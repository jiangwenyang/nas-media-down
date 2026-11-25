"""接口请求模型。"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class LoginBody(BaseModel):
    """登录请求。"""

    password: str = Field(min_length=1, max_length=256)


class ProbeBody(BaseModel):
    """URL 探测请求。"""

    url: str = Field(min_length=1, max_length=4096)


class JobItemInput(BaseModel):
    """待下载条目的元数据（来自探测结果）。"""

    index: int = Field(ge=1)
    title: str = Field(default="", max_length=1000)
    duration: float | None = Field(default=None, ge=0)
    thumbnail: str | None = Field(default=None, max_length=2048)


class JobCreateBody(BaseModel):
    """创建下载任务。"""

    url: str = Field(min_length=1, max_length=4096)
    kind: Literal["video", "playlist"] = "video"
    playlist_id: str | None = Field(default=None, max_length=500)
    playlist_title: str | None = Field(default=None, max_length=500)
    entries: list[JobItemInput] = Field(min_length=1, max_length=2000)


class BangumiSubscribeBody(BaseModel):
    """添加追番/追剧订阅。

    mode=watch 只跟踪后续更新；mode=all 同时下载当前已发布的全部剧集。
    """

    season_id: int = Field(gt=0)
    media_type: Literal[1, 2] = 1
    mode: Literal["watch", "all"] = "watch"


class BangumiUpdateBody(BaseModel):
    """修改订阅开关。"""

    enabled: bool | None = None
    auto_download: bool | None = None


class BangumiDownloadBody(BaseModel):
    """下载指定剧集（按剧集在季内的序号选择）。"""

    season_id: int = Field(gt=0)
    episode_indices: list[int] = Field(min_length=1, max_length=2000)


class ShareLinkBody(BaseModel):
    """为下载目录内的文件签发短期分享链接。"""

    path: str = Field(min_length=1, max_length=4096)
