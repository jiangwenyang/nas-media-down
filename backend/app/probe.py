"""用 yt-dlp 探测 URL：识别单视频或播放列表，只返回必要的元数据。"""

from __future__ import annotations

import re
import shutil
from urllib.parse import urlparse

import yt_dlp

from .bilibili import cookiefile_for
from .config import Settings
from .errors import friendly_error

# 从 B 站等 App 的分享文本中提取链接
URL_PATTERN = re.compile(
    r"https?://[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+",
    re.IGNORECASE,
)
TRAILING_PUNCTUATION = ".,;:!?)]}>，。；：！？、】」』》〉\"'"


class ProbeError(Exception):
    """探测失败，消息可直接展示给用户。"""


def validate_url(text: str) -> str:
    """从网址或分享文本中提取第一个 http/https 链接并规范化。"""
    raw = (text or "").strip()
    match = URL_PATTERN.search(raw)
    if not match:
        raise ValueError("未找到有效链接，请粘贴网址或完整分享文本")
    cleaned = match.group(0).rstrip(TRAILING_PUNCTUATION)
    parsed = urlparse(cleaned)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise ValueError("请输入有效的 http/https 网址")
    return cleaned


def _base_opts(url: str, settings: Settings) -> dict:
    opts: dict = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "socket_timeout": 20,
        "retries": 3,
        "noplaylist": False,
    }
    cookiefile = cookiefile_for(url, settings)
    if cookiefile:
        opts["cookiefile"] = str(cookiefile)
    if shutil.which("deno"):
        opts["js_runtimes"] = {"deno": {}}
    return opts


def _thumbnail(info: dict) -> str | None:
    if info.get("thumbnail"):
        return info["thumbnail"]
    thumbs = info.get("thumbnails") or []
    if thumbs:
        return thumbs[-1].get("url")
    return None


def _video_view(info: dict | None) -> dict | None:
    if not info:
        return None
    return {
        "id": info.get("id"),
        "title": info.get("title") or info.get("id") or "未命名视频",
        "duration": info.get("duration"),
        "thumbnail": _thumbnail(info),
        "uploader": info.get("uploader") or info.get("channel") or info.get("creator"),
        "webpage_url": info.get("webpage_url") or info.get("original_url"),
    }


def _entry_view(entry: dict, fallback_index: int) -> dict:
    raw_index = entry.get("playlist_index")
    try:
        index = int(raw_index) if raw_index is not None else fallback_index
    except (TypeError, ValueError):
        index = fallback_index
    return {
        "index": index,
        "id": entry.get("id"),
        "title": entry.get("title") or f"第 {index} 个视频",
        "duration": entry.get("duration"),
        "thumbnail": _thumbnail(entry),
    }


def probe_url(url: str, settings: Settings) -> dict:
    """探测 URL：返回单视频信息或播放列表条目，供前端展示与勾选。"""
    url = validate_url(url)
    opts = _base_opts(url, settings)
    opts.update(
        {
            "extract_flat": "in_playlist",
            "playlist_items": f"1-{settings.max_playlist_items}",
        }
    )

    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=False)
    except Exception as exc:  # noqa: BLE001 - yt-dlp 异常类型繁多，统一转译
        raise ProbeError(friendly_error(exc)) from exc

    if not info:
        raise ProbeError("未能解析该链接，请确认网址正确")

    if info.get("_type") in ("playlist", "multi_video"):
        entries: list[dict] = []
        for raw in info.get("entries") or []:
            if not raw:
                continue
            entries.append(_entry_view(raw, len(entries) + 1))
        if not entries:
            raise ProbeError("播放列表为空或无法读取")

        playlist_count = int(info.get("playlist_count") or len(entries))
        video = None
        # YouTube 的 watch?v=X&list=Y 同时包含单个视频与播放列表，额外探测当前视频
        if "v=" in url and "list=" in url:
            single_opts = _base_opts(url, settings)
            single_opts["noplaylist"] = True
            try:
                with yt_dlp.YoutubeDL(single_opts) as ydl:
                    video = _video_view(ydl.extract_info(url, download=False))
            except Exception:  # noqa: BLE001 - 单个视频信息只用于展示，失败不影响列表
                video = None

        return {
            "kind": "playlist",
            "video": video,
            "playlist": {
                "id": info.get("id"),
                "title": info.get("title") or "未命名播放列表",
                "count": playlist_count,
                "truncated": playlist_count > len(entries),
                "entries": entries,
            },
        }

    return {"kind": "video", "video": _video_view(info), "playlist": None}
