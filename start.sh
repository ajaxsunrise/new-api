#!/bin/bash

# 项目启动脚本

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$SCRIPT_DIR/.server.pid"
LOG_FILE="$SCRIPT_DIR/logs/server.log"

mkdir -p "$SCRIPT_DIR/logs"

# 检查进程是否已运行
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "服务已在运行 (PID: $PID)"
        exit 0
    fi
    rm -f "$PID_FILE"
fi

echo "启动服务..."

cd "$SCRIPT_DIR"

# 如果已有编译好的二进制，使用它；否则用 go run
if [ -f "$SCRIPT_DIR/new-api" ]; then
    nohup "$SCRIPT_DIR/new-api" > "$LOG_FILE" 2>&1 &
    SERVER_PID=$!
else
    nohup go run main.go > "$LOG_FILE" 2>&1 &
    SERVER_PID=$!
fi

echo $SERVER_PID > "$PID_FILE"
echo "服务已启动 (PID: $SERVER_PID)"
echo "日志文件: $LOG_FILE"

# 等待服务启动
sleep 3

# 检查服务是否成功启动（通过检查日志文件是否有 "Network:" 或端口监听）
if grep -q "Network:" "$LOG_FILE" 2>/dev/null || kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "服务启动成功"
    tail -3 "$LOG_FILE"
else
    echo "服务启动失败，请检查日志: $LOG_FILE"
    exit 1
fi

