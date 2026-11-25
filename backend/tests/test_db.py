"""数据库启动恢复逻辑测试。"""

from __future__ import annotations

from pathlib import Path

from app import db


def test_mark_interrupted_jobs(tmp_path: Path) -> None:
    db_path = tmp_path / "test.db"
    db.init_db(db_path)

    with db.session(db_path) as conn:
        conn.execute(
            "INSERT INTO jobs (id, url, kind, title, status, progress, created_at) "
            "VALUES ('running-job', 'http://x', 'video', '运行中', 'running', 0.5, 1)"
        )
        conn.execute(
            "INSERT INTO job_items (job_id, idx, title, status, progress) "
            "VALUES ('running-job', 1, '运行中', 'downloading', 0.5)"
        )
        conn.execute(
            "INSERT INTO jobs (id, url, kind, title, status, progress, created_at) "
            "VALUES ('done-job', 'http://y', 'video', '已完成', 'completed', 1, 1)"
        )
        conn.execute(
            "INSERT INTO job_items (job_id, idx, title, status, progress) "
            "VALUES ('done-job', 1, '已完成', 'done', 1)"
        )

    assert db.mark_interrupted_jobs(db_path) == 1

    with db.session(db_path) as conn:
        job = conn.execute(
            "SELECT status, finished_at FROM jobs WHERE id = 'running-job'"
        ).fetchone()
        item = conn.execute(
            "SELECT status, error FROM job_items WHERE job_id = 'running-job'"
        ).fetchone()
        done_job = conn.execute(
            "SELECT status FROM jobs WHERE id = 'done-job'"
        ).fetchone()
        done_item = conn.execute(
            "SELECT status FROM job_items WHERE job_id = 'done-job'"
        ).fetchone()

    assert job["status"] == "interrupted"
    assert job["finished_at"] is not None
    assert item["status"] == "failed"
    assert item["error"]
    assert done_job["status"] == "completed"
    assert done_item["status"] == "done"
