#!/bin/bash

# 项目重启脚本

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 停止服务
"$SCRIPT_DIR/stop.sh"

# 等待端口释放
for i in {1..10}; do
    if ! lsof -ti :3000 >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# 端口仍被占用
if lsof -ti :3000 >/dev/null 2>&1; then
    echo "错误: 端口3000仍被占用，无法启动"
    lsof -i :3000
    exit 1
fi

# 启动服务
"$SCRIPT_DIR/start.sh"

