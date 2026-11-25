"""哔哩哔哩追番/追剧：读取关注列表、订阅剧集并自动下载更新。"""

from __future__ import annotations

import logging
import sqlite3
import threading
import time
import uuid
from typing import Any

import requests

from . import bilibili, db
from .config import Settings
from .downloader import JobCreateError, JobManager
from .models import JobCreateBody, JobItemInput

logger = logging.getLogger(__name__)

FOLLOW_LIST_URL = "https://api.bilibili.com/x/space/bangumi/follow/list"
SEASON_URL = "https://api.bilibili.com/pgc/view/web/season"
PAGE_SIZE = 24
JOB_CHUNK_SIZE = 50
HTTP_TIMEOUT = 20
PUBLISH_GRACE = 60

STATUS_QUERIES = """
    SELECT subscription_id,
           COUNT(*) AS episode_count,
           SUM(status = 'done') AS done_count,
           SUM(status = 'queued') AS queued_count,
           SUM(status = 'failed') AS failed_count,
           SUM(status = 'skipped') AS skipped_count
      FROM bangumi_episodes
     GROUP BY subscription_id
"""


class BangumiError(Exception):
    """B 站追番接口失败，消息可直接展示给用户。"""


def _https(url: str | None) -> str | None:
    """把 B 站返回的 http 图片地址升级为 https，避免页面混合内容拦截。"""
    if not url:
        return None
    return url.replace("http://", "https://", 1) if url.startswith("http://") else url


def _api_message(code: Any, message: Any) -> str:
    if code == -101:
        return "哔哩哔哩登录已失效，请到「账号」页重新扫码登录"
    if code == 53013:
        return "该账号的追番/追剧列表未公开，请先在哔哩哔哩隐私设置中开放"
    return f"哔哩哔哩接口返回错误（{code}）：{message or '未知错误'}"


def _request_json(
    url: str,
    params: dict[str, Any] | None = None,
    settings: Settings | None = None,
    *,
    require_login: bool = False,
) -> dict:
    """调用 B 站接口并统一处理网络与业务错误。"""
    cookies = bilibili.cookie_values(settings) if settings else {}
    if require_login and not cookies.get("SESSDATA"):
        raise BangumiError("请先在「账号」页扫码登录哔哩哔哩")
    try:
        response = requests.get(
            url,
            params=params,
            headers=bilibili.HEADERS,
            cookies=cookies,
            timeout=HTTP_TIMEOUT,
        )
        response.raise_for_status()
        payload = response.json()
    except requests.RequestException as exc:
        raise BangumiError(f"无法连接哔哩哔哩：{exc}") from exc
    except ValueError as exc:
        raise BangumiError("哔哩哔哩返回了无效响应") from exc
    if not isinstance(payload, dict):
        raise BangumiError("哔哩哔哩返回了无效响应")
    if payload.get("code") != 0:
        raise BangumiError(_api_message(payload.get("code"), payload.get("message")))
    return payload


def _follow_item(raw: dict, media_type: int) -> dict:
    """把关注列表条目裁剪成前端需要的字段。"""
    raw_new_ep = raw.get("new_ep") if isinstance(raw.get("new_ep"), dict) else None
    return {
        "season_id": int(raw.get("season_id") or 0),
        "media_id": raw.get("media_id"),
        "type": media_type,
        "title": raw.get("title") or "未命名",
        "cover": _https(raw.get("cover")),
        "season_title": raw.get("season_title"),
        "total_count": int(raw.get("total_count") or 0),
        "is_finish": bool(raw.get("is_finish")),
        "new_ep": {
            "title": raw_new_ep.get("index_show") or raw_new_ep.get("title"),
            "pub_time": raw_new_ep.get("pub_time"),
        }
        if raw_new_ep
        else None,
        "url": f"https://www.bilibili.com/bangumi/play/ss{raw.get('season_id')}",
    }


