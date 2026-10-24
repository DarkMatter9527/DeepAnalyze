#!/bin/bash

echo "Starting Chat System"
echo "=========================="

# Ensure logs directory exists
mkdir -p logs

# Function to check and free ports（部分容器无 lsof，需 fuser 兜底）
check_port() {
    local port=$1
    local pids
    if command -v lsof >/dev/null 2>&1; then
        pids=$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)
        if [ -n "$pids" ]; then
            echo "Port $port in use by PIDs: $pids. Terminating..."
            kill $pids 2>/dev/null || true
            sleep 1
            pids=$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)
            if [ -n "$pids" ]; then
                echo "Force terminating remaining PIDs on $port: $pids"
                kill -9 $pids 2>/dev/null || true
                sleep 1
            fi
        fi
    fi
    if command -v fuser >/dev/null 2>&1; then
        if fuser "$port/tcp" >/dev/null 2>&1; then
            echo "Port $port still held; fuser -k ${port}/tcp"
            fuser -k "$port/tcp" 2>/dev/null || true
            sleep 1
        fi
    fi
}

# Clean up old processes（避免与 API/start_server.py 等其它占用 8200 的进程冲突）
echo "Cleaning old processes..."
pkill -f "python.*backend.py" 2>/dev/null || true
pkill -f "python.*start_server.py" 2>/dev/null || true
pkill -f "python.*API/main.py" 2>/dev/null || true
pkill -f "npm.*dev" 2>/dev/null || true
# Extra cleanup for child processes that may outlive npm
pkill -f "vite.*serve" 2>/dev/null || true
pkill -f "node.*vite" 2>/dev/null || true
pkill -f "react-scripts.*start" 2>/dev/null || true

# Frontend port (default 6008, can override via FRONTEND_PORT)
FRONTEND_PORT=${FRONTEND_PORT:-6008}

# Check and clean ports (only LISTENers)
check_port 8100
check_port 8200
check_port "$FRONTEND_PORT"

echo "Cleanup completed."
echo ""

# Start backend API (ports 8200, 8100)
echo "Starting backend API..."
nohup python3 backend.py > logs/backend.log 2>&1 &
BACKEND_PID=$!
echo "Backend PID: $BACKEND_PID"
echo "API running on: http://0.0.0.0:8200"
echo "File service running on: http://0.0.0.0:8100"

# Wait for backend to initialize
sleep 3

if ! curl -sf "http://127.0.0.1:8200/workspace/tree?session_id=default" >/dev/null; then
    echo ""
    echo "ERROR: 后端未在 8200 端口就绪（常见于端口仍被其它进程占用）。"
    echo "       请查看 logs/backend.log；可先执行: FRONTEND_PORT=$FRONTEND_PORT ./stop.sh"
    echo "       勿同时运行 demo/chat/backend.py 与 API/start_server.py（均占用 8200）。"
    exit 1
fi

# Start frontend (React, default port: $FRONTEND_PORT)
echo ""
echo "Starting React frontend..."
cd frontend || exit
nohup npm run dev -- -H 0.0.0.0 -p "$FRONTEND_PORT" > ../logs/frontend.log 2>&1 &
FRONTEND_PID=$!
cd ..
echo "Frontend PID: $FRONTEND_PID"
echo "Frontend running on: http://0.0.0.0:$FRONTEND_PORT"

# Save PIDs
echo $BACKEND_PID > logs/backend.pid
echo $FRONTEND_PID > logs/frontend.pid

echo ""
echo "All services started successfully."
echo ""
echo "Service URLs:"
echo "  Backend API:  http://0.0.0.0:8200"
echo "  Frontend:     http://0.0.0.0:$FRONTEND_PORT"
echo "  File Service: http://0.0.0.0:8100"
echo ""
echo "自定义服务（AutoDL / SeeTacloud 等）：请在控制台打开「127.0.0.1:${FRONTEND_PORT}」对应的外链 https 地址；"
echo "  勿混用 6006 与 ${FRONTEND_PORT} 的链接（二者映射不同本地端口）。"
echo ""
echo "Log files:"
echo "  Backend: logs/backend.log"
echo "  Frontend: logs/frontend.log"
echo ""
echo "Stop services: ./stop.sh"
