#!/bin/bash
set -e
echo "=== 设置本地打通桥接 ==="
ROOT=$(cd "$(dirname "$0")/.." && pwd)
echo "项目根: $ROOT"

mkdir -p "$ROOT/local/inbox" "$ROOT/local/outbox" "$ROOT/local/status_receipts"
mkdir -p "$ROOT/output" "$ROOT/status"

echo "目录结构:"
ls -R "$ROOT/local"

echo "安装依赖..."
pip3 install -r "$ROOT/requirements.txt" || pip install -r "$ROOT/requirements.txt"

echo "本地桥接设置完成"
echo "可运行: python3 orchestrator/self_loop.py"
