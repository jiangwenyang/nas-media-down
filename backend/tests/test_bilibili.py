"""哔哩哔哩扫码登录的 Cookie 解析与文件管理测试。"""

from __future__ import annotations

import json
import stat
from pathlib import Path
from types import SimpleNamespace

import pytest
import requests

from app import bilibili
from app.config import Settings


def make_settings(tmp_path: Path, cookies_file: Path | None = None) -> Settings:
    return Settings(
        access_password="test",
        download_dir=tmp_path / "downloads",
        data_dir=tmp_path / "data",
        max_concurrent=2,
        max_playlist_items=10,
        merge_format="mp4/mkv",
        cookies_file=cookies_file,
        cookie_secure=False,
        port=8080,
    )


def test_is_bilibili_url() -> None:
    assert bilibili.is_bilibili_url("https://www.bilibili.com/video/BV1xx")
    assert bilibili.is_bilibili_url("https://space.bilibili.com/123")
    assert bilibili.is_bilibili_url("https://b23.tv/abcd")
    assert not bilibili.is_bilibili_url("https://example.com/bilibili.com")
    assert not bilibili.is_bilibili_url("https://notbilibili.com/video/1")


def test_collect_cookies_from_url_and_headers() -> None:
    url = (
        "https://passport.biligame.com/crossDomain?"
        "DedeUserID=123&DedeUserID__ckMd5=abc&SESSDATA=sess%2Ctoken"
        "&bili_jct=csrf&gourl=https%3A%2F%2Fwww.bilibili.com"
    )
    headers = [
        "buvid3=buv-123; Path=/; Domain=.bilibili.com; Max-Age=86400; Secure; HttpOnly",
        "b_nut=1700000000; Path=/; Domain=.bilibili.com; Secure",
        "unrelated=1; Path=/; Domain=.example.com",
    ]

    cookies = bilibili._collect_cookies(url, headers)

    assert cookies["SESSDATA"]["value"] == "sess,token"
    assert cookies["bili_jct"]["value"] == "csrf"
    assert cookies["DedeUserID"]["value"] == "123"
    assert cookies["buvid3"]["value"] == "buv-123"
    assert cookies["buvid3"]["domain"] == ".bilibili.com"
    assert cookies["buvid3"]["secure"] is True
    assert "unrelated" not in cookies
    assert all(info["domain"] == ".bilibili.com" for info in cookies.values())


def test_set_cookie_headers_from_raw() -> None:
    class RawHeaders:
        def getlist(self, name: str) -> list[str]:
            assert name == "Set-Cookie"
            return ["a=1; Path=/", "b=2; Path=/"]

    response = requests.Response()
    response.raw = SimpleNamespace(headers=RawHeaders())

    assert bilibili._set_cookie_headers(response) == ["a=1; Path=/", "b=2; Path=/"]


def test_set_cookie_headers_fallback() -> None:
    response = requests.Response()
    response.headers["Set-Cookie"] = "a=1; Path=/"

    assert bilibili._set_cookie_headers(response) == ["a=1; Path=/"]
    assert bilibili._set_cookie_headers(requests.Response()) == []


