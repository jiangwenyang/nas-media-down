"""下载任务管理：线程池执行、进度回调、取消与持久化。"""

from __future__ import annotations

import logging
import os
import re
import shutil
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path

import yt_dlp
from yt_dlp.utils import DownloadCancelled

from . import db
from .config import Settings
from .errors import friendly_error
from .models import JobCreateBody
from .probe import validate_url

logger = logging.getLogger(__name__)

ACTIVE_STATUSES = ("queued", "running")
MAX_QUEUED_JOBS = 20
MIN_FREE_BYTES = 1024**3
FLUSH_INTERVAL = 2.0

_INVALID_FILENAME_CHARS = re.compile(r'[<>:"/\\|?*\x00-\x1f]')


class JobCreateError(Exception):
    """任务创建失败，带 HTTP 状态码。"""

    def __init__(self, message: str, status_code: int = 400) -> None:
        super().__init__(message)
        self.status_code = status_code


def build_items_spec(indices: list[int]) -> str:
    """把索引列表压缩成 yt-dlp 的 playlist_items 语法，如 [1,3,4,5] -> '1,3-5'。"""
    ordered = sorted(set(indices))
    if not ordered:
        raise ValueError("至少需要选择一个条目")
    parts: list[str] = []
    start = previous = ordered[0]
    for number in ordered[1:]:
        if number == previous + 1:
            previous = number
            continue
        parts.append(str(start) if start == previous else f"{start}-{previous}")
        start = previous = number
    parts.append(str(start) if start == previous else f"{start}-{previous}")
    return ",".join(parts)


def sanitize_filename(name: str, max_bytes: int = 80) -> str:
    """清洗目录名：去掉非法字符，并按 UTF-8 字节截断。"""
    cleaned = _INVALID_FILENAME_CHARS.sub("_", name or "").strip().strip(".")
    cleaned = re.sub(r"\s+", " ", cleaned)
    if not cleaned:
        cleaned = "未命名"
    encoded = cleaned.encode("utf-8")
    if len(encoded) > max_bytes:
        cleaned = encoded[:max_bytes].decode("utf-8", "ignore").rstrip()
    return cleaned or "未命名"


@dataclass
class ItemState:
    """单个待下载条目的运行期状态。"""

    idx: int
    title: str
    thumbnail: str | None = None
    duration: float | None = None
    status: str = "pending"
    progress: float = 0.0
    downloaded_bytes: int | None = None
    total_bytes: int | None = None
    speed: float | None = None
    eta: int | None = None
    filename: str | None = None
    error: str | None = None


@dataclass
class JobRuntime:
    """一个下载任务的运行期状态。"""

    id: str
    url: str
    kind: str
    title: str
    target_dir: Path
    items: dict[int, ItemState]
    playlist_id: str | None = None
    playlist_title: str | None = None
    playlist_count: int | None = None
    items_spec: str | None = None
    status: str = "queued"
    error: str | None = None
    progress: float = 0.0
    created_at: int = field(default_factory=db.now_ts)
    started_at: int | None = None
    finished_at: int | None = None
    current_idx: int | None = None
    cancel: threading.Event = field(default_factory=threading.Event)
    lock: threading.Lock = field(default_factory=threading.Lock)
    last_flush: float = 0.0


class _JobLogger:
    """接收 yt-dlp 日志，保留最近一条错误用于展示。"""

    def __init__(self, runtime: JobRuntime) -> None:
        self._runtime = runtime

    def debug(self, msg: str) -> None:
        return None

    def info(self, msg: str) -> None:
        return None

    def warning(self, msg: str) -> None:
        self._runtime.error = str(msg)[:300]

    def error(self, msg: str) -> None:
        self._runtime.error = str(msg).removeprefix("ERROR: ").strip()[:300]


