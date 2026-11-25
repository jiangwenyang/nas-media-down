"""FastAPI 应用入口：API 路由、静态前端与启动恢复。"""

from __future__ import annotations

import logging
import mimetypes
import re
import shutil
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import APIRouter, Depends, FastAPI, HTTPException, Query, Request, Response
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from . import auth, bangumi, bilibili, db
from .config import APP_VERSION, ConfigError, load_settings
from .downloader import JobCreateError, JobManager
from .files import FileAccessError, list_dir, resolve_path
from .models import (
    BangumiDownloadBody,
    BangumiSubscribeBody,
    BangumiUpdateBody,
    JobCreateBody,
    ProbeBody,
)
from .probe import ProbeError, probe_url

logger = logging.getLogger(__name__)

STATIC_DIR = Path(__file__).resolve().parent.parent / "static"
INLINE_MIME_PREFIXES = ("video/", "audio/", "image/")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """启动时校验配置、初始化数据库并恢复中断任务。"""
    try:
        settings = load_settings()
    except ConfigError as exc:
        logger.critical("配置错误：%s", exc)
        raise

    settings.download_dir.mkdir(parents=True, exist_ok=True)
    settings.data_dir.mkdir(parents=True, exist_ok=True)
    db_path = settings.data_dir / "nas-media-down.db"
    db.init_db(db_path)
    db.mark_interrupted_jobs(db_path)
    db.purge_expired_sessions(db_path)

    app.state.settings = settings
    app.state.db_path = db_path
    app.state.login_limiter = auth.LoginRateLimiter()
    app.state.jobs = JobManager(settings)
    app.state.bangumi = bangumi.BangumiManager(settings, app.state.jobs)
    app.state.bangumi.start()
    logger.info("服务已启动，下载目录：%s", settings.download_dir)
    try:
        yield
    finally:
        app.state.bangumi.stop()
        app.state.jobs.shutdown()


app = FastAPI(
    title="NAS Media Down",
    version=APP_VERSION,
    lifespan=lifespan,
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
)

app.include_router(auth.router)


@app.get("/api/health")
def health() -> dict[str, str]:
    """容器健康检查，公开访问。"""
    return {"status": "ok", "version": APP_VERSION}


api = APIRouter(prefix="/api", dependencies=[Depends(auth.require_auth)])


@api.post("/probe")
def probe(body: ProbeBody, request: Request) -> dict:
    """探测 URL，返回单视频信息或播放列表条目。"""
    settings = request.app.state.settings
    try:
        return probe_url(body.url, settings)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except ProbeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@api.post("/jobs")
def create_job(body: JobCreateBody, request: Request) -> dict:
    """创建下载任务。"""
    manager: JobManager = request.app.state.jobs
    try:
        runtime = manager.create(body)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except JobCreateError as exc:
        raise HTTPException(status_code=exc.status_code, detail=str(exc)) from exc
    return {"job_id": runtime.id, "item_count": len(runtime.items)}