def test_write_cookies_reports_os_error(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    settings = make_settings(tmp_path)
    cookies = {
        "SESSDATA": {
            "value": "x",
            "domain": ".bilibili.com",
            "path": "/",
            "secure": True,
            "expires": 1,
        }
    }

    def fail(*args: object, **kwargs: object) -> None:
        raise OSError("permission denied")

    monkeypatch.setattr(Path, "write_text", fail)

    with pytest.raises(bilibili.BilibiliError):
        bilibili._write_cookies(settings, cookies)


def test_poll_qrcode_success_saves_cookies(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    settings = make_settings(tmp_path)

    class RawHeaders:
        def getlist(self, name: str) -> list[str]:
            assert name == "Set-Cookie"
            return [
                "buvid3=buv-1; Path=/; Domain=.bilibili.com; Max-Age=86400; Secure",
                "b_nut=1700000000; Path=/; Domain=.bilibili.com; Secure",
            ]

    def fake_response(payload: dict, set_cookies: list[str] | None = None) -> requests.Response:
        response = requests.Response()
        response.status_code = 200
        response._content = json.dumps(payload).encode()
        if set_cookies is not None:
            response.raw = SimpleNamespace(headers=RawHeaders())
        return response

    def fake_get(url: str, **kwargs: object) -> requests.Response:
        if url == bilibili.POLL_URL:
            return fake_response(
                {
                    "code": 0,
                    "data": {
                        "code": 0,
                        "url": (
                            "https://passport.biligame.com/crossDomain?"
                            "DedeUserID=123&DedeUserID__ckMd5=abc"
                            "&SESSDATA=sess%2Ctoken&bili_jct=csrf"
                        ),
                    },
                },
                set_cookies=["buvid3=buv-1"],
            )
        if url == bilibili.NAV_URL:
            return fake_response(
                {
                    "code": 0,
                    "data": {"isLogin": True, "uname": "tester", "vipStatus": 1},
                }
            )
        raise AssertionError(f"unexpected request: {url}")

    monkeypatch.setattr(bilibili.requests, "get", fake_get)

    result = bilibili.poll_qrcode(settings, "a" * 32)

    assert result["code"] == 0
    assert result["logged_in"] is True
    assert result["uname"] == "tester"
    assert result["vip"] is True
    entries = {
        name: value
        for name, value, _ in bilibili._read_cookie_entries(bilibili.cookie_path(settings))
    }
    assert entries["SESSDATA"] == "sess,token"
    assert entries["buvid3"] == "buv-1"


def test_write_and_read_cookie_file(tmp_path: Path) -> None:
    settings = make_settings(tmp_path)
    cookies = bilibili._collect_cookies(
        "https://passport.biligame.com/crossDomain?SESSDATA=sess%2Ctoken&bili_jct=csrf",
        ["buvid3=buv-123; Path=/; Domain=.bilibili.com; Max-Age=86400; Secure"],
    )

    bilibili._write_cookies(settings, cookies)
    path = bilibili.cookie_path(settings)

    assert path.exists()
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    content = path.read_text(encoding="utf-8")
    assert content.startswith("# Netscape HTTP Cookie File")
    assert ".bilibili.com\tTRUE\t/\tTRUE\t" in content

    entries = {name: value for name, value, _ in bilibili._read_cookie_entries(path)}
    assert entries["SESSDATA"] == "sess,token"
    assert entries["bili_jct"] == "csrf"


def test_cookiefile_for_prefers_managed_bilibili_cookies(tmp_path: Path) -> None:
    global_cookie = tmp_path / "global.txt"
    global_cookie.write_text("# global\n", encoding="utf-8")
    settings = make_settings(tmp_path, cookies_file=global_cookie)

    assert bilibili.cookiefile_for("https://www.bilibili.com/video/BV1", settings) == global_cookie

    managed = bilibili.cookie_path(settings)
    managed.parent.mkdir(parents=True)
    managed.write_text("# managed\n", encoding="utf-8")

    assert bilibili.cookiefile_for("https://www.bilibili.com/video/BV1", settings) == managed
    assert bilibili.cookiefile_for("https://b23.tv/abcd", settings) == managed
    assert bilibili.cookiefile_for("https://example.com/v", settings) == global_cookie


def test_logout_removes_only_managed_cookie(tmp_path: Path) -> None:
    global_cookie = tmp_path / "global.txt"
    global_cookie.write_text("# global\n", encoding="utf-8")
    settings = make_settings(tmp_path, cookies_file=global_cookie)
    managed = bilibili.cookie_path(settings)
    managed.parent.mkdir(parents=True)
    managed.write_text("# managed\n", encoding="utf-8")

    bilibili.logout(settings)

    assert not managed.exists()
    assert global_cookie.exists()
