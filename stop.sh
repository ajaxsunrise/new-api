#!/bin/bash

# 项目停止脚本

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$SCRIPT_DIR/.server.pid"

stop_by_pid() {
    local PID="$1"
    if ! kill -0 "$PID" 2>/dev/null; then
        return 1
    fi
    echo "停止服务 (PID: $PID)..."
    kill "$PID" 2>/dev/null

    # 等待进程结束
    for i in {1..10}; do
        if ! kill -0 "$PID" 2>/dev/null; then
            return 0
        fi
        sleep 1
    done

    # 强制杀死
    if kill -0 "$PID" 2>/dev/null; then
        echo "强制停止服务..."
        kill -9 "$PID" 2>/dev/null
        sleep 1
    fi
    ! kill -0 "$PID" 2>/dev/null
}

# 方式1: 通过PID文件停止
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        if stop_by_pid "$PID"; then
            rm -f "$PID_FILE"
            echo "服务已停止"
            exit 0
        else
            rm -f "$PID_FILE"
            echo "停止失败"
            exit 1
        fi
    else
        echo "PID文件中的进程不存在 (PID: $PID)，清理PID文件"
        rm -f "$PID_FILE"
    fi
fi

# 方式2: 通过端口查找进程停止
PORT_PID=$(lsof -ti :3000 2>/dev/null | head -1)
if [ -n "$PORT_PID" ]; then
    echo "PID文件未找到，通过端口3000发现进程 (PID: $PORT_PID)"
    if stop_by_pid "$PORT_PID"; then
        rm -f "$PID_FILE"
        echo "服务已停止"
        exit 0
    else
        echo "停止失败"
        exit 1
    fi
fi

echo "未找到运行中的服务"
exit 0

