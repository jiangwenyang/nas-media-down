"""短期分享链接存储测试。"""

from __future__ import annotations

from pathlib import Path

from app.share import ShareLinkStore


def test_create_and_resolve(tmp_path: Path) -> None:
    file = tmp_path / "movie.mp4"
    file.write_bytes(b"video")

    store = ShareLinkStore(ttl=60)
    token, expires_at = store.create(file)

    assert len(token) >= 32
    assert expires_at > 0
    assert store.resolve(token) == file


def test_unknown_token() -> None:
    assert ShareLinkStore().resolve("missing-token") is None


def test_expired_token(tmp_path: Path) -> None:
    file = tmp_path / "movie.mp4"
    file.write_bytes(b"video")

    store = ShareLinkStore(ttl=-1)
    token, _ = store.create(file)

    assert store.resolve(token) is None
