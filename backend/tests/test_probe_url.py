"""分享文本链接提取测试。"""

from __future__ import annotations

import pytest

from app.probe import validate_url


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        (
            "【新能源车买得起修不起？汽修厂：有些品牌也不敢修-哔哩哔哩】 https://b23.tv/ojgNeqq",
            "https://b23.tv/ojgNeqq",
        ),
        (
            "看这个 https://www.bilibili.com/video/BV1xx411c7mD，很有意思",
            "https://www.bilibili.com/video/BV1xx411c7mD",
        ),
        (
            "【标题】https://b23.tv/abc】",
            "https://b23.tv/abc",
        ),
        (
            "https://example.com/watch?v=1&list=2",
            "https://example.com/watch?v=1&list=2",
        ),
        (
            "第一个 https://a.example/x 第二个 https://b.example/y",
            "https://a.example/x",
        ),
        (
            "  https://example.com/movie.mkv  ",
            "https://example.com/movie.mkv",
        ),
    ],
)
def test_extracts_first_url(text: str, expected: str) -> None:
    assert validate_url(text) == expected


@pytest.mark.parametrize(
    "text",
    [
        "",
        "没有链接的分享文本",
        "ftp://example.com/file",
        "javascript:alert(1)",
    ],
)
def test_rejects_text_without_http_url(text: str) -> None:
    with pytest.raises(ValueError):
        validate_url(text)
