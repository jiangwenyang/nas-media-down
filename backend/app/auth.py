"""登录鉴权：单密码、服务端会话与失败限流。"""

from __future__ import annotations

import hashlib
import secrets
import threading
import time
from collections import defaultdict, deque
from pathlib import Path

from fastapi import APIRouter, HTTPException, Request, Response

from . import db
from .models import LoginBody

COOKIE_NAME = "nmd_session"
SESSION_TTL = 30 * 24 * 3600
MAX_FAILURES = 5
FAILURE_WINDOW = 5 * 60

router = APIRouter(prefix="/api/auth", tags=["auth"])


class LoginRateLimiter:
    """按 IP 统计登录失败次数，防止暴力猜测密码。"""

    def __init__(self) -> None:
        self._failures: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def _prune(self, ip: str) -> deque[float]:
        attempts = self._failures[ip]
        cutoff = time.time() - FAILURE_WINDOW
        while attempts and attempts[0] < cutoff:
            attempts.popleft()
        return attempts

    def blocked(self, ip: str) -> bool:
        with self._lock:
            return len(self._prune(ip)) >= MAX_FAILURES

    def record_failure(self, ip: str) -> None:
        with self._lock:
            self._prune(ip).append(time.time())

    def reset(self, ip: str) -> None:
        with self._lock:
            self._failures.pop(ip, None)


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def create_session(db_path: Path, ip: str | None, user_agent: str | None) -> str:
    """创建服务端会话，返回写入 Cookie 的明文 token。"""
    token = secrets.token_urlsafe(32)
    now = db.now_ts()
    with db.session(db_path) as conn:
        conn.execute(
            "INSERT INTO sessions (sid_hash, created_at, expires_at, ip, user_agent) VALUES (?, ?, ?, ?, ?)",
            (_hash_token(token), now, now + SESSION_TTL, ip, (user_agent or "")[:300]),
        )
    return token


def lookup_session(db_path: Path, token: str | None) -> bool:
    """校验 Cookie 中的 token 是否对应有效会话。"""
    if not token:
        return False
    token_hash = _hash_token(token)
    with db.session(db_path) as conn:
        row = conn.execute(
            "SELECT expires_at FROM sessions WHERE sid_hash = ?", (token_hash,)
        ).fetchone()
        if row is None:
            return False
        if int(row["expires_at"]) < db.now_ts():
            conn.execute("DELETE FROM sessions WHERE sid_hash = ?", (token_hash,))
            return False
    return True


def delete_session(db_path: Path, token: str | None) -> None:
    if not token:
        return
    with db.session(db_path) as conn:
        conn.execute("DELETE FROM sessions WHERE sid_hash = ?", (_hash_token(token),))


def require_auth(request: Request) -> None:
    """受保护接口的统一鉴权依赖。"""
    settings = request.app.state.settings
    token = request.cookies.get(COOKIE_NAME)
    if not lookup_session(request.app.state.db_path, token):
        raise HTTPException(status_code=401, detail="请先登录")


@router.post("/login")
def login(body: LoginBody, request: Request, response: Response) -> dict[str, bool]:
    """校验访问密码并签发会话 Cookie。"""
    settings = request.app.state.settings
    ip = request.client.host if request.client else "unknown"
    limiter: LoginRateLimiter = request.app.state.login_limiter

    if limiter.blocked(ip):
        raise HTTPException(status_code=429, detail="尝试次数过多，请 5 分钟后再试")

    if not secrets.compare_digest(body.password, settings.access_password):
        limiter.record_failure(ip)
        raise HTTPException(status_code=401, detail="访问密码不正确")

    limiter.reset(ip)
    token = create_session(
        request.app.state.db_path, ip, request.headers.get("user-agent")
    )
    response.set_cookie(
        COOKIE_NAME,
        token,
        max_age=SESSION_TTL,
        httponly=True,
        samesite="lax",
        secure=settings.cookie_secure,
        path="/",
    )
    return {"ok": True}


@router.post("/logout")
def logout(request: Request, response: Response) -> dict[str, bool]:
    """注销当前会话。"""
    delete_session(request.app.state.db_path, request.cookies.get(COOKIE_NAME))
    response.delete_cookie(COOKIE_NAME, path="/")
    return {"ok": True}


@router.get("/me")
def me(request: Request) -> dict[str, bool]:
    """返回当前请求是否已登录，供前端决定显示登录页还是主界面。"""
    token = request.cookies.get(COOKIE_NAME)
    return {"authenticated": lookup_session(request.app.state.db_path, token)}
