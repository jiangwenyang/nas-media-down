"""追番/追剧接口解析与订阅自动下载测试。"""

from __future__ import annotations

import json
from pathlib import Path
from types import SimpleNamespace

import pytest
import requests

from app import bangumi, db
from app.config import Settings


def make_settings(tmp_path: Path) -> Settings:
    return Settings(
        access_password="test",
        download_dir=tmp_path / "downloads",
        data_dir=tmp_path / "data",
        max_concurrent=2,
        max_playlist_items=10,
        merge_format="mp4/mkv",
        cookies_file=None,
        cookie_secure=False,
        port=8080,
    )


def fake_response(payload: dict) -> requests.Response:
    response = requests.Response()
    response.status_code = 200
    response._content = json.dumps(payload).encode()
    return response


def episode(ep_id: int, idx: int, pub_time: int = 1_700_000_000) -> dict:
    return {
        "ep_id": ep_id,
        "idx": idx,
        "title": f"第{idx}话",
        "duration": 1500.0,
        "cover": None,
        "pub_time": pub_time,
    }


def test_fetch_follow_list_maps_items(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    settings = make_settings(tmp_path)
    payload = {
        "code": 0,
        "data": {
            "total": 30,
            "list": [
                {
                    "season_id": 123,
                    "media_id": 456,
                    "title": "测试番剧",
                    "cover": "http://i0.hdslb.com/a.png",
                    "season_title": "第一季",
                    "total_count": 12,
                    "is_finish": 0,
                    "new_ep": {"index_show": "更新至第3话", "pub_time": "2026-01-02 10:00:00"},
                }
            ],
        },
    }
    monkeypatch.setattr(bangumi.requests, "get", lambda *a, **k: fake_response(payload))

    result = bangumi.fetch_follow_list(settings, 1, 1, vmid="52142074")

    assert result["has_more"] is True
    assert result["total"] == 30
    item = result["items"][0]
    assert item["season_id"] == 123
    assert item["title"] == "测试番剧"
    assert item["cover"].startswith("https://")
    assert item["new_ep"]["title"] == "更新至第3话"
    assert item["url"].endswith("/ss123")


def test_fetch_follow_list_maps_api_error(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    settings = make_settings(tmp_path)
    payload = {"code": 53013, "message": "用户隐私设置未公开"}
    monkeypatch.setattr(bangumi.requests, "get", lambda *a, **k: fake_response(payload))

    with pytest.raises(bangumi.BangumiError, match="未公开"):
        bangumi.fetch_follow_list(settings, 1, 1, vmid="1")


def test_fetch_follow_list_requires_login_without_vmid(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    settings = make_settings(tmp_path)
    calls: list[str] = []
    monkeypatch.setattr(
        bangumi.requests,
        "get",
        lambda *a, **k: calls.append("called") or fake_response({"code": 0, "data": {}}),
    )

    with pytest.raises(bangumi.BangumiError, match="扫码登录"):
        bangumi.fetch_follow_list(settings, 1, 1)
    assert calls == []


def test_fetch_season_filters_future_episodes(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    settings = make_settings(tmp_path)
    payload = {
        "code": 0,
        "result": {
            "media_id": 9,
            "title": "测试剧",
            "cover": "http://i0.hdslb.com/b.png",
            "episodes": [
                {
                    "ep_id": 11,
                    "title": "1",
                    "show_title": "第1话 开始",
                    "duration": 55000,
                    "pub_time": 1_600_000_000,
                    "cover": "http://i0.hdslb.com/e.png",
                },
                {
                    "ep_id": 12,
                    "title": "2",
                    "show_title": "第2话 未播",
                    "duration": 55000,
                    "pub_time": 4_000_000_000,
                },
            ],
        },
    }
    monkeypatch.setattr(bangumi.requests, "get", lambda *a, **k: fake_response(payload))

    season = bangumi.fetch_season(settings, 99)

    assert season["title"] == "测试剧"
    assert season["cover"].startswith("https://")
    assert len(season["episodes"]) == 1
    first = season["episodes"][0]
    assert first["ep_id"] == 11
    assert first["idx"] == 1
    assert first["title"] == "第1话 开始"
    assert first["duration"] == 55.0


class FakeJobs:
    """记录 JobManager.create 的调用并写入最小任务记录，不真正下载。"""

    def __init__(self, db_path: Path | None = None) -> None:
        self.created: list = []
        self.db_path = db_path
        self.active: set[int] = set()

    def active_indices(self, url: str) -> set[int]:  # noqa: ARG002 - 与 JobManager 签名保持一致
        return set(self.active)

    def create(self, body):  # noqa: ANN001 - 与 JobManager 签名保持一致
        self.created.append(body)
        job_id = f"job{len(self.created)}"
        if self.db_path is not None:
            with db.session(self.db_path) as conn:
                conn.execute(
                    """
                    INSERT INTO jobs (id, url, kind, title, status, progress, created_at)
                    VALUES (?, ?, ?, ?, 'queued', 0, ?)
                    """,
                    (job_id, body.url, body.kind, body.playlist_title, db.now_ts()),
                )
                conn.executemany(
                    """
                    INSERT INTO job_items (job_id, idx, title, status, progress)
                    VALUES (?, ?, ?, 'pending', 0)
                    """,
                    [(job_id, entry.index, entry.title) for entry in body.entries],
                )
        return SimpleNamespace(id=job_id)


def test_watch_mode_baseline_then_download_new_episode(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    settings = make_settings(tmp_path)
    db.init_db(settings.data_dir / "nas-media-down.db")
    jobs = FakeJobs(settings.data_dir / "nas-media-down.db")
    manager = bangumi.BangumiManager(settings, jobs)  # type: ignore[arg-type]

    season = {
        "season_id": 1,
        "media_id": 2,
        "title": "自动追番",
        "cover": None,
        "total_count": 2,
        "episodes": [episode(101, 1), episode(102, 2)],
    }
    monkeypatch.setattr(bangumi, "fetch_season", lambda s, sid: season)

    created = manager.subscribe(1, 1, "watch")
    assert created["job_count"] == 0
    assert jobs.created == []
    sub_id = created["subscription"]["id"]

    season["episodes"].append(episode(103, 3))
    result = manager.check(sub_id)

    assert result["new_episodes"] == 1
    assert result["job_count"] == 1
    assert len(jobs.created) == 1
    body = jobs.created[0]
    assert body.kind == "playlist"
    assert [entry.index for entry in body.entries] == [3]

    payload = manager.get_subscription(sub_id)
    assert payload is not None
    stats = manager.list_subscriptions()[0]
    assert stats["queued_count"] == 1
    assert stats["skipped_count"] == 2


def test_download_all_enqueues_every_published_episode(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    settings = make_settings(tmp_path)
    db.init_db(settings.data_dir / "nas-media-down.db")
    jobs = FakeJobs(settings.data_dir / "nas-media-down.db")
    manager = bangumi.BangumiManager(settings, jobs)  # type: ignore[arg-type]

    season = {
        "season_id": 8,
        "media_id": None,
        "title": "整季下载",
        "cover": None,
        "total_count": 3,
        "episodes": [episode(201, 1), episode(202, 2), episode(203, 3)],
    }
    monkeypatch.setattr(bangumi, "fetch_season", lambda s, sid: season)

    created = manager.subscribe(1, 8, "watch")
    sub_id = created["subscription"]["id"]
    assert jobs.created == []

    result = manager.download_all(sub_id)

    assert result["episode_count"] == 3
    assert result["job_count"] == 1
    assert [entry.index for entry in jobs.created[0].entries] == [1, 2, 3]

    # 再次下载不会重复入队
    again = manager.download_all(sub_id)
    assert again["job_count"] == 0
    assert len(jobs.created) == 1


def test_reconcile_follows_manual_retry(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    settings = make_settings(tmp_path)
    db_path = settings.data_dir / "nas-media-down.db"
    db.init_db(db_path)
    jobs = FakeJobs(db_path)
    manager = bangumi.BangumiManager(settings, jobs)  # type: ignore[arg-type]

    season = {
        "season_id": 3,
        "media_id": None,
        "title": "重试测试",
        "cover": None,
        "total_count": 3,
        "episodes": [episode(301, 1), episode(302, 2)],
    }
    monkeypatch.setattr(bangumi, "fetch_season", lambda s, sid: season)

    created = manager.subscribe(1, 3, "watch")
    sub_id = created["subscription"]["id"]
    url = created["subscription"]["url"]

    season["episodes"].append(episode(303, 3))
    manager.check(sub_id)
    assert manager.list_subscriptions()[0]["queued_count"] == 1

    with db.session(db_path) as conn:
        conn.execute("UPDATE jobs SET status = 'failed' WHERE id = 'job1'")
        conn.execute("UPDATE job_items SET status = 'failed' WHERE job_id = 'job1'")

    manager.check(sub_id)
    stats = manager.list_subscriptions()[0]
    assert stats["failed_count"] == 1
    assert stats["done_count"] == 0

    # 用户在「任务」页重新下载同一集并成功
    with db.session(db_path) as conn:
        conn.execute(
            """
            INSERT INTO jobs (id, url, kind, title, status, progress, created_at)
            VALUES ('retry', ?, 'playlist', '重试测试', 'completed', 1, ?)
            """,
            (url, db.now_ts()),
        )
        conn.execute(
            """
            INSERT INTO job_items (job_id, idx, title, status, progress)
            VALUES ('retry', 3, '第3话', 'done', 1)
            """
        )

    manager.check(sub_id)
    stats = manager.list_subscriptions()[0]
    assert stats["done_count"] == 1
    assert stats["failed_count"] == 0


def test_download_selected_episodes_without_subscription(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    settings = make_settings(tmp_path)
    db.init_db(settings.data_dir / "nas-media-down.db")
    jobs = FakeJobs(settings.data_dir / "nas-media-down.db")
    manager = bangumi.BangumiManager(settings, jobs)  # type: ignore[arg-type]

    season = {
        "season_id": 11,
        "media_id": None,
        "title": "选集下载",
        "cover": None,
        "total_count": 4,
        "episodes": [episode(401 + i, i + 1) for i in range(4)],
    }
    monkeypatch.setattr(bangumi, "fetch_season", lambda s, sid: season)

    result = manager.download_episodes(11, [2, 4])

    assert result["episode_count"] == 2
    assert result["job_count"] == 1
    assert result["subscription"] is None
    assert [entry.index for entry in jobs.created[0].entries] == [2, 4]
    assert jobs.created[0].playlist_title == "选集下载"
    assert manager.list_subscriptions() == []


def test_download_selected_episodes_updates_subscription(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    settings = make_settings(tmp_path)
    db.init_db(settings.data_dir / "nas-media-down.db")
    jobs = FakeJobs(settings.data_dir / "nas-media-down.db")
    manager = bangumi.BangumiManager(settings, jobs)  # type: ignore[arg-type]

    season = {
        "season_id": 12,
        "media_id": None,
        "title": "追更选集",
        "cover": None,
        "total_count": 3,
        "episodes": [episode(501, 1), episode(502, 2), episode(503, 3)],
    }
    monkeypatch.setattr(bangumi, "fetch_season", lambda s, sid: season)

    created = manager.subscribe(1, 12, "watch")
    sub_id = created["subscription"]["id"]

    result = manager.download_episodes(12, [1, 2])
    assert result["episode_count"] == 2
    assert result["job_count"] == 1
    assert result["subscription"]["queued_count"] == 2

    with pytest.raises(bangumi.BangumiError, match="已下载或正在下载"):
        manager.download_episodes(12, [1])

    detail = manager.season_detail(12)
    assert detail["subscribed"] is True
    statuses = {ep["idx"]: ep["status"] for ep in detail["episodes"]}
    assert statuses == {1: "queued", 2: "queued", 3: "skipped"}


def test_season_detail_marks_downloaded_files(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    settings = make_settings(tmp_path)
    db.init_db(settings.data_dir / "nas-media-down.db")
    jobs = FakeJobs(settings.data_dir / "nas-media-down.db")
    manager = bangumi.BangumiManager(settings, jobs)  # type: ignore[arg-type]

    season = {
        "season_id": 21,
        "media_id": None,
        "title": "已下载标记",
        "cover": None,
        "total_count": 3,
        "episodes": [episode(601, 1), episode(602, 2), episode(603, 3)],
    }
    monkeypatch.setattr(bangumi, "fetch_season", lambda s, sid: season)

    folder = settings.download_dir / "已下载标记"
    folder.mkdir(parents=True)
    (folder / "1 第1话 [601].mkv").write_bytes(b"media")
    (folder / "2 第2话 [602].mkv.part").write_bytes(b"partial")

    detail = manager.season_detail(21)

    flags = {ep["idx"]: ep["downloaded"] for ep in detail["episodes"]}
    assert flags == {1: True, 2: False, 3: False}


def test_season_detail_marks_downloaded_from_jobs(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    settings = make_settings(tmp_path)
    db_path = settings.data_dir / "nas-media-down.db"
    db.init_db(db_path)
    jobs = FakeJobs(db_path)
    manager = bangumi.BangumiManager(settings, jobs)  # type: ignore[arg-type]

    season = {
        "season_id": 22,
        "media_id": None,
        "title": "任务记录标记",
        "cover": None,
        "total_count": 2,
        "episodes": [episode(611, 1), episode(612, 2)],
    }
    monkeypatch.setattr(bangumi, "fetch_season", lambda s, sid: season)

    folder = settings.download_dir / "其它目录名"
    folder.mkdir(parents=True)
    (folder / "2 第2话 [612].mkv").write_bytes(b"media")
    with db.session(db_path) as conn:
        conn.execute(
            """
            INSERT INTO jobs (id, url, kind, title, status, progress, created_at)
            VALUES ('jobx', ?, 'playlist', '任务记录标记', 'completed', 1, ?)
            """,
            ("https://www.bilibili.com/bangumi/play/ss22", db.now_ts()),
        )
        conn.execute(
            """
            INSERT INTO job_items (job_id, idx, title, status, progress, filename)
            VALUES ('jobx', 2, '第2话', 'done', 1, '其它目录名/2 第2话 [612].mkv')
            """
        )

    detail = manager.season_detail(22)

    flags = {ep["idx"]: ep["downloaded"] for ep in detail["episodes"]}
    assert flags == {1: False, 2: True}


def test_download_episodes_skips_downloaded_and_active(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    settings = make_settings(tmp_path)
    db.init_db(settings.data_dir / "nas-media-down.db")
    jobs = FakeJobs(settings.data_dir / "nas-media-down.db")
    manager = bangumi.BangumiManager(settings, jobs)  # type: ignore[arg-type]

    season = {
        "season_id": 23,
        "media_id": None,
        "title": "跳过已下载",
        "cover": None,
        "total_count": 4,
        "episodes": [episode(621 + i, i + 1) for i in range(4)],
    }
    monkeypatch.setattr(bangumi, "fetch_season", lambda s, sid: season)

    folder = settings.download_dir / "跳过已下载"
    folder.mkdir(parents=True)
    (folder / "1 第1话 [621].mkv").write_bytes(b"media")
    jobs.active.add(2)

    result = manager.download_episodes(23, [1, 2, 3])

    assert result["episode_count"] == 1
    assert result["skipped_count"] == 2
    assert [entry.index for entry in jobs.created[0].entries] == [3]

    with pytest.raises(bangumi.BangumiError, match="已下载或正在下载"):
        manager.download_episodes(23, [1])
