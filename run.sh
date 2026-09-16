#!/bin/bash
set -e

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"

echo "=========================================="
echo "自循环任务 - Arena Agent Skills 安装"
echo "源: https://arena.ai/agent/01a0a821-3f3c-7bbe-bf99-6e6793c45d81"
echo "分支: arena/01a0a93d-test-auto-arena"
echo "=========================================="

# 安装依赖
echo "[1/3] 安装依赖..."
pip3 install -q -r requirements.txt || pip install -q -r requirements.txt
echo "依赖安装完成"

# 确保目录
mkdir -p output status local/inbox local/outbox local/status_receipts

# 运行自循环
echo "[2/3] 启动自循环任务..."
python3 orchestrator/self_loop.py
EXIT_CODE=$?

echo "[3/3] 验证输出..."
ls -lh output/
ls -lh status/
ls -lh local/inbox/ | head -20
ls -lh local/status_receipts/ | head -20

echo "=========================================="
echo "最终输出:"
cat status/final_summary.json || echo "无 final_summary"
echo "=========================================="

echo "Git 状态:"
git status --short
git log --oneline -10

echo "完成，退出码: $EXIT_CODE"
exit $EXIT_CODE
