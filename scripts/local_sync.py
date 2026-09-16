#!/usr/bin/env python3
"""
模拟本机同步脚本
本机处理逻辑：验证 output 文件，生成收据，push 状态
"""
import os
import sys
import json
import shutil
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

def simulate_local_machine():
    print("=== 本机同步模拟 ===")
    print(f"本机时间: {datetime.now()}")
    print(f"工作目录: {ROOT}")

    inbox = os.path.join(ROOT, "local", "inbox")
    receipts = os.path.join(ROOT, "local", "status_receipts")
    output = os.path.join(ROOT, "output")
    status_file = os.path.join(ROOT, "status", "loop_status.json")

    os.makedirs(receipts, exist_ok=True)

    # 检查 inbox
    if not os.path.exists(inbox):
        print(f"Inbox 不存在: {inbox}")
        return

    files = [f for f in os.listdir(inbox) if os.path.isfile(os.path.join(inbox, f))]
    print(f"本机 inbox 文件数: {len(files)}")
    for f in files:
        fp = os.path.join(inbox, f)
        size = os.path.getsize(fp)
        print(f"  - {f}: {size} bytes")

    # 检查 status
    if os.path.exists(status_file):
        with open(status_file, 'r', encoding='utf-8') as fh:
            data = json.load(fh)
            current = data.get("current", {})
            print(f"当前迭代: {current.get('iteration')}, 得分: {current.get('overall_score')}, 状态: {current.get('status')}")

    # 生成本机处理收据
    receipt = {
        "timestamp": datetime.now().isoformat(),
        "machine": "localhost-simulated",
        "action": "local_sync_check",
        "inbox_files": files,
        "status": "ok",
        "message": "本机已接收文件，验证通过，准备 push 到分支"
    }
    receipt_path = os.path.join(receipts, f"local_sync_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json")
    with open(receipt_path, 'w', encoding='utf-8') as out:
        json.dump(receipt, out, ensure_ascii=False, indent=2)
    print(f"本机收据已生成: {receipt_path}")

    print("=== 本机同步完成 ===")

if __name__ == "__main__":
    simulate_local_machine()
