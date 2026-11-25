"""哔哩哔哩扫码登录：生成二维码、轮询状态并保存 yt-dlp 可用的 Cookie。"""

from __future__ import annotations

import logging
import os
import time
from http.cookies import SimpleCookie
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import requests

from .config import Settings

logger = logging.getLogger(__name__)

BILIBILI_COOKIE_FILENAME = "bilibili-cookies.txt"
GENERATE_URL = "https://passport.bilibili.com/x/passport-login/web/qrcode/generate"
POLL_URL = "https://passport.bilibili.com/x/passport-login/web/qrcode/poll"
NAV_URL = "https://api.bilibili.com/x/web-interface/nav"
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
)
HEADERS = {"User-Agent": USER_AGENT, "Referer": "https://www.bilibili.com/"}
COOKIE_TTL = 180 * 24 * 3600
URL_COOKIE_NAMES = {
    "SESSDATA",
    "bili_jct",
    "DedeUserID",
    "DedeUserID__ckMd5",
    "sid",
    "b_nut",
}
QR_MESSAGES = {
    0: "登录成功",
    86101: "等待扫码",
    86090: "已扫码，请在手机确认",
    86038: "二维码已过期",
}


class BilibiliError(Exception):
    """B 站接口调用失败，消息可直接展示。"""


def cookie_path(settings: Settings) -> Path:
    """B 站登录 Cookie 的保存位置（容器内 /data 卷）。"""
    return settings.data_dir / BILIBILI_COOKIE_FILENAME


def is_bilibili_url(url: str) -> bool:
    """判断 URL 是否属于哔哩哔哩域名。"""
    host = (urlparse(url).hostname or "").lower()
    return host in {"bilibili.com", "b23.tv"} or host.endswith(
        (".bilibili.com", ".b23.tv")
    )


def cookiefile_for(url: str, settings: Settings) -> Path | None:
    """为 URL 选择 Cookie 文件：B 站优先用扫码登录保存的文件。"""
    if is_bilibili_url(url):
        managed = cookie_path(settings)
        if managed.exists() and managed.stat().st_size > 0:
            return managed
    if settings.cookies_file and settings.cookies_file.exists():
        return settings.cookies_file
    return None


def _get_json(url: str) -> dict:
    try:
        response = requests.get(url, headers=HEADERS, timeout=15)
        response.raise_for_status()
        return response.json()
    except requests.RequestException as exc:
        raise BilibiliError(f"无法连接哔哩哔哩：{exc}") from exc
    except ValueError as exc:
        raise BilibiliError("哔哩哔哩返回了无效响应") from exc


def generate_qrcode() -> dict[str, str]:
    """请求官方接口生成登录二维码。"""
    payload = _get_json(GENERATE_URL)
    if payload.get("code") != 0:
        raise BilibiliError(str(payload.get("message") or "生成二维码失败"))
    data = payload.get("data") or {}
    if not data.get("url") or not data.get("qrcode_key"):
        raise BilibiliError("未能生成登录二维码")
    return {"url": str(data["url"]), "key": str(data["qrcode_key"])}


def poll_qrcode(settings: Settings, key: str) -> dict:
    """轮询扫码状态；成功后把 Cookie 写入本地文件。"""
    try:
        response = requests.get(
            POLL_URL,
            params={"qrcode_key": key, "source": "main-fe-header"},
            headers=HEADERS,
            timeout=15,
        )
        response.raise_for_status()
        payload = response.json()
    except requests.RequestException as exc:
        raise BilibiliError(f"无法连接哔哩哔哩：{exc}") from exc
    except ValueError as exc:
        raise BilibiliError("哔哩哔哩返回了无效响应") from exc

    data = payload.get("data") or {}
    try:
        code = int(data.get("code", -1))
    except (TypeError, ValueError):
        code = -1

    result: dict = {
        "code": code,
        "status": QR_MESSAGES.get(code, str(data.get("message") or "未知状态")),
        "logged_in": False,
        "uname": None,
        "vip": False,
    }
    if code != 0:
        return result

    cookies = _collect_cookies(
        str(data.get("url") or ""), response.headers.getlist("Set-Cookie")
    )
    if "SESSDATA" not in cookies:
        raise BilibiliError("登录成功但未取得 SESSDATA，请重试")
    _write_cookies(settings, cookies)
    logger.info("哔哩哔哩扫码登录成功，Cookie 已保存")

    status = session_status(settings)
    result.update(
        {
            "logged_in": bool(status.get("logged_in")),
            "uname": status.get("uname"),
            "vip": bool(status.get("vip")),
        }
    )
    return result


