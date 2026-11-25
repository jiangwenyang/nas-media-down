"""下载目录浏览：路径安全校验、媒体类型识别与目录枚举。"""

from __future__ import annotations

import mimetypes
from pathlib import Path

# 容器与播放器常见的扩展名，系统 mimetypes 不一定覆盖（尤其是 mkv）
EXTRA_MIME_TYPES = {
    ".mkv": "video/x-matroska",
    ".m4v": "video/x-m4v",
    ".mov": "video/quicktime",
    ".avi": "video/x-msvideo",
    ".webm": "video/webm",
    ".flv": "video/x-flv",
    ".ts": "video/mp2t",
    ".wmv": "video/x-ms-wmv",
    ".mp3": "audio/mpeg",
    ".m4a": "audio/mp4",
    ".flac": "audio/flac",
    ".aac": "audio/aac",
    ".opus": "audio/opus",
    ".ogg": "audio/ogg",
    ".wav": "audio/wav",
    ".srt": "text/plain",
    ".ass": "text/plain",
}


class FileAccessError(Exception):
    """目标路径越界或不可用。"""


def guess_mime(name: str) -> str | None:
    """按扩展名推断 MIME，优先使用显式媒体类型表。"""
    suffix = Path(name).suffix.lower()
    if suffix in EXTRA_MIME_TYPES:
        return EXTRA_MIME_TYPES[suffix]
    return mimetypes.guess_type(name)[0]


def resolve_path(root: Path, relative: str) -> Path:
    """把相对路径解析到下载根目录内，拒绝路径穿越与符号链接逃逸。"""
    root = root.resolve()
    raw = (relative or "").strip()
    if raw.startswith(("/", "\\")):
        raise FileAccessError("非法的文件路径")
    cleaned = raw.lstrip("/\\")
    target = (root / cleaned).resolve() if cleaned else root
    if target != root and not target.is_relative_to(root):
        raise FileAccessError("非法的文件路径")
    return target


def list_dir(root: Path, relative: str) -> dict:
    """列出目录内容，目录在前、按名称排序。"""
    root = root.resolve()
    target = resolve_path(root, relative)
    if not target.exists():
        raise FileAccessError("目录不存在")
    if not target.is_dir():
        raise FileAccessError("目标不是目录")

    entries: list[dict] = []
    for child in target.iterdir():
        try:
            resolved = child.resolve()
        except OSError:
            continue
        # 跳过指向下载目录之外的符号链接，避免浏览到宿主机其他位置
        if resolved != root and not resolved.is_relative_to(root):
            continue
        try:
            stat = child.stat()
        except OSError:
            continue
        is_dir = child.is_dir()
        entries.append(
            {
                "name": child.name,
                "path": str(child.relative_to(root)),
                "is_dir": is_dir,
                "size": 0 if is_dir else stat.st_size,
                "mtime": int(stat.st_mtime),
                "mime": None if is_dir else guess_mime(child.name),
            }
        )

    entries.sort(key=lambda item: (not item["is_dir"], item["name"].lower()))

    if target == root:
        current = ""
        parent = None
    else:
        current = str(target.relative_to(root))
        parent_path = target.parent.relative_to(root)
        parent = "" if str(parent_path) == "." else str(parent_path)

    return {"path": current, "parent": parent, "entries": entries}
