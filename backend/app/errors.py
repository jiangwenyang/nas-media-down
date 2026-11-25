"""把 yt-dlp 的异常转换成可直接展示给用户的中文提示。"""

from __future__ import annotations

import socket

import yt_dlp


def friendly_error(exc: BaseException) -> str:
    """提取最具信息量的一行错误，并补充常见场景的排查建议。"""
    name = type(exc).__name__
    message = str(exc).strip()
    lowered = message.lower()

    if name == "UnsupportedError" or "unsupported url" in lowered:
        return "不支持的链接或站点，请确认网址正确"
    if name == "GeoRestrictedError" or "not available in your country" in lowered:
        return "该视频在当前网络区域不可用"
    if isinstance(exc, (socket.timeout, TimeoutError)) or "timed out" in lowered:
        return "网络请求超时，请检查 NAS 的网络或代理设置"
    if "database is locked" in lowered:
        return "数据库繁忙（写入冲突），请稍后重试"
    if "http error 403" in lowered or "403: forbidden" in lowered:
        return "目标站点拒绝访问（403），可能需要配置 cookies.txt（需登录或有人机验证的站点）"
    if "sign in" in lowered or "cookies" in lowered or "login required" in lowered:
        return "该视频需要登录 Cookie，请配置 COOKIES_FILE"
    if "private video" in lowered or "video unavailable" in lowered:
        return "视频不可用或为私享内容"
    if "http error 404" in lowered:
        return "视频不存在（404）"

    if isinstance(exc, yt_dlp.utils.DownloadError) and exc.args:
        message = str(exc.args[0])
    first_line = message.splitlines()[0].strip() if message else "未知错误"
    return first_line[:300]