def fetch_follow_list(
    settings: Settings,
    media_type: int,
    page: int = 1,
    vmid: str | None = None,
) -> dict:
    """读取追番（type=1）或追剧（type=2）关注列表。

    私有列表需要登录 Cookie；显式传入 vmid 时允许读取公开账号。
    """
    if media_type not in (1, 2):
        raise BangumiError("无效的追番类型")
    uid = str(vmid or bilibili.self_uid(settings) or "").strip()
    if not uid.isdigit():
        raise BangumiError("请先在「账号」页扫码登录哔哩哔哩")

    payload = _request_json(
        FOLLOW_LIST_URL,
        {
            "vmid": uid,
            "type": media_type,
            "pn": page,
            "ps": PAGE_SIZE,
            "follow_status": 0,
            "playform": "web",
        },
        settings,
        require_login=not vmid,
    )
    data = payload.get("data")
    if not isinstance(data, dict):
        data = {}
    raw_list = data.get("list") if isinstance(data.get("list"), list) else []
    items = [
        _follow_item(raw, media_type)
        for raw in raw_list
        if isinstance(raw, dict) and raw.get("season_id")
    ]
    try:
        total = int(data.get("total") or 0)
    except (TypeError, ValueError):
        total = 0
    return {
        "items": items,
        "page": page,
        "total": total,
        "has_more": page * PAGE_SIZE < total,
    }


def fetch_season(settings: Settings, season_id: int) -> dict:
    """读取剧集详情与已发布的正片列表（顺序与 yt-dlp 播放列表一致）。"""
    payload = _request_json(SEASON_URL, {"season_id": season_id}, settings)
    result = payload.get("result")
    if not isinstance(result, dict) or not result:
        raise BangumiError("未找到该剧集信息")

    now = int(time.time())
    episodes: list[dict] = []
    raw_episodes = result.get("episodes")
    if not isinstance(raw_episodes, list):
        raw_episodes = []
    for position, raw in enumerate(raw_episodes, start=1):
        if not isinstance(raw, dict):
            continue
        try:
            ep_id = int(raw.get("ep_id") or raw.get("id") or 0)
        except (TypeError, ValueError):
            continue
        if ep_id <= 0:
            continue
        pub_time = raw.get("pub_time")
        if isinstance(pub_time, (int, float)) and pub_time > now + PUBLISH_GRACE:
            continue
        raw_duration = raw.get("duration")
        duration = float(raw_duration) / 1000 if isinstance(raw_duration, (int, float)) else None
        episodes.append(
            {
                "ep_id": ep_id,
                "idx": position,
                "title": raw.get("show_title")
                or raw.get("title")
                or f"第 {position} 话",
                "long_title": raw.get("long_title"),
                "duration": duration,
                "cover": _https(raw.get("cover")),
                "pub_time": pub_time,
                "url": raw.get("link")
                or f"https://www.bilibili.com/bangumi/play/ep{ep_id}",
            }
        )
    return {
        "season_id": int(season_id),
        "media_id": result.get("media_id"),
        "title": result.get("title") or "未命名剧集",
        "season_title": result.get("season_title"),
        "cover": _https(result.get("cover")),
        "total_count": len(episodes),
        "episodes": episodes,
    }