@api.get("/jobs")
def list_jobs(
    request: Request,
    limit: int = Query(default=100, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> dict:
    """任务列表，活动任务附带实时条目进度。"""
    manager: JobManager = request.app.state.jobs
    return {"jobs": manager.list_jobs(limit, offset)}


@api.get("/jobs/{job_id}")
def get_job(job_id: str, request: Request) -> dict:
    """任务详情与全部子条目。"""
    manager: JobManager = request.app.state.jobs
    data = manager.get_job(job_id)
    if data is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    return data


@api.post("/jobs/{job_id}/cancel", status_code=202)
def cancel_job(job_id: str, request: Request) -> dict[str, bool]:
    """请求取消任务。"""
    manager: JobManager = request.app.state.jobs
    if not manager.cancel(job_id):
        raise HTTPException(status_code=404, detail="任务不存在或已结束")
    return {"ok": True}


@api.delete("/jobs/{job_id}", status_code=204)
def delete_job(job_id: str, request: Request) -> Response:
    """删除任务历史记录（不删除文件）。"""
    manager: JobManager = request.app.state.jobs
    if not manager.delete_job(job_id):
        raise HTTPException(status_code=404, detail="任务不存在")
    return Response(status_code=204)


@api.get("/files")
def files_list(request: Request, path: str = "") -> dict:
    """浏览下载目录。"""
    settings = request.app.state.settings
    try:
        return list_dir(settings.download_dir, path)
    except FileAccessError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc


@api.get("/files/content")
def file_content(request: Request, path: str, inline: bool = False) -> FileResponse:
    """下载或内联预览文件；FileResponse 自带 Range 支持。"""
    settings = request.app.state.settings
    try:
        target = resolve_path(settings.download_dir, path)
    except FileAccessError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    if not target.is_file():
        raise HTTPException(status_code=404, detail="文件不存在")

    media_type = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
    allow_inline = inline and (
        media_type.startswith(INLINE_MIME_PREFIXES) or media_type == "application/pdf"
    )
    return FileResponse(
        target,
        media_type=media_type,
        filename=target.name,
        content_disposition_type="inline" if allow_inline else "attachment",
    )


@api.delete("/files", status_code=204)
def delete_file(request: Request, path: str, recursive: bool = False) -> Response:
    """删除下载目录内的文件或目录。"""
    settings = request.app.state.settings
    root = settings.download_dir.resolve()
    try:
        target = resolve_path(root, path)
    except FileAccessError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    if target == root:
        raise HTTPException(status_code=400, detail="不能删除下载根目录")
    if not target.exists():
        raise HTTPException(status_code=404, detail="文件不存在")
    if target.is_dir():
        if not recursive:
            raise HTTPException(status_code=400, detail="删除目录需要 recursive=true")
        shutil.rmtree(target)
    else:
        target.unlink()
    return Response(status_code=204)


@api.post("/bilibili/qrcode")
def bilibili_qrcode() -> dict:
    """生成哔哩哔哩登录二维码。"""
    try:
        return bilibili.generate_qrcode()
    except bilibili.BilibiliError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@api.get("/bilibili/qrcode/poll")
def bilibili_poll(request: Request, key: str) -> dict:
    """轮询扫码状态；登录成功后把 Cookie 保存到 DATA_DIR。"""
    if not re.fullmatch(r"[A-Za-z0-9]{16,64}", key):
        raise HTTPException(status_code=400, detail="无效的二维码参数")
    try:
        return bilibili.poll_qrcode(request.app.state.settings, key)
    except bilibili.BilibiliError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@api.get("/bilibili/status")
def bilibili_status(request: Request) -> dict:
    """返回哔哩哔哩登录态与大会员状态。"""
    return bilibili.session_status(request.app.state.settings)


@api.post("/bilibili/logout")
def bilibili_logout(request: Request) -> dict[str, bool]:
    """删除本地哔哩哔哩登录 Cookie。"""
    bilibili.logout(request.app.state.settings)
    return {"ok": True}


def _bangumi_error(exc: Exception) -> HTTPException:
    return HTTPException(status_code=502, detail=str(exc))


@api.get("/bangumi/follow")
def bangumi_follow(
    request: Request,
    media_type: int = Query(default=1, alias="type", ge=1, le=2),
    page: int = Query(default=1, ge=1, le=100),
    vmid: str | None = Query(default=None, pattern=r"^\d{1,20}$"),
) -> dict:
    """读取当前账号的追番（type=1）或追剧（type=2）列表。"""
    try:
        data = bangumi.fetch_follow_list(
            request.app.state.settings, media_type, page, vmid
        )
    except bangumi.BangumiError as exc:
        raise _bangumi_error(exc) from exc
    subscriptions = request.app.state.bangumi.subscriptions_by_season()
    for item in data["items"]:
        item["subscribed"] = item["season_id"] in subscriptions
        item["subscription_id"] = subscriptions.get(item["season_id"])
    return data


@api.get("/bangumi/season/{season_id}")
def bangumi_season(season_id: int, request: Request) -> dict:
    """返回剧集列表；已订阅时附带每集下载状态。"""
    if season_id <= 0:
        raise HTTPException(status_code=400, detail="无效的剧集编号")
    try:
        return request.app.state.bangumi.season_detail(season_id)
    except bangumi.BangumiError as exc:
        raise _bangumi_error(exc) from exc


@api.post("/bangumi/download")
def bangumi_download_episodes(body: BangumiDownloadBody, request: Request) -> dict:
    """下载选中的剧集；已订阅的剧集会同步更新下载状态。"""
    try:
        return request.app.state.bangumi.download_episodes(
            body.season_id, body.episode_indices
        )
    except bangumi.BangumiError as exc:
        raise _bangumi_error(exc) from exc


@api.get("/bangumi/subscriptions")
def bangumi_subscriptions(request: Request) -> dict:
    """返回全部追番订阅及下载统计。"""
    return {"subscriptions": request.app.state.bangumi.list_subscriptions()}


@api.post("/bangumi/subscriptions")
def bangumi_subscribe(body: BangumiSubscribeBody, request: Request) -> dict:
    """订阅一部剧；mode=all 时同时下载已发布剧集。"""
    try:
        return request.app.state.bangumi.subscribe(
            body.media_type, body.season_id, body.mode
        )
    except bangumi.BangumiError as exc:
        raise _bangumi_error(exc) from exc


@api.patch("/bangumi/subscriptions/{sub_id}")
def bangumi_update_subscription(
    sub_id: str, body: BangumiUpdateBody, request: Request
) -> dict:
    """切换订阅的启用状态或自动下载开关。"""
    data = request.app.state.bangumi.update_subscription(
        sub_id, body.enabled, body.auto_download
    )
    if data is None:
        raise HTTPException(status_code=404, detail="订阅不存在")
    return data


@api.delete("/bangumi/subscriptions/{sub_id}", status_code=204)
def bangumi_delete_subscription(sub_id: str, request: Request) -> Response:
    """取消订阅（不删除已下载文件）。"""
    if not request.app.state.bangumi.delete_subscription(sub_id):
        raise HTTPException(status_code=404, detail="订阅不存在")
    return Response(status_code=204)


@api.post("/bangumi/subscriptions/{sub_id}/check")
def bangumi_check_subscription(sub_id: str, request: Request) -> dict:
    """立即检查一部剧的更新。"""
    data = request.app.state.bangumi.check(sub_id)
    if data is None:
        raise HTTPException(status_code=404, detail="订阅不存在")
    return data


@api.post("/bangumi/subscriptions/{sub_id}/download-all")
def bangumi_download_all(sub_id: str, request: Request) -> dict:
    """下载该剧当前已发布的全部剧集。"""
    try:
        return request.app.state.bangumi.download_all(sub_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail="订阅不存在") from exc
    except bangumi.BangumiError as exc:
        raise _bangumi_error(exc) from exc


app.include_router(api)


def _mount_static() -> None:
    """存在构建产物时挂载带哈希的静态资源；开发模式下静默跳过。"""
    assets_dir = STATIC_DIR / "assets"
    if assets_dir.is_dir():
        app.mount("/assets", StaticFiles(directory=assets_dir), name="assets")


_mount_static()


@app.get("/{full_path:path}", include_in_schema=False)
def spa_fallback(full_path: str):
    """SPA 路由回退：静态文件优先，其余返回 index.html。"""
    if full_path == "api" or full_path.startswith("api/"):
        raise HTTPException(status_code=404, detail="接口不存在")

    static_root = STATIC_DIR.resolve()
    if full_path:
        candidate = (static_root / full_path).resolve()
        if candidate.is_relative_to(static_root) and candidate.is_file():
            return FileResponse(candidate)

    index = static_root / "index.html"
    if index.is_file():
        return FileResponse(index)
    return JSONResponse(
        {"detail": "前端尚未构建，请先在 frontend 目录执行 npm run build"}, status_code=503
    )
