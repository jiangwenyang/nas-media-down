"""下载目录路径安全与枚举行为测试。"""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from app.files import FileAccessError, list_dir, resolve_path


@pytest.fixture()
def root(tmp_path: Path) -> Path:
    download_dir = tmp_path / "downloads"
    download_dir.mkdir()
    (download_dir / "movie").mkdir()
    (download_dir / "movie" / "a.mp4").write_bytes(b"fake")
    (download_dir / "b.txt").write_text("hello", encoding="utf-8")
    return download_dir


def test_resolve_root(root: Path) -> None:
    assert resolve_path(root, "") == root.resolve()


def test_resolve_normal_path(root: Path) -> None:
    assert resolve_path(root, "movie/a.mp4") == (root / "movie" / "a.mp4").resolve()


@pytest.mark.parametrize(
    "relative",
    ["../outside.txt", "movie/../../outside.txt", "/etc/passwd", "..%2foutside"],
)
def test_rejects_traversal(root: Path, relative: str) -> None:
    if relative == "..%2foutside":
        # 百分号编码在这里不是特殊字符，只应解析为普通文件名
        assert resolve_path(root, relative).name == "..%2foutside"
        return
    with pytest.raises(FileAccessError):
        resolve_path(root, relative)


def test_rejects_symlink_escape(root: Path, tmp_path: Path) -> None:
    secret = tmp_path / "secret.txt"
    secret.write_text("secret", encoding="utf-8")
    link = root / "escape.txt"
    os.symlink(secret, link)
    with pytest.raises(FileAccessError):
        resolve_path(root, "escape.txt")


def test_list_dir_hides_escaping_symlinks(root: Path, tmp_path: Path) -> None:
    secret = tmp_path / "secret.txt"
    secret.write_text("secret", encoding="utf-8")
    os.symlink(secret, root / "escape.txt")
    (root / "a-link.mp4").symlink_to(root / "movie" / "a.mp4")

    listing = list_dir(root, "")
    names = [entry["name"] for entry in listing["entries"]]

    assert "escape.txt" not in names
    assert names == ["movie", "a-link.mp4", "b.txt"]
    assert listing["path"] == ""
    assert listing["parent"] is None


def test_list_dir_reports_parent(root: Path) -> None:
    listing = list_dir(root, "movie")
    assert listing["path"] == "movie"
    assert listing["parent"] == ""
    assert [entry["name"] for entry in listing["entries"]] == ["a.mp4"]
    assert listing["entries"][0]["size"] == 4


def test_list_dir_rejects_file(root: Path) -> None:
    with pytest.raises(FileAccessError):
        list_dir(root, "b.txt")
