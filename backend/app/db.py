"""SQLite 存储层：建表、连接与启动期数据修复。"""

from __future__ import annotations

import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

SCHEMA = """
CREATE TABLE IF NOT EXISTS jobs (
    id TEXT PRIMARY KEY,
    url TEXT NOT NULL,
    kind TEXT NOT NULL,
    title TEXT,
    playlist_id TEXT,
    playlist_title TEXT,
    playlist_count INTEGER,
    items_spec TEXT,
    status TEXT NOT NULL,
    progress REAL NOT NULL DEFAULT 0,
    error TEXT,
    created_at INTEGER NOT NULL,
    started_at INTEGER,
    finished_at INTEGER
);

CREATE TABLE IF NOT EXISTS job_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    idx INTEGER NOT NULL,
    video_id TEXT,
    title TEXT,
    duration REAL,
    thumbnail TEXT,
    status TEXT NOT NULL,
    progress REAL NOT NULL DEFAULT 0,
    downloaded_bytes INTEGER,
    total_bytes INTEGER,
    speed REAL,
    eta INTEGER,
    filename TEXT,
    error TEXT,
    UNIQUE (job_id, idx)
);

CREATE TABLE IF NOT EXISTS sessions (
    sid_hash TEXT PRIMARY KEY,
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    ip TEXT,
    user_agent TEXT
);

CREATE INDEX IF NOT EXISTS ix_jobs_created ON jobs(created_at DESC);
CREATE INDEX IF NOT EXISTS ix_items_job ON job_items(job_id, idx);
CREATE INDEX IF NOT EXISTS ix_sessions_expiry ON sessions(expires_at);
"""


def now_ts() -> int:
    """当前 Unix 时间戳（秒）。"""
    return int(time.time())


def connect(db_path: Path) -> sqlite3.Connection:
    """建立带 WAL 的连接；每次调用独立连接，天然线程安全。"""
    conn = sqlite3.connect(db_path, timeout=5.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=5000")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


@contextmanager
def session(db_path: Path) -> Iterator[sqlite3.Connection]:
    """自动提交并关闭的事务上下文。"""
    conn = connect(db_path)
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db(db_path: Path) -> None:
    """创建数据库目录与全部表结构（幂等）。"""
    db_path.parent.mkdir(parents=True, exist_ok=True)
    with session(db_path) as conn:
        conn.executescript(SCHEMA)


def mark_interrupted_jobs(db_path: Path) -> int:
    """容器重启后，把未完成任务标记为中断，避免进度永远停在旧状态。"""
    with session(db_path) as conn:
        cursor = conn.execute(
            """
            UPDATE jobs
               SET status = 'interrupted',
                   finished_at = ?,
                   error = COALESCE(error, '服务重启，下载已中断')
             WHERE status IN ('queued', 'running')
            """,
            (now_ts(),),
        )
        conn.execute(
            """
            UPDATE job_items
               SET status = 'failed',
                   error = COALESCE(error, '服务重启，下载已中断')
             WHERE status IN ('pending', 'downloading', 'processing')
               AND job_id IN (SELECT id FROM jobs WHERE status = 'interrupted')
            """
        )
        return cursor.rowcount


def purge_expired_sessions(db_path: Path) -> int:
    """清理过期会话。"""
    with session(db_path) as conn:
        cursor = conn.execute("DELETE FROM sessions WHERE expires_at < ?", (now_ts(),))
        return cursor.rowcount
