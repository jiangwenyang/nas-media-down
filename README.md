# NAS 媒体下载器

一个部署在 NAS 上的轻量视频下载器：粘贴网址，自动探测视频；如果链接关联播放列表（例如 YouTube `watch?v=X&list=Y`），弹窗列出条目供勾选；文件按最佳画质下载到 NAS 映射目录。

- 单容器部署（Docker Compose），不依赖外部数据库
- 强制密码登录，会话存服务端
- 播放列表勾选、列表内并行下载、失败条目单独重试、任务进度、历史记录、文件浏览与在线预览
- 哔哩哔哩扫码登录，支持下载大会员专属清晰度
- 追番/追剧：读取 B 站关注列表，订阅后自动下载新剧集，也可一次下载整季
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
| `MAX_CONCURRENT` | `2` | 同时下载的视频数（跨任务共享，播放列表内也会并行） |
| `MAX_PLAYLIST_ITEMS` | `500` | 播放列表单次加载/下载上限 |
| `BANGUMI_CHECK_INTERVAL` | `1800` | 追番/追剧自动检查间隔（秒），最小 60 |
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

## 哔哩哔哩扫码登录

1. 打开「账号」页，点击「扫码登录」。
2. 用哔哩哔哩 App 扫码，并在手机上确认登录。
3. 登录成功后 Cookie 保存在 `${DATA_DIR}/bilibili-cookies.txt`（权限 600），仅用于 `bilibili.com` / `b23.tv` 链接。

- 大会员账号可下载会员专属清晰度，请遵守哔哩哔哩服务条款。
- 登录态过期后页面会显示未登录，重新扫码即可；「退出登录」会删除该 Cookie 文件。
- 已配置的全局 `COOKIES_FILE` 仍用于其他站点，不会被覆盖。

## 追番 / 追剧

1. 先在「账号」页扫码登录哔哩哔哩（关注列表需要登录态才能读取）。
2. 打开「追番」页，在「番剧 / 追剧」之间切换，浏览自己的关注列表：
   - **追更**：只跟踪后续更新，已在列表中的剧集不会下载。
   - **下载全集**：订阅并立即把当前已发布的全部剧集加入下载队列。
   - **选集下载**：打开剧集列表，勾选任意集数下载；已下载或排队中的剧集不可重复选择。
3. 「正在追更」区域可查看下载进度、立即检查、手动下载全部、开关自动下载或取消追更。

- 后台每隔 `BANGUMI_CHECK_INTERVAL` 秒检查一次（默认 30 分钟），发现新剧集后自动创建播放列表任务，按剧名分目录保存。
- 每集的下载状态会与任务状态同步；失败可在「任务」页单独重试。
- 自动下载只针对订阅之后的更新；重新开启自动下载不会补下关闭期间遗漏的剧集，可点「下载全部」补齐。
- 付费/大会员专属剧集仍受账号权限限制；请遵守哔哩哔哩服务条款。

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
cp .env.example .env          # 首次：至少填好 ACCESS_PASSWORD
.venv/bin/uvicorn app.main:app --app-dir backend --reload --port 8080
```

后端启动时会自动读取项目根目录的 `.env`（进程环境变量优先，docker-compose 用的是同一份）。
本地开发不设置 `DOWNLOAD_DIR` / `DATA_DIR` 时，默认使用仓库下的 `downloads/` 和 `data/`。

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
