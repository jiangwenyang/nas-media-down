"""短期文件分享链接：供外部播放器直接访问，无需登录 Cookie。"""

from __future__ import annotations

import secrets
import threading
import time
from dataclasses import dataclass
from pathlib import Path

SHARE_TTL = 6 * 3600


@dataclass(frozen=True)
class ShareEntry:
    path: Path
    expires_at: int


class ShareLinkStore:
    """进程内 token 存储；服务单 worker 运行，重启后链接自动失效。"""

    def __init__(self, ttl: int = SHARE_TTL) -> None:
        self._ttl = ttl
        self._entries: dict[str, ShareEntry] = {}
        self._lock = threading.Lock()

    def create(self, path: Path) -> tuple[str, int]:
        """为文件签发随机 token，返回 token 与过期时间。"""
        token = secrets.token_urlsafe(32)
        expires_at = int(time.time()) + self._ttl
        with self._lock:
            self._prune()
            self._entries[token] = ShareEntry(path=path, expires_at=expires_at)
        return token, expires_at

    def resolve(self, token: str) -> Path | None:
        """校验 token 并返回文件路径；过期或不存在时返回 None。"""
        now = time.time()
        with self._lock:
            entry = self._entries.get(token)
            if entry is None:
                return None
            if entry.expires_at <= now:
                self._entries.pop(token, None)
                return None
            return entry.path

    def _prune(self) -> None:
        now = time.time()
        expired = [
            token for token, entry in self._entries.items() if entry.expires_at <= now
        ]
        for token in expired:
            self._entries.pop(token, None)
