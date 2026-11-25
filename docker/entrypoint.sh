#!/bin/sh
set -eu

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

if [ "$(id -u)" = "0" ]; then
  # 让容器内 app 用户与 NAS 上的文件属主对齐
  groupmod -o -g "$PGID" app 2>/dev/null || groupadd -o -g "$PGID" app 2>/dev/null || true
  usermod -o -u "$PUID" -g "$PGID" app 2>/dev/null || true

  mkdir -p "$DATA_DIR" "$DOWNLOAD_DIR"
  chown "$PUID:$PGID" "$DATA_DIR" "$DOWNLOAD_DIR" 2>/dev/null \
    || echo "警告：无法修改 /data 或 /downloads 的属主，请检查挂载目录权限"

  # 构建上下文来自 SMB/NAS 时可能带 600/700 权限，降权后需保证代码可读
  chmod -R a+rX /app 2>/dev/null \
    || echo "警告：无法调整 /app 权限，请检查镜像构建方式"

  exec gosu app:app "$@"
fi

exec "$@"
