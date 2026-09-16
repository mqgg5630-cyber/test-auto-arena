"""
local_bridge_skill - 与本地打通
模拟本机目录，实现文件返回本机 + 状态 push 到分支
"""
import os
import shutil
import json
import subprocess
from datetime import datetime

class LocalBridgeSkill:
    def __init__(self, 
                 output_dir="output",
                 local_dir="local",
                 status_dir="status",
                 branch="arena/01a0a93d-test-auto-arena"):
        self.output_dir = output_dir
        self.local_dir = local_dir
        self.local_inbox = os.path.join(local_dir, "inbox")
        self.local_outbox = os.path.join(local_dir, "outbox")
        self.local_receipts = os.path.join(local_dir, "status_receipts")
        self.status_dir = status_dir
        self.branch = branch

        for d in [self.local_inbox, self.local_outbox, self.local_receipts, self.status_dir, self.output_dir]:
            os.makedirs(d, exist_ok=True)

    def copy_to_local(self, iteration, files):
        """
        将生成的文件返回到本机 (local/inbox/)
        """
        copied = []
        timestamp = datetime.now().isoformat()
        for src in files:
            if not os.path.exists(src):
                continue
            filename = os.path.basename(src)
            dest = os.path.join(self.local_inbox, filename)
            # 同时保留版本化文件到本地
            shutil.copy2(src, dest)
            copied.append(dest)
            print(f"[LocalBridge] 已返回到本机: {src} -> {dest}")

        # 生成本地接收记录
        receipt = {
            "iteration": iteration,
            "timestamp": timestamp,
            "files_received": copied,
            "local_path": self.local_inbox,
            "action": "copy_to_local",
            "status": "success"
        }
        receipt_path = os.path.join(self.local_receipts, f"receipt_v{iteration}_inbox.json")
        with open(receipt_path, 'w', encoding='utf-8') as f:
            json.dump(receipt, f, ensure_ascii=False, indent=2)

        return copied

    def simulate_local_processing(self, iteration):
        """
        模拟本机处理：验证文件，生成处理收据
        """
        inbox_files = [os.path.join(self.local_inbox, f) for f in os.listdir(self.local_inbox) if os.path.isfile(os.path.join(self.local_inbox, f))]
        # 过滤出当前 iteration 的文件或 final 文件
        valid_files = []
        for fp in inbox_files:
            if os.path.getsize(fp) > 0:
                valid_files.append(fp)

        receipt = {
            "iteration": iteration,
            "timestamp": datetime.now().isoformat(),
            "action": "local_processing",
            "files_validated": len(valid_files),
            "files": valid_files,
            "local_machine": "simulated_localhost",
            "status": "processed",
            "next_action": "push_to_branch"
        }
        receipt_path = os.path.join(self.local_receipts, f"receipt_v{iteration}_processed.json")
        with open(receipt_path, 'w', encoding='utf-8') as f:
            json.dump(receipt, f, ensure_ascii=False, indent=2)

        print(f"[LocalBridge] 本机处理完成: {len(valid_files)} 文件已验证")
        return receipt

    def update_status(self, iteration, eval_result, files_info):
        """
        更新 status/loop_status.json
        """
        status_file = os.path.join(self.status_dir, "loop_status.json")
        log_file = os.path.join(self.status_dir, "loop_log.md")

        # 读取现有状态
        if os.path.exists(status_file):
            with open(status_file, 'r', encoding='utf-8') as f:
                try:
                    status_data = json.load(f)
                except:
                    status_data = {"iterations": [], "current": {}}
        else:
            status_data = {"iterations": [], "current": {}}

        # 追加当前迭代
        iteration_record = {
            "iteration": iteration,
            "timestamp": datetime.now().isoformat(),
            "eval": eval_result,
            "files": files_info,
            "branch": self.branch,
            "local_receipts": [
                f"local/status_receipts/receipt_v{iteration}_inbox.json",
                f"local/status_receipts/receipt_v{iteration}_processed.json"
            ]
        }
        status_data["iterations"].append(iteration_record)
        status_data["current"] = {
            "iteration": iteration,
            "overall_score": eval_result.get("overall_score"),
            "is_pass": eval_result.get("is_pass"),
            "status": eval_result.get("status"),
            "timestamp": datetime.now().isoformat(),
            "branch": self.branch,
            "files": files_info
        }
        status_data["meta"] = {
            "source_agent": "https://arena.ai/agent/01a0a821-3f3c-7bbe-bf99-6e6793c45d81",
            "branch": self.branch,
            "total_iterations": len(status_data["iterations"]),
            "last_update": datetime.now().isoformat()
        }

        with open(status_file, 'w', encoding='utf-8') as f:
            json.dump(status_data, f, ensure_ascii=False, indent=2)

        # 更新 log md
        log_entry = (
            f"\n## 迭代 v{iteration} - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
            f"- **综合得分**: {eval_result.get('overall_score')} / 100 (阈值 {eval_result.get('threshold')})\n"
            f"- **状态**: {eval_result.get('status')} ({'✓ 通过' if eval_result.get('is_pass') else '✗ 未通过'})\n"
            f"- **Docx得分**: {eval_result.get('docx', {}).get('score')} - {eval_result.get('docx', {}).get('details')}\n"
            f"- **Pptx得分**: {eval_result.get('pptx', {}).get('score')} - {eval_result.get('pptx', {}).get('details')}\n"
            f"- **反馈**: {eval_result.get('feedback')}\n"
            f"- **建议**: {', '.join(eval_result.get('suggestions', [])[:5])}\n"
            f"- **文件**: {files_info}\n"
            f"- **本地收据**: local/status_receipts/receipt_v{iteration}_*.json\n"
            f"- **Git分支**: {self.branch}\n"
            f"---\n"
        )

        if not os.path.exists(log_file):
            with open(log_file, 'w', encoding='utf-8') as f:
                f.write("# 自循环任务日志\n\n")
                f.write(f"源 Agent: https://arena.ai/agent/01a0a821-3f3c-7bbe-bf99-6e6793c45d81\n")
                f.write(f"分支: {self.branch}\n\n")

        with open(log_file, 'a', encoding='utf-8') as f:
            f.write(log_entry)

        print(f"[LocalBridge] 状态已更新: {status_file}")
        return status_data

    def git_push_status(self, iteration, eval_result):
        """
        将结果状态 push 到分支
        """
        try:
            # 确保在正确的分支
            subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], check=True, capture_output=True)
            
            # git add
            subprocess.run(["git", "add", "output/", "status/", "local/", "skills/", "orchestrator/", "SKILLS.md"], check=True)
            
            # 检查是否有变更
            result = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True)
            if not result.stdout.strip():
                print("[LocalBridge] 无变更，跳过 push")
                return {"pushed": False, "reason": "no_changes"}

            # commit
            commit_msg = (
                f"auto-loop v{iteration}: score {eval_result.get('overall_score')} "
                f"({'PASS' if eval_result.get('is_pass') else 'CONTINUE'}) - "
                f"docx {eval_result.get('docx', {}).get('score')} "
                f"pptx {eval_result.get('pptx', {}).get('score')} "
                f"@ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
            )
            subprocess.run(["git", "commit", "-m", commit_msg], check=True)
            print(f"[LocalBridge] 已 commit: {commit_msg}")

            # push
            # 获取当前分支名
            branch_result = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True, check=True)
            current_branch = branch_result.stdout.strip()
            print(f"[LocalBridge] 当前分支: {current_branch}, 目标推送分支: {self.branch}")

            # 尝试 push
            push_result = subprocess.run(["git", "push", "origin", current_branch], capture_output=True, text=True)
            if push_result.returncode == 0:
                print(f"[LocalBridge] 已 push 到 origin/{current_branch}")
                return {"pushed": True, "branch": current_branch, "commit": commit_msg}
            else:
                # 尝试强制推送或检查错误
                print(f"[LocalBridge] Push 输出: {push_result.stdout} {push_result.stderr}")
                # 如果分支不存在，尝试推送
                if "has no upstream" in push_result.stderr or "set-upstream" in push_result.stderr:
                    subprocess.run(["git", "push", "--set-upstream", "origin", current_branch], check=True)
                    return {"pushed": True, "branch": current_branch, "commit": commit_msg}
                return {"pushed": False, "error": push_result.stderr, "branch": current_branch}

        except subprocess.CalledProcessError as e:
            print(f"[LocalBridge] Git 操作失败: {e}")
            if e.stdout:
                print(e.stdout)
            if e.stderr:
                print(e.stderr)
            return {"pushed": False, "error": str(e)}
        except Exception as e:
            print(f"[LocalBridge] 异常: {e}")
            return {"pushed": False, "error": str(e)}

    def full_cycle(self, iteration, files, eval_result):
        """
        完整本地打通流程: copy -> local processing -> update status -> push
        """
        print(f"\n[LocalBridge] ===== 开始本地打通流程 v{iteration} =====")
        copied = self.copy_to_local(iteration, files)
        local_receipt = self.simulate_local_processing(iteration)
        status = self.update_status(iteration, eval_result, files)
        push_result = self.git_push_status(iteration, eval_result)
        print(f"[LocalBridge] ===== 本地打通流程完成 v{iteration} =====\n")
        return {
            "copied": copied,
            "local_receipt": local_receipt,
            "status": status,
            "push": push_result
        }

if __name__ == "__main__":
    bridge = LocalBridgeSkill()
    print("LocalBridgeSkill 测试")
