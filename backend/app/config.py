"""应用配置：从环境变量读取并在启动时校验。"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

APP_VERSION = "1.0.0"


class ConfigError(RuntimeError):
    """环境变量缺失或非法。"""


def _int_env(name: str, default: int) -> int:
    """读取正整数环境变量，非法值直接抛错，避免带病启动。"""
    raw = os.environ.get(name)
    if raw is None or raw.strip() == "":
        return default
    try:
        value = int(raw)
    except ValueError as exc:
        raise ConfigError(f"环境变量 {name} 必须是整数，当前值：{raw!r}") from exc
    if value <= 0:
        raise ConfigError(f"环境变量 {name} 必须大于 0，当前值：{raw!r}")
    return value


def _bool_env(name: str, default: bool = False) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    """运行期配置。"""

    access_password: str
    download_dir: Path
    data_dir: Path
    max_concurrent: int
    max_playlist_items: int
    merge_format: str
    cookies_file: Path | None
    cookie_secure: bool
    port: int
    version: str = APP_VERSION


def load_settings() -> Settings:
    """读取环境变量；缺少访问密码时拒绝启动。"""
    password = os.environ.get("ACCESS_PASSWORD", "").strip()
    if not password:
        raise ConfigError(
            "未设置环境变量 ACCESS_PASSWORD。为避免下载服务在无保护状态下暴露，"
            "请先在 .env 或 docker-compose.yml 中配置访问密码。"
        )

    cookies_raw = os.environ.get("COOKIES_FILE", "").strip()
    return Settings(
        access_password=password,
        download_dir=Path(os.environ.get("DOWNLOAD_DIR", "/downloads")).resolve(),
        data_dir=Path(os.environ.get("DATA_DIR", "/data")).resolve(),
        max_concurrent=_int_env("MAX_CONCURRENT", 2),
        max_playlist_items=_int_env("MAX_PLAYLIST_ITEMS", 500),
        merge_format=os.environ.get("MERGE_FORMAT", "mp4/mkv").strip() or "mp4/mkv",
        cookies_file=Path(cookies_raw) if cookies_raw else None,
        cookie_secure=_bool_env("COOKIE_SECURE", False),
        port=_int_env("PORT", 8080),
    )