class JobManager:
    """维护活动任务、执行下载并落库。"""

    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.db_path = settings.data_dir / "nas-media-down.db"
        self.executor = ThreadPoolExecutor(
            max_workers=settings.max_concurrent, thread_name_prefix="download"
        )
        self._jobs: dict[str, JobRuntime] = {}
        self._lock = threading.Lock()

    # ------------------------------------------------------------------ create

    def create(self, body: JobCreateBody) -> JobRuntime:
        """校验请求、创建任务并提交线程池。"""
        url = validate_url(body.url)
        self.settings.download_dir.mkdir(parents=True, exist_ok=True)

        if body.kind == "video":
            entry = body.entries[0]
            entries = [
                ItemState(
                    idx=1,
                    title=entry.title or "未命名视频",
                    thumbnail=entry.thumbnail,
                    duration=entry.duration,
                )
            ]
            target_dir = self.settings.download_dir
            title = entry.title or url
            items_spec = None
            playlist_title = None
            playlist_id = None
            playlist_count = None
        else:
            seen: dict[int, ItemState] = {}
            for entry in body.entries:
                if entry.index in seen:
                    continue
                seen[entry.index] = ItemState(
                    idx=entry.index,
                    title=entry.title or f"第 {entry.index} 个视频",
                    thumbnail=entry.thumbnail,
                    duration=entry.duration,
                )
            if not seen:
                raise JobCreateError("请至少选择一个视频")
            if len(seen) > self.settings.max_playlist_items:
                raise JobCreateError(
                    f"一次最多下载 {self.settings.max_playlist_items} 个条目"
                )
            entries = [seen[idx] for idx in sorted(seen)]
            playlist_title = (body.playlist_title or "播放列表").strip() or "播放列表"
            target_dir = self.settings.download_dir / sanitize_filename(playlist_title)
            title = playlist_title
            items_spec = build_items_spec([item.idx for item in entries])
            playlist_id = body.playlist_id
            playlist_count = len(entries)

        with self._lock:
            if len(self._jobs) >= MAX_QUEUED_JOBS:
                raise JobCreateError("当前排队任务过多，请稍后再试", status_code=429)

        free_bytes = shutil.disk_usage(self.settings.download_dir).free
        if free_bytes < MIN_FREE_BYTES:
            raise JobCreateError("下载目录剩余空间不足 1GB，请先清理磁盘", status_code=507)

        runtime = JobRuntime(
            id=uuid.uuid4().hex,
            url=url,
            kind=body.kind,
            title=title,
            target_dir=target_dir,
            items={item.idx: item for item in entries},
            playlist_id=playlist_id,
            playlist_title=playlist_title,
            playlist_count=playlist_count,
            items_spec=items_spec,
        )

        self._persist_new_job(runtime)
        with self._lock:
            self._jobs[runtime.id] = runtime

        try:
            self.executor.submit(self._run, runtime.id)
        except RuntimeError as exc:
            self._finish(runtime, "failed", f"任务调度失败：{exc}")
            raise JobCreateError("任务调度失败，请稍后重试", status_code=503) from exc

        return runtime

    # ----------------------------------------------------------------- storage

    def _persist_new_job(self, runtime: JobRuntime) -> None:
        with db.session(self.db_path) as conn:
            conn.execute(
                """
                INSERT INTO jobs (id, url, kind, title, playlist_id, playlist_title,
                                  playlist_count, items_spec, status, progress, error,
                                  created_at, started_at, finished_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    runtime.id,
                    runtime.url,
                    runtime.kind,
                    runtime.title,
                    runtime.playlist_id,
                    runtime.playlist_title,
                    runtime.playlist_count,
                    runtime.items_spec,
                    runtime.status,
                    runtime.progress,
                    runtime.error,
                    runtime.created_at,
                    runtime.started_at,
                    runtime.finished_at,
                ),
            )
            conn.executemany(
                """
                INSERT INTO job_items (job_id, idx, video_id, title, duration, thumbnail,
                                       status, progress)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    (
                        runtime.id,
                        item.idx,
                        None,
                        item.title,
                        item.duration,
                        item.thumbnail,
                        item.status,
                        item.progress,
                    )
                    for item in runtime.items.values()
                ],
            )

    def _flush(self, runtime: JobRuntime) -> None:
        """把内存状态写入 SQLite；调用方不得持有 runtime.lock。"""
        with runtime.lock:
            job_values = (
                runtime.status,
                round(runtime.progress, 4),
                runtime.error,
                runtime.started_at,
                runtime.finished_at,
                runtime.id,
            )
            item_values = [
                (
                    item.status,
                    round(item.progress, 4),
                    item.downloaded_bytes,
                    item.total_bytes,
                    item.speed,
                    item.eta,
                    item.filename,
                    item.error,
                    item.title,
                    runtime.id,
                    item.idx,
                )
                for item in runtime.items.values()
            ]
        with db.session(self.db_path) as conn:
            conn.execute(
                """
                UPDATE jobs
                   SET status = ?, progress = ?, error = ?,
                       started_at = ?, finished_at = ?
                 WHERE id = ?
                """,
                job_values,
            )
            conn.executemany(
                """
                UPDATE job_items
                   SET status = ?, progress = ?, downloaded_bytes = ?, total_bytes = ?,
                       speed = ?, eta = ?, filename = ?, error = ?, title = ?
                 WHERE job_id = ? AND idx = ?
                """,
                item_values,
            )

    def _maybe_flush(self, runtime: JobRuntime) -> None:
        now = time.monotonic()
        if now - runtime.last_flush < FLUSH_INTERVAL:
            return
        runtime.last_flush = now
        self._flush(runtime)

    # --------------------------------------------------------------- execution

    def _build_opts(self, runtime: JobRuntime) -> dict:
        opts: dict = {
            "quiet": True,
            "no_warnings": True,
            "noprogress": True,
            "socket_timeout": 30,
            "retries": 5,
            "fragment_retries": 5,
            "format": "bv*+ba/b",
            "merge_output_format": self.settings.merge_format,
            "outtmpl": {"default": "%(title).180B [%(id)s].%(ext)s"},
            "paths": {"home": str(runtime.target_dir)},
            "noplaylist": runtime.kind == "video",
            "overwrites": False,
            "progress_hooks": [lambda data: self._on_progress(runtime, data)],
            "postprocessor_hooks": [lambda data: self._on_postprocess(runtime, data)],
            "logger": _JobLogger(runtime),
        }
        if runtime.items_spec:
            opts["playlist_items"] = runtime.items_spec
        if self.settings.cookies_file and self.settings.cookies_file.exists():
            opts["cookiefile"] = str(self.settings.cookies_file)
        if shutil.which("deno"):
            opts["js_runtimes"] = {"deno": {}}
        return opts

    def _run(self, job_id: str) -> None:
        with self._lock:
            runtime = self._jobs.get(job_id)
        if runtime is None:
            return

        if runtime.cancel.is_set():
            self._finish(runtime, "cancelled")
            return

        with runtime.lock:
            runtime.status = "running"
            runtime.started_at = db.now_ts()
        self._flush(runtime)

        runtime.target_dir.mkdir(parents=True, exist_ok=True)
        try:
            with yt_dlp.YoutubeDL(self._build_opts(runtime)) as ydl:
                ydl.download([runtime.url])
        except DownloadCancelled:
            self._finish(runtime, "cancelled")
            return
        except Exception as exc:  # noqa: BLE001 - 统一转成用户可读错误
            logger.exception("下载任务失败：%s", runtime.id)
            self._finish(runtime, "failed", friendly_error(exc))
            return

        self._finish(runtime, "completed")

    def _finish(self, runtime: JobRuntime, status: str, error: str | None = None) -> None:
        """统一收尾：更新状态、兜底条目状态、落库并从活动表移除。"""
        with runtime.lock:
            if status == "completed":
                for item in runtime.items.values():
                    if item.status not in ("failed",):
                        item.status = "done"
                        item.progress = 1.0
                        item.speed = None
                        item.eta = 0
            elif status == "cancelled":
                for item in runtime.items.values():
                    if item.status in ("pending", "downloading", "processing"):
                        item.status = "cancelled"
                runtime.status = status
            elif status == "failed":
                for item in runtime.items.values():
                    if item.status in ("pending", "downloading", "processing"):
                        item.status = "failed"
                        item.error = item.error or error
            runtime.status = status
            runtime.error = error
            runtime.finished_at = db.now_ts()
            runtime.progress = self._progress_locked(runtime)
        self._flush(runtime)
        with self._lock:
            self._jobs.pop(runtime.id, None)

    @staticmethod
    def _progress_locked(runtime: JobRuntime) -> float:
        total = len(runtime.items)
        if total == 0:
            return 0.0
        completed = sum(
            1 for item in runtime.items.values() if item.status in ("done", "processing")
        )
        current = sum(
            item.progress for item in runtime.items.values() if item.status == "downloading"
        )
        return min(1.0, (completed + current) / total)

    @staticmethod
    def _resolve_index_locked(runtime: JobRuntime, info: dict) -> int | None:
        raw = info.get("playlist_index")
        try:
            index = int(raw) if raw is not None else None
        except (TypeError, ValueError):
            index = None
        if index is not None and index in runtime.items:
            return index
        if len(runtime.items) == 1:
            return next(iter(runtime.items))
        if runtime.current_idx in runtime.items:
            return runtime.current_idx
        for item in runtime.items.values():
            if item.status in ("pending", "downloading", "processing"):
                return item.idx
        return None

    def _on_progress(self, runtime: JobRuntime, data: dict) -> None:
        """yt-dlp 进度回调；取消请求在这里生效。"""
        if runtime.cancel.is_set():
            raise DownloadCancelled("用户取消了下载")

        info = data.get("info_dict") or {}
        status = data.get("status")
        with runtime.lock:
            index = self._resolve_index_locked(runtime, info)
            if index is None:
                return
            item = runtime.items.get(index)
            if item is None:
                return
            runtime.current_idx = index

            if status == "downloading":
                item.status = "downloading"
                downloaded = data.get("downloaded_bytes")
                total = data.get("total_bytes") or data.get("total_bytes_estimate")
                item.downloaded_bytes = int(downloaded) if downloaded else None
                item.total_bytes = int(total) if total else None
                item.speed = data.get("speed")
                item.eta = data.get("eta")
                if downloaded and total:
                    item.progress = min(1.0, float(downloaded) / float(total))
                if info.get("title"):
                    item.title = info["title"]
            elif status == "finished":
                item.status = "processing"
                item.progress = 1.0
                item.speed = None
                item.eta = 0
            elif status == "error":
                raw_error = data.get("error")
                item.status = "failed"
                item.error = friendly_error(
                    raw_error
                    if isinstance(raw_error, BaseException)
                    else RuntimeError(str(raw_error or "下载失败"))
                )
            runtime.progress = self._progress_locked(runtime)
        self._maybe_flush(runtime)

    def _on_postprocess(self, runtime: JobRuntime, data: dict) -> None:
        """合并/移动完成后记录最终文件路径。"""
        if data.get("status") != "finished":
            return
        info = data.get("info_dict") or {}
        filepath = info.get("filepath")
        with runtime.lock:
            index = self._resolve_index_locked(runtime, info)
            if index is None:
                return
            item = runtime.items.get(index)
            if item is None:
                return
            if filepath:
                try:
                    item.filename = os.path.relpath(filepath, self.settings.download_dir)
                except ValueError:
                    item.filename = str(filepath)
            item.status = "done"
            item.progress = 1.0
            item.speed = None
            item.eta = 0
            runtime.progress = self._progress_locked(runtime)
        self._maybe_flush(runtime)

    # ----------------------------------------------------------------- queries

    @staticmethod
    def _item_payload(item: ItemState) -> dict:
        return {
            "idx": item.idx,
            "title": item.title,
            "thumbnail": item.thumbnail,
            "duration": item.duration,
            "status": item.status,
            "progress": round(item.progress, 4),
            "downloaded_bytes": item.downloaded_bytes,
            "total_bytes": item.total_bytes,
            "speed": item.speed,
            "eta": item.eta,
            "filename": item.filename,
            "error": item.error,
        }

    def _job_payload_locked(self, runtime: JobRuntime) -> dict:
        return {
            "id": runtime.id,
            "url": runtime.url,
            "kind": runtime.kind,
            "title": runtime.title,
            "playlist_title": runtime.playlist_title,
            "status": runtime.status,
            "progress": round(runtime.progress, 4),
            "error": runtime.error,
            "created_at": runtime.created_at,
            "started_at": runtime.started_at,
            "finished_at": runtime.finished_at,
            "item_count": len(runtime.items),
            "items": [
                self._item_payload(item)
                for item in sorted(runtime.items.values(), key=lambda value: value.idx)
            ],
        }

    @staticmethod
    def _row_payload(row: dict, items: list[dict] | None = None) -> dict:
        payload = {
            "id": row["id"],
            "url": row["url"],
            "kind": row["kind"],
            "title": row["title"],
            "playlist_title": row["playlist_title"],
            "status": row["status"],
            "progress": round(float(row["progress"] or 0), 4),
            "error": row["error"],
            "created_at": row["created_at"],
            "started_at": row["started_at"],
            "finished_at": row["finished_at"],
            "item_count": row.get("item_count", 0),
        }
        if items is not None:
            payload["items"] = items
        return payload

    @staticmethod
    def _item_row_payload(row: dict) -> dict:
        return {
            "idx": row["idx"],
            "title": row["title"],
            "thumbnail": row["thumbnail"],
            "duration": row["duration"],
            "status": row["status"],
            "progress": round(float(row["progress"] or 0), 4),
            "downloaded_bytes": row["downloaded_bytes"],
            "total_bytes": row["total_bytes"],
            "speed": row["speed"],
            "eta": row["eta"],
            "filename": row["filename"],
            "error": row["error"],
        }

    def list_jobs(self, limit: int, offset: int) -> list[dict]:
        """返回任务列表；活动任务附带子条目实时进度。"""
        with self._lock:
            live = dict(self._jobs)
        with db.session(self.db_path) as conn:
            rows = conn.execute(
                """
                SELECT j.*, (SELECT COUNT(*) FROM job_items i WHERE i.job_id = j.id) AS item_count
                  FROM jobs j
                 ORDER BY j.created_at DESC
                 LIMIT ? OFFSET ?
                """,
                (limit, offset),
            ).fetchall()

        jobs: list[dict] = []
        for row in rows:
            runtime = live.get(row["id"])
            if runtime is not None:
                with runtime.lock:
                    jobs.append(self._job_payload_locked(runtime))
            else:
                jobs.append(self._row_payload(dict(row)))
        return jobs

    def get_job(self, job_id: str) -> dict | None:
        """返回任务详情与全部子条目。"""
        with self._lock:
            runtime = self._jobs.get(job_id)
        if runtime is not None:
            with runtime.lock:
                payload = self._job_payload_locked(runtime)
            items = payload.pop("items")
            return {"job": payload, "items": items}

        with db.session(self.db_path) as conn:
            row = conn.execute(
                """
                SELECT j.*, (SELECT COUNT(*) FROM job_items i WHERE i.job_id = j.id) AS item_count
                  FROM jobs j WHERE j.id = ?
                """,
                (job_id,),
            ).fetchone()
            if row is None:
                return None
            item_rows = conn.execute(
                "SELECT * FROM job_items WHERE job_id = ? ORDER BY idx", (job_id,)
            ).fetchall()
        return {
            "job": self._row_payload(dict(row)),
            "items": [self._item_row_payload(dict(item)) for item in item_rows],
        }

    # ---------------------------------------------------------------- mutation

    def cancel(self, job_id: str) -> bool:
        """请求取消；排队中的任务立即结束，运行中的任务在下一个进度回调中断。"""
        with self._lock:
            runtime = self._jobs.get(job_id)
        if runtime is None:
            return False

        runtime.cancel.set()
        with runtime.lock:
            queued = runtime.status == "queued"
            if queued:
                for item in runtime.items.values():
                    if item.status in ("pending", "downloading", "processing"):
                        item.status = "cancelled"
                runtime.status = "cancelled"
                runtime.finished_at = db.now_ts()
                runtime.error = "已取消"
                runtime.progress = self._progress_locked(runtime)
        if queued:
            self._flush(runtime)
            with self._lock:
                self._jobs.pop(runtime.id, None)
        return True

    def delete_job(self, job_id: str) -> bool:
        """删除历史记录（不删除已下载文件）。"""
        with self._lock:
            runtime = self._jobs.pop(job_id, None)
        if runtime is not None:
            runtime.cancel.set()
        with db.session(self.db_path) as conn:
            cursor = conn.execute("DELETE FROM jobs WHERE id = ?", (job_id,))
            deleted = cursor.rowcount > 0
        return deleted or runtime is not None

    def shutdown(self) -> None:
        """停止接受新任务并通知运行中的任务退出。"""
        with self._lock:
            runtimes = list(self._jobs.values())
        for runtime in runtimes:
            runtime.cancel.set()
        self.executor.shutdown(wait=False, cancel_futures=True)