class BangumiManager:
    """维护追番订阅，并定时检查更新、创建下载任务。"""

    def __init__(self, settings: Settings, jobs: JobManager) -> None:
        self.settings = settings
        self.jobs = jobs
        self.db_path = settings.data_dir / "nas-media-down.db"
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._locks: dict[str, threading.Lock] = {}
        self._locks_guard = threading.Lock()
        self._db_lock = threading.Lock()

    # ------------------------------------------------------------- lifecycle

    def start(self) -> None:
        """启动后台检查线程。"""
        if self._thread is not None:
            return
        self._thread = threading.Thread(
            target=self._loop, name="bangumi-check", daemon=True
        )
        self._thread.start()

    def stop(self) -> None:
        """停止后台检查线程。"""
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=5)
            self._thread = None

    def _loop(self) -> None:
        interval = max(60, self.settings.bangumi_check_interval)
        delay = min(60, interval)
        while not self._stop.wait(delay):
            try:
                self.check_all()
            except Exception:  # noqa: BLE001 - 后台线程不能因单次异常退出
                logger.exception("追番自动检查失败")
            delay = interval

    # ------------------------------------------------------------ operations

    def list_subscriptions(self) -> list[dict]:
        """返回全部订阅及剧集下载统计。"""
        with db.session(self.db_path) as conn:
            rows = [
                dict(row)
                for row in conn.execute(
                    "SELECT * FROM bangumi_subscriptions ORDER BY created_at DESC"
                ).fetchall()
            ]
            stats = {
                row["subscription_id"]: dict(row)
                for row in conn.execute(STATUS_QUERIES).fetchall()
            }
            latest = {
                row["subscription_id"]: dict(row)
                for row in conn.execute(
                    """
                    SELECT e.subscription_id, e.title, e.status, e.idx
                      FROM bangumi_episodes e
                      JOIN (
                            SELECT subscription_id, MAX(idx) AS idx
                              FROM bangumi_episodes
                             GROUP BY subscription_id
                           ) m
                        ON m.subscription_id = e.subscription_id AND m.idx = e.idx
                    """
                ).fetchall()
            }
        return [
            self._sub_payload(row, stats.get(row["id"]), latest.get(row["id"]))
            for row in rows
        ]

    def get_subscription(self, sub_id: str) -> dict | None:
        """返回单个订阅，不存在时返回 None。"""
        with db.session(self.db_path) as conn:
            row = conn.execute(
                "SELECT * FROM bangumi_subscriptions WHERE id = ?", (sub_id,)
            ).fetchone()
        return dict(row) if row else None

    def subscriptions_by_season(self) -> dict[int, str]:
        """season_id 到订阅 ID 的映射，供关注列表标记订阅状态。"""
        with db.session(self.db_path) as conn:
            rows = conn.execute(
                "SELECT season_id, id FROM bangumi_subscriptions"
            ).fetchall()
        return {int(row["season_id"]): row["id"] for row in rows}

    def subscribe(self, media_type: int, season_id: int, mode: str) -> dict:
        """创建订阅；mode=all 时立即把已发布剧集加入下载队列。"""
        if media_type not in (1, 2):
            raise BangumiError("无效的追番类型")
        if mode not in ("watch", "all"):
            raise BangumiError("无效的订阅模式")

        season = fetch_season(self.settings, season_id)
        now = db.now_ts()
        url = f"https://www.bilibili.com/bangumi/play/ss{season_id}"
        existing = self._subscription_by_season(season_id)

        if existing is None:
            sub_id = uuid.uuid4().hex
            try:
                with self._db_lock, db.session(self.db_path) as conn:
                    conn.execute(
                        """
                        INSERT INTO bangumi_subscriptions
                               (id, season_id, media_id, type, title, cover, url,
                                auto_download, enabled, last_check_at, last_error, created_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, 1, 1, ?, NULL, ?)
                        """,
                        (
                            sub_id,
                            season_id,
                            season.get("media_id"),
                            media_type,
                            season["title"],
                            season.get("cover"),
                            url,
                            now,
                            now,
                        ),
                    )
            except sqlite3.IntegrityError:
                # 并发请求已经创建过同一部剧的订阅，复用已有记录
                existing = self._subscription_by_season(season_id)
                if existing is None:
                    raise
                sub_id = existing["id"]
            else:
                self._record_episodes(sub_id, season["episodes"], "skipped")
        if existing is not None:
            sub_id = existing["id"]
            self._touch_subscription(
                sub_id,
                title=season["title"],
                cover=season.get("cover"),
                last_check_at=now,
            )

        job_count = 0
        error: str | None = None
        if mode == "all":
            sub = self.get_subscription(sub_id)
            if sub is not None:
                result = self.download_all(sub_id)
                job_count = result["job_count"]
                error = result.get("error")

        return {
            "subscription": self._payload_for(sub_id),
            "job_count": job_count,
            "error": error,
        }

    def update_subscription(
        self,
        sub_id: str,
        enabled: bool | None = None,
        auto_download: bool | None = None,
    ) -> dict | None:
        """切换订阅启用状态或自动下载开关。"""
        assignments: list[str] = []
        values: list[Any] = []
        if enabled is not None:
            assignments.append("enabled = ?")
            values.append(1 if enabled else 0)
        if auto_download is not None:
            assignments.append("auto_download = ?")
            values.append(1 if auto_download else 0)
        if not assignments:
            return self._payload_for(sub_id)
        values.append(sub_id)
        with self._db_lock, db.session(self.db_path) as conn:
            cursor = conn.execute(
                f"UPDATE bangumi_subscriptions SET {', '.join(assignments)} WHERE id = ?",
                values,
            )
            if cursor.rowcount == 0:
                return None
        return self._payload_for(sub_id)

    def delete_subscription(self, sub_id: str) -> bool:
        """删除订阅及其剧集记录（不删除已下载文件）。"""
        with self._db_lock, db.session(self.db_path) as conn:
            cursor = conn.execute(
                "DELETE FROM bangumi_subscriptions WHERE id = ?", (sub_id,)
            )
            return cursor.rowcount > 0

    def check(self, sub_id: str) -> dict | None:
        """手动检查单个订阅；订阅繁忙时返回 busy 标记。"""
        sub = self.get_subscription(sub_id)
        if sub is None:
            return None
        lock = self._lock_for(sub_id)
        if not lock.acquire(blocking=False):
            return {"checked": False, "busy": True, "new_episodes": 0, "job_count": 0}
        try:
            return self._check_locked(sub)
        finally:
            lock.release()

    def check_all(self) -> None:
        """检查所有启用的订阅。"""
        with db.session(self.db_path) as conn:
            rows = [
                dict(row)
                for row in conn.execute(
                    "SELECT * FROM bangumi_subscriptions WHERE enabled = 1"
                ).fetchall()
            ]
        for sub in rows:
            lock = self._lock_for(sub["id"])
            if not lock.acquire(blocking=False):
                continue
            try:
                self._check_locked(sub)
            except Exception:  # noqa: BLE001 - 单个订阅失败不影响其他订阅
                logger.exception("检查订阅失败：%s", sub["id"])
            finally:
                lock.release()

    def download_all(self, sub_id: str) -> dict:
        """把尚未下载/待下载的已发布剧集全部加入队列。"""
        sub = self.get_subscription(sub_id)
        if sub is None:
            raise KeyError(sub_id)
        lock = self._lock_for(sub_id)
        if not lock.acquire(blocking=False):
            return {
                "episode_count": 0,
                "job_count": 0,
                "error": "正在检查该订阅，请稍后重试",
                "subscription": self._payload_for(sub_id),
            }
        try:
            season = fetch_season(self.settings, sub["season_id"])
            self._reconcile_jobs(sub_id)
            known = self._episode_rows(sub_id)

            missing = [ep for ep in season["episodes"] if ep["ep_id"] not in known]
            if missing:
                self._record_episodes(sub_id, missing, "skipped")
                known = self._episode_rows(sub_id)

            targets = [
                ep
                for ep in season["episodes"]
                if known.get(ep["ep_id"], {}).get("status")
                in (None, "skipped", "failed")
            ]
            result = self._enqueue_episodes(sub, targets)
            self._touch_subscription(
                sub_id, last_check_at=db.now_ts(), last_error=result.get("error")
            )
            return {
                "episode_count": len(targets),
                "job_count": result["job_count"],
                "error": result.get("error"),
                "subscription": self._payload_for(sub_id),
            }
        finally:
            lock.release()

    def season_detail(self, season_id: int) -> dict:
        """返回剧集列表；已订阅时附带每集的下载状态。"""
        season = fetch_season(self.settings, season_id)
        sub = self._subscription_by_season(season_id)
        statuses: dict[int, str] = {}
        if sub is not None:
            self._reconcile_jobs(sub["id"])
            statuses = {
                ep_id: str(row["status"])
                for ep_id, row in self._episode_rows(sub["id"]).items()
            }
        for ep in season["episodes"]:
            ep["status"] = statuses.get(ep["ep_id"])
        season["subscribed"] = sub is not None
        return season

    def download_episodes(self, season_id: int, indices: list[int]) -> dict:
        """按剧集序号下载选中的剧集；未订阅时直接创建任务。"""
        season = fetch_season(self.settings, season_id)
        by_idx = {int(ep["idx"]): ep for ep in season["episodes"]}
        selected = [by_idx[idx] for idx in sorted(set(indices)) if idx in by_idx]
        if not selected:
            raise BangumiError("所选剧集不存在或尚未发布")

        sub = self._subscription_by_season(season_id)
        if sub is None:
            pseudo = {
                "url": f"https://www.bilibili.com/bangumi/play/ss{season_id}",
                "title": season["title"],
                "season_id": season_id,
            }
            result = self._enqueue_episodes(pseudo, selected)
            return {
                "episode_count": len(selected),
                "job_count": result["job_count"],
                "error": result.get("error"),
                "subscription": None,
            }

        lock = self._lock_for(sub["id"])
        if not lock.acquire(blocking=False):
            raise BangumiError("正在检查该订阅，请稍后重试")
        try:
            self._reconcile_jobs(sub["id"])
            known = self._episode_rows(sub["id"])
            available = [
                ep
                for ep in selected
                if known.get(ep["ep_id"], {}).get("status") not in ("done", "queued")
            ]
            if not available:
                raise BangumiError("所选剧集已下载或正在下载")

            missing = [ep for ep in available if ep["ep_id"] not in known]
            if missing:
                self._record_episodes(sub["id"], missing, "skipped")
            result = self._enqueue_episodes(sub, available)
            self._touch_subscription(
                sub["id"], last_check_at=db.now_ts(), last_error=result.get("error")
            )
            return {
                "episode_count": len(available),
                "job_count": result["job_count"],
                "error": result.get("error"),
                "subscription": self._payload_for(sub["id"]),
            }
        finally:
            lock.release()

    # --------------------------------------------------------------- internal

    def _lock_for(self, sub_id: str) -> threading.Lock:
        with self._locks_guard:
            return self._locks.setdefault(sub_id, threading.Lock())

    def _subscription_by_season(self, season_id: int) -> dict | None:
        with db.session(self.db_path) as conn:
            row = conn.execute(
                "SELECT * FROM bangumi_subscriptions WHERE season_id = ?",
                (season_id,),
            ).fetchone()
        return dict(row) if row else None

    def _check_locked(self, sub: dict) -> dict:
        now = db.now_ts()
        try:
            season = fetch_season(self.settings, sub["season_id"])
        except BangumiError as exc:
            self._touch_subscription(
                sub["id"], last_check_at=now, last_error=str(exc)
            )
            return {
                "checked": True,
                "new_episodes": 0,
                "job_count": 0,
                "error": str(exc),
            }

        self._reconcile_jobs(sub["id"])
        self._touch_subscription(
            sub["id"], title=season["title"], cover=season.get("cover")
        )

        known = self._episode_rows(sub["id"])
        unseen = [ep for ep in season["episodes"] if ep["ep_id"] not in known]
        if unseen:
            status = "skipped"
            self._record_episodes(sub["id"], unseen, status)

        job_count = 0
        error: str | None = None
        if unseen and sub["auto_download"]:
            result = self._enqueue_episodes(sub, unseen)
            job_count = result["job_count"]
            error = result.get("error")

        self._touch_subscription(sub["id"], last_check_at=now, last_error=error)
        return {
            "checked": True,
            "new_episodes": len(unseen),
            "job_count": job_count,
            "error": error,
        }

    def _enqueue_episodes(self, sub: dict, episodes: list[dict]) -> dict:
        """按块创建播放列表任务，并记录每个剧集对应的任务。"""
        if not episodes:
            return {"job_count": 0, "error": None}
        sub_id = sub.get("id")
        chunk_size = max(1, min(JOB_CHUNK_SIZE, self.settings.max_playlist_items))
        job_count = 0
        errors: list[str] = []
        for start in range(0, len(episodes), chunk_size):
            chunk = episodes[start : start + chunk_size]
            body = JobCreateBody(
                url=sub["url"],
                kind="playlist",
                playlist_id=str(sub["season_id"]),
                playlist_title=sub["title"],
                entries=[
                    JobItemInput(
                        index=ep["idx"],
                        title=ep["title"],
                        duration=ep.get("duration"),
                        thumbnail=ep.get("cover"),
                    )
                    for ep in chunk
                ],
            )
            try:
                runtime = self.jobs.create(body)
            except JobCreateError as exc:
                errors.append(str(exc))
                if sub_id is not None:
                    self._mark_episodes(sub_id, chunk, "failed")
                continue
            if sub_id is not None:
                self._mark_episodes(sub_id, chunk, "queued", runtime.id)
            job_count += 1
        return {
            "job_count": job_count,
            "error": "；".join(errors) if errors else None,
        }

    def _record_episodes(
        self, sub_id: str, episodes: list[dict], status: str
    ) -> None:
        """记录尚未入库的剧集，已存在的不覆盖状态。"""
        if not episodes:
            return
        now = db.now_ts()
        with self._db_lock, db.session(self.db_path) as conn:
            conn.executemany(
                """
                INSERT OR IGNORE INTO bangumi_episodes
                       (subscription_id, ep_id, idx, title, duration, cover,
                        status, job_id, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?)
                """,
                [
                    (
                        sub_id,
                        ep["ep_id"],
                        ep["idx"],
                        ep["title"],
                        ep.get("duration"),
                        ep.get("cover"),
                        status,
                        now,
                    )
                    for ep in episodes
                ],
            )

    def _mark_episodes(
        self,
        sub_id: str,
        episodes: list[dict],
        status: str,
        job_id: str | None = None,
    ) -> None:
        """更新剧集状态与对应任务 ID。"""
        if not episodes:
            return
        now = db.now_ts()
        with self._db_lock, db.session(self.db_path) as conn:
            conn.executemany(
                """
                UPDATE bangumi_episodes
                   SET status = ?, job_id = COALESCE(?, job_id), updated_at = ?
                 WHERE subscription_id = ? AND ep_id = ?
                """,
                [
                    (status, job_id, now, sub_id, ep["ep_id"])
                    for ep in episodes
                ],
            )

    def _episode_rows(self, sub_id: str) -> dict[int, dict]:
        with db.session(self.db_path) as conn:
            rows = conn.execute(
                "SELECT ep_id, idx, title, status, job_id FROM bangumi_episodes WHERE subscription_id = ?",
                (sub_id,),
            ).fetchall()
        return {int(row["ep_id"]): dict(row) for row in rows}

    def _reconcile_jobs(self, sub_id: str) -> None:
        """把剧集状态与对应下载任务同步，包括任务页里的手动重试。"""
        sub = self.get_subscription(sub_id)
        if sub is None:
            return
        rows = self._episode_rows(sub_id)
        queued = [
            row for row in rows.values() if row["status"] == "queued" and row["job_id"]
        ]
        failed = [row for row in rows.values() if row["status"] == "failed"]
        if not queued and not failed:
            return

        job_status: dict[str, str] = {}
        item_status: dict[tuple[str, int], str] = {}
        job_ids = sorted({row["job_id"] for row in queued})
        if job_ids:
            placeholders = ",".join("?" for _ in job_ids)
            with db.session(self.db_path) as conn:
                job_rows = conn.execute(
                    f"SELECT id, status FROM jobs WHERE id IN ({placeholders})", job_ids
                ).fetchall()
                item_rows = conn.execute(
                    f"SELECT job_id, idx, status FROM job_items WHERE job_id IN ({placeholders})",
                    job_ids,
                ).fetchall()
            job_status = {row["id"]: row["status"] for row in job_rows}
            item_status = {
                (row["job_id"], int(row["idx"])): row["status"] for row in item_rows
            }

        retried: dict[int, tuple[str, str]] = {}
        if failed:
            wanted = {int(row["idx"]) for row in failed}
            with db.session(self.db_path) as conn:
                matched = conn.execute(
                    """
                    SELECT i.job_id, i.idx, i.status AS item_status,
                           j.status AS job_status
                      FROM job_items i
                      JOIN jobs j ON j.id = i.job_id
                     WHERE j.url = ?
                     ORDER BY j.created_at DESC
                    """,
                    (sub["url"],),
                ).fetchall()
            for row in matched:
                idx = int(row["idx"])
                if idx not in wanted:
                    continue
                if row["item_status"] == "done":
                    retried[idx] = ("done", row["job_id"])
                elif row["item_status"] in (
                    "pending",
                    "downloading",
                    "processing",
                ) and row["job_status"] in ("queued", "running"):
                    retried.setdefault(idx, ("queued", row["job_id"]))

        now = db.now_ts()
        updates: list[tuple[str, str | None, int, str, int]] = []

        for row in queued:
            job = job_status.get(row["job_id"])
            if job is None:
                updates.append(("failed", None, now, sub_id, int(row["ep_id"])))
                continue
            item = item_status.get((row["job_id"], int(row["idx"])))
            if item == "done":
                updates.append(("done", None, now, sub_id, int(row["ep_id"])))
            elif item in ("failed", "cancelled") or job in (
                "failed",
                "partial",
                "cancelled",
                "interrupted",
            ):
                fallback = retried.get(int(row["idx"]))
                if fallback is not None:
                    updates.append(
                        (fallback[0], fallback[1], now, sub_id, int(row["ep_id"]))
                    )
                else:
                    updates.append(("failed", None, now, sub_id, int(row["ep_id"])))
        for row in failed:
            retried_idx = int(row["idx"])
            if retried_idx not in retried:
                continue
            status, job_id = retried[retried_idx]
            updates.append((status, job_id, now, sub_id, int(row["ep_id"])))

        if not updates:
            return
        with self._db_lock, db.session(self.db_path) as conn:
            conn.executemany(
                """
                UPDATE bangumi_episodes
                   SET status = ?, job_id = COALESCE(?, job_id), updated_at = ?
                 WHERE subscription_id = ? AND ep_id = ?
                """,
                updates,
            )

    def _touch_subscription(self, sub_id: str, **fields: Any) -> None:
        """更新订阅的元信息，忽略未提供的字段。"""
        allowed = {"title", "cover", "last_check_at", "last_error"}
        assignments = [f"{key} = ?" for key in fields if key in allowed]
        if not assignments:
            return
        values = [value for key, value in fields.items() if key in allowed]
        values.append(sub_id)
        with self._db_lock, db.session(self.db_path) as conn:
            conn.execute(
                f"UPDATE bangumi_subscriptions SET {', '.join(assignments)} WHERE id = ?",
                values,
            )

    def _payload_for(self, sub_id: str) -> dict | None:
        for item in self.list_subscriptions():
            if item["id"] == sub_id:
                return item
        return None

    @staticmethod
    def _sub_payload(row: dict, stat: dict | None, latest: dict | None) -> dict:
        stat = stat or {}
        return {
            "id": row["id"],
            "season_id": row["season_id"],
            "media_id": row["media_id"],
            "type": row["type"],
            "title": row["title"],
            "cover": row["cover"],
            "url": row["url"],
            "auto_download": bool(row["auto_download"]),
            "enabled": bool(row["enabled"]),
            "last_check_at": row["last_check_at"],
            "last_error": row["last_error"],
            "created_at": row["created_at"],
            "episode_count": int(stat.get("episode_count") or 0),
            "done_count": int(stat.get("done_count") or 0),
            "queued_count": int(stat.get("queued_count") or 0),
            "failed_count": int(stat.get("failed_count") or 0),
            "skipped_count": int(stat.get("skipped_count") or 0),
            "latest_title": latest.get("title") if latest else None,
            "latest_status": latest.get("status") if latest else None,
        }
