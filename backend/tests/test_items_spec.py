"""播放列表索引压缩与目录名清洗测试。"""

from __future__ import annotations

import pytest

from app.downloader import build_items_spec, sanitize_filename


@pytest.mark.parametrize(
    ("indices", "expected"),
    [
        ([1], "1"),
        ([1, 2, 3], "1-3"),
        ([1, 3, 4, 5], "1,3-5"),
        ([5, 3, 1], "1,3,5"),
        ([2, 2, 3], "2-3"),
        ([1, 2, 4, 6, 7, 9], "1-2,4,6-7,9"),
    ],
)
def test_build_items_spec(indices: list[int], expected: str) -> None:
    assert build_items_spec(indices) == expected


def test_build_items_spec_requires_items() -> None:
    with pytest.raises(ValueError):
        build_items_spec([])


def test_sanitize_filename_replaces_invalid_chars() -> None:
    assert sanitize_filename('a/b:c*d?e"f<g>h|i') == "a_b_c_d_e_f_g_h_i"


def test_sanitize_filename_strips_and_falls_back() -> None:
    assert sanitize_filename("  ...  ") == "未命名"
    assert sanitize_filename("") == "未命名"


def test_sanitize_filename_truncates_utf8_bytes() -> None:
    name = "中文" * 40
    result = sanitize_filename(name, max_bytes=12)
    assert len(result.encode("utf-8")) <= 12
    assert result == "中文中文"
