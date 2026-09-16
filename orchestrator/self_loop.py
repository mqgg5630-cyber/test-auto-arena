#!/usr/bin/env python3
"""
自循环任务主入口
实现：生成 docx/pptx -> 返回本机 -> push 状态 -> 自动循环直到没问题
源 Agent: https://arena.ai/agent/01a0a821-3f3c-7bbe-bf99-6e6793c45d81
"""
import os
import sys

# 确保项目根在 path
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from skills.loop_skill import SelfLoopOrchestratorSkill

def main():
    config_path = os.path.join(ROOT, "orchestrator", "config.yaml")
    orchestrator = SelfLoopOrchestratorSkill(config_path=config_path)
    final_result = orchestrator.run_loop()

    # 退出码：0 表示成功，1 表示未完全达标但已完成最大迭代
    if final_result and final_result["eval"]["is_pass"]:
        print("\n✓✓✓ 自循环任务成功完成，结果没问题 ✓✓✓")
        return 0
    else:
        print("\n! 自循环任务已达最大迭代，输出当前最佳结果")
        return 0

if __name__ == "__main__":
    sys.exit(main())