def session_status(settings: Settings) -> dict:
    """读取本地 Cookie 并调用 nav 接口验证登录态。"""
    path = cookie_path(settings)
    entries = _read_cookie_entries(path) if path.exists() else []
    if not entries:
        return {"logged_in": False, "uname": None, "vip": False, "expires_at": None}

    values = {name: value for name, value, _ in entries}
    expires_at = max((expiry for _, _, expiry in entries), default=None)
    if "SESSDATA" not in values:
        return {"logged_in": False, "uname": None, "vip": False, "expires_at": None}

    try:
        response = requests.get(
            NAV_URL, headers=HEADERS, cookies=values, timeout=15
        )
        payload = response.json()
    except (requests.RequestException, ValueError):
        # 网络暂时不可用时保留“已保存登录信息”的状态，不强制重新扫码
        return {"logged_in": True, "uname": None, "vip": False, "expires_at": expires_at}

    data = payload.get("data") or {}
    code = payload.get("code")
    if code == -101:
        return {"logged_in": False, "uname": None, "vip": False, "expires_at": None}
    if code != 0:
        # 接口风控等异常时，只要本地 Cookie 还在就保留登录状态
        return {"logged_in": True, "uname": None, "vip": False, "expires_at": expires_at}
    logged_in = bool(data.get("isLogin"))
    return {
        "logged_in": logged_in,
        "uname": data.get("uname") if logged_in else None,
        "vip": bool(data.get("vipStatus") == 1) if logged_in else False,
        "expires_at": expires_at if logged_in else None,
    }


def logout(settings: Settings) -> None:
    """删除本地登录 Cookie。"""
    path = cookie_path(settings)
    path.unlink(missing_ok=True)
    path.with_name(path.name + ".tmp").unlink(missing_ok=True)
    logger.info("已删除哔哩哔哩登录 Cookie")


def _clean_cookie_value(value: str) -> str:
    return value.replace("\t", "").replace("\r", "").replace("\n", "")


def _collect_cookies(url: str, set_cookie_headers: list[str]) -> dict[str, dict]:
    """合并 Set-Cookie 与登录跳转 URL 中的 Cookie，只保留 B 站域名。"""
    now = int(time.time())
    default_expiry = now + COOKIE_TTL
    cookies: dict[str, dict] = {}

    for header in set_cookie_headers:
        jar = SimpleCookie()
        try:
            jar.load(header)
        except Exception:  # noqa: BLE001 - 单条 Cookie 解析失败不影响登录
            continue
        for name, morsel in jar.items():
            domain = morsel["domain"] or ".bilibili.com"
            if "bilibili.com" not in domain:
                continue
            expiry = default_expiry
            max_age = morsel["max-age"]
            if max_age not in (None, ""):
                try:
                    expiry = now + int(max_age)
                except (TypeError, ValueError):
                    pass
            cookies[name] = {
                "value": _clean_cookie_value(morsel.value),
                "domain": domain if domain.startswith(".") else f".{domain}",
                "path": morsel["path"] or "/",
                "secure": bool(morsel["secure"]),
                "expires": expiry,
            }

    # parse_qs 已完成 URL 解码，不能再 unquote 一次
    for name, values in parse_qs(urlparse(url).query).items():
        if name not in URL_COOKIE_NAMES and not name.startswith("buvid"):
            continue
        if not values:
            continue
        cookies[name] = {
            "value": _clean_cookie_value(values[-1]),
            "domain": ".bilibili.com",
            "path": "/",
            "secure": True,
            "expires": default_expiry,
        }
    return cookies


def _write_cookies(settings: Settings, cookies: dict[str, dict]) -> None:
    """按 Netscape 格式原子写入 Cookie 文件，权限 600。"""
    path = cookie_path(settings)
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = ["# Netscape HTTP Cookie File", "# Generated by nas-media-down"]
    for name, info in sorted(cookies.items()):
        domain = str(info["domain"])
        include_sub = "TRUE" if domain.startswith(".") else "FALSE"
        secure = "TRUE" if info["secure"] else "FALSE"
        lines.append(
            "\t".join(
                [
                    domain,
                    include_sub,
                    str(info["path"]),
                    secure,
                    str(info["expires"]),
                    name,
                    str(info["value"]),
                ]
            )
        )
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text("\n".join(lines) + "\n", encoding="utf-8")
    os.chmod(tmp, 0o600)
    tmp.replace(path)
    os.chmod(path, 0o600)


def _read_cookie_entries(path: Path) -> list[tuple[str, str, int]]:
    """读取 Netscape Cookie 文件的 (name, value, expiry)。"""
    try:
        content = path.read_text(encoding="utf-8")
    except OSError:
        return []
    entries: list[tuple[str, str, int]] = []
    for line in content.splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 7:
            continue
        try:
            expiry = int(parts[4])
        except ValueError:
            expiry = 0
        entries.append((parts[5], parts[6], expiry))
    return entries
