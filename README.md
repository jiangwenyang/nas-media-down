# NAS 媒体下载器

一个部署在 NAS 上的轻量视频下载器：粘贴网址，自动探测视频；如果链接关联播放列表（例如 YouTube `watch?v=X&list=Y`），弹窗列出条目供勾选；文件按最佳画质下载到 NAS 映射目录。

- 单容器部署（Docker Compose），不依赖外部数据库
- 强制密码登录，会话存服务端
- 播放列表勾选、任务进度、历史记录、文件浏览与在线预览
- yt-dlp + ffmpeg + Deno（YouTube 完整支持），随构建固定版本
- 深色玻璃拟态界面，适配手机

## 快速开始

1. 复制配置并设置访问密码：

   ```bash
   cp .env.example .env
   ```

   编辑 `.env`，至少修改：

   ```ini
   ACCESS_PASSWORD=你的密码
   DOWNLOAD_PATH=/volume1/media/downloads
   DATA_PATH=/volume1/docker/nas-media-down/data
   PUID=1026
   PGID=100
   ```

2. 启动：

   ```bash
   docker compose up -d --build
   ```

3. 浏览器打开 `http://NAS_IP:8080`，输入密码登录。

首次构建会下载 Node、Python、ffmpeg 与 Deno，视网络情况可能需要几分钟。

> 国内网络拉取基础镜像较慢时，可先为 Docker 配置镜像加速器，或提前执行：
> `docker pull node:22-bookworm-slim python:3.12-slim denoland/deno:bin-2.9.8`

### 群晖 / QNAP 路径示例

| 用途 | 宿主机路径（群晖示例） | 容器路径 |
| --- | --- | --- |
| 下载文件 | `/volume1/media/downloads` | `/downloads` |
| 配置与历史 | `/volume1/docker/nas-media-down/data` | `/data` |

`PUID` / `PGID` 决定下载文件在 NAS 上的属主。群晖可用 `id 用户名` 查询，常见值为 `1026:100`。

## 配置项

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `ACCESS_PASSWORD` | 无 | **必填**，未设置时容器拒绝启动 |
| `DOWNLOAD_PATH` | `./downloads` | 宿主机下载目录 |
| `DATA_PATH` | `./data` | SQLite 与会话数据目录 |
| `PUID` / `PGID` | `1026` / `100` | 文件属主 |
| `PORT` | `8080` | 对外端口 |
| `MAX_CONCURRENT` | `2` | 同时下载的任务数 |
| `MAX_PLAYLIST_ITEMS` | `500` | 播放列表单次加载/下载上限 |
| `MERGE_FORMAT` | `mp4/mkv` | 合并容器优先级；能 mp4 就 mp4，否则无损 mkv |
| `COOKIE_SECURE` | `false` | 通过 HTTPS 反向代理访问时设为 `true` |
| `COOKIES_FILE` | 空 | 容器内 cookies.txt 路径，例如 `/data/cookies.txt` |
| `HTTP_PROXY` / `HTTPS_PROXY` | 空 | NAS 需要代理访问外网时设置 |

## 需要登录或人机验证的站点（如 4kcz.com）

部分站点启用了 WAF（返回 403 或 JS 验证），直接请求拿不到网页，yt-dlp 也无法解析。处理方式：

1. 在能正常打开该站点的浏览器中导出 Netscape 格式的 `cookies.txt`（推荐扩展：Get cookies.txt LOCALLY）。
2. 把 `cookies.txt` 放到 NAS，例如 `/volume1/docker/nas-media-down/cookies.txt`。
3. 在 `docker-compose.yml` 中取消该行注释：

   ```yaml
   - ${COOKIES_PATH:-./cookies.txt}:/data/cookies.txt:ro
   ```

4. 在 `.env` 中设置 `COOKIES_FILE=/data/cookies.txt`，然后 `docker compose up -d`。

如果站点仍然无法解析，可以在浏览器开发者工具的网络面板中找到视频的 `.m3u8` 地址，直接粘贴到本产品中下载（yt-dlp 原生支持 HLS）。

## 安全建议

- 默认设计为**局域网使用**。如需公网访问，请放在 HTTPS 反向代理之后，并设置 `COOKIE_SECURE=true`。
- 登录失败限流为同一 IP 5 分钟内 5 次。
- 文件浏览接口做了路径穿越与符号链接逃逸校验，只能访问 `/downloads` 内文件。
- 删除文件不可恢复，页面上会二次确认。

## 更新 yt-dlp

站点解析规则变化频繁，建议定期重建镜像：

```bash
docker compose build --pull --no-cache
docker compose up -d
```

## 开发

后端：

```bash
python3 -m venv .venv
.venv/bin/pip install -r backend/requirements-dev.txt
ACCESS_PASSWORD=dev DOWNLOAD_DIR=./downloads DATA_DIR=./data \
  .venv/bin/uvicorn app.main:app --app-dir backend --reload --port 8080
```

前端（Vite 会把 `/api` 代理到 `127.0.0.1:8080`）：

```bash
cd frontend
npm install
npm run dev
```

测试与构建：

```bash
cd backend && ../.venv/bin/python -m pytest tests/ -q
cd frontend && npm run build
```

## 常见问题

### 启动报 `PermissionError: '/app/app/__init__.py'`

从 NAS/SMB 复制的源码可能带 600/700 权限，`COPY` 进镜像后容器内的 `app` 用户无法读取。当前版本会在构建时与容器启动时执行 `chmod -R a+rX /app`。更新代码后重新构建即可：

```bash
docker compose build
docker compose up -d
```

不需要 `--no-cache`，Dockerfile 变更会使相关层自动重建。

## 已知限制

- 容器重启不会续传进行中的下载，任务会标记为「已中断」，可手动重新下载。
- 取消操作在视频信息提取阶段无法立即生效，进入传输后才会中断。
- 最佳画质通常产出 mkv（AV1/VP9/Opus 无损）；如需更广的播放器兼容性，可把 `MERGE_FORMAT` 改为 `mp4`，但不兼容编码仍会回退 mkv。
- 单进程运行（`--workers 1`），任务状态保存在内存并由 SQLite 持久化。
