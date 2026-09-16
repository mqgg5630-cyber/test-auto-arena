#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""自循环任务编排器（入口）。

闭环: 生成(docx/pptx) → 验证(0-100分) → 状态写入 + git push → 未达标则带失败项进入下一轮自修复。
收敛: 得分 >= pass_score（默认 100）→ DONE，自动停止。
运行: .venv/bin/python pipeline/loop.py
"""
import json
import os
import subprocess
import sys
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from skills.docx_skill import build_docx      # noqa: E402
from skills.pptx_skill import build_pptx      # noqa: E402
from skills.validator import validate         # noqa: E402

BRANCH = "arena/01a0a948-test-auto-arena"
DOCX = os.path.join(ROOT, "output", "doc", "report.docx")
PPTX = os.path.join(ROOT, "output", "slides", "deck.pptx")
STATUS_DIR = os.path.join(ROOT, "status")
STATUS_JSON = os.path.join(STATUS_DIR, "loop_status.json")
ISSUES_JSON = os.path.join(STATUS_DIR, "issues.json")
REPORT_MD = os.path.join(STATUS_DIR, "REPORT.md")
CONFIG = os.path.join(ROOT, "pipeline", "config.json")


def now():
    return datetime.now().astimezone().isoformat(timespec="seconds")


def git(*args, timeout=180):
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True,
                       text=True, env=env, timeout=timeout)
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def git_commit(message):
    """git add -A + commit；无变更时返回 None。"""
    rc, _out, err = git("add", "-A")
    if rc != 0:
        raise RuntimeError("git add failed: %s" % err)
    rc, out, err = git("commit", "-m", message)
    if rc == 0:
        _rc2, sha, _e2 = git("rev-parse", "--short", "HEAD")
        return sha
    if "nothing to commit" in (out + err):
        return None
    raise RuntimeError("git commit failed: %s" % err)


def git_push():
    rc, out, err = git("push", "origin", BRANCH)
    if rc == 0:
        return True, ""
    tail = (err or out).strip().splitlines()
    return False, tail[-1] if tail else "unknown error"


def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:  # noqa: BLE001
        return None


def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def write_status(it, max_iter, pass_score, score, status_str, checks, history):
    save_json(STATUS_JSON, {
        "updated_at": now(),
        "branch": BRANCH,
        "iteration": it,
        "max_iterations": max_iter,
        "pass_score": pass_score,
        "score": score,
        "status": status_str,
        "checks": checks,
        "history": history,
        "artifacts": {
            "docx": "output/doc/report.docx",
            "pptx": "output/slides/deck.pptx",
        },
    })


def write_issues(it, score, failed, prev_failed):
    save_json(ISSUES_JSON, {
        "updated_at": now(),
        "iteration": it,
        "score": score,
        "issues": failed,
        "resolved": [x for x in prev_failed if x not in failed],
    })


def write_report(it, max_iter, pass_score, score, status_str, checks, history):
    icon = {"DONE": "[OK]", "ITERATING": "[LOOP]", "MAX_REACHED": "[WARN]",
            "PUSH_FAILED": "[FAIL]", "VALIDATING": "[..."}.get(status_str, "[..]")
    lines = [
        "# 自动循环流水线 · 状态报告",
        "",
        "最近更新: %s" % now(),
        "分支: `%s`" % BRANCH,
        "当前迭代: %d / %d · 收敛阈值: %d/100" % (it, max_iter, pass_score),
        "",
        "## 当前状态: %s %s（得分 %s/100）" % (
            icon, status_str, score if score is not None else "-"),
        "",
        "## 本轮验证明细",
        "",
        "| 检查项 | 权重 | 结果 | 说明 |",
        "| --- | --- | --- | --- |",
    ]
    for c in checks or []:
        mark = "PASS" if c["passed"] else "FAIL"
        lines.append("| %s | %d | %s %s | %s |" % (
            c["name"], c["weight"], mark, c.get("detail", ""), c["desc"]))
    lines += [
        "",
        "## 迭代历史",
        "",
        "| 迭代 | 得分 | 失败项 | 状态 | commit | push | 时间 |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for h in history:
        lines.append("| %s | %s/100 | %d | %s | %s | %s | %s |" % (
            h["iteration"], h["score"], len(h["failed"]), h["status"],
            h.get("commit") or "-", h.get("push") or "-", h["timestamp"]))
    lines.append("")
    with open(REPORT_MD, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def main():
    cfg = load_json(CONFIG) or {}
    max_iter = int(cfg.get("max_iterations", 4))
    pass_score = int(cfg.get("pass_score", 100))

    prev = load_json(STATUS_JSON) or {}
    history = list(prev.get("history", []))
    if history and history[-1].get("status") == "DONE":
        print("流水线已收敛（DONE），无需继续循环。")
        return 0
    prev_issues = (load_json(ISSUES_JSON) or {}).get("issues", [])

    os.makedirs(os.path.dirname(DOCX), exist_ok=True)
    os.makedirs(os.path.dirname(PPTX), exist_ok=True)
    os.makedirs(STATUS_DIR, exist_ok=True)

    start = len(history) + 1
    push_fail_streak = 0
    final_status = "UNKNOWN"

    for it in range(start, max_iter + 1):
        fixes = set(prev_issues)
        level = min(it, 3)
        print("\n===== 迭代 %d/%d (level=%d, 修复项=%s) ====="
              % (it, max_iter, level, sorted(fixes) or "无"))

        build_docx(DOCX, level=level, fixes=fixes, history=history)
        build_pptx(PPTX, level=level, fixes=fixes, history=history)

        # 先落一份「验证中」状态，供 status_written 检查项读取
        write_status(it, max_iter, pass_score, None, "VALIDATING", None, history)
        score, checks = validate(ROOT)
        failed = [c["id"] for c in checks if not c["passed"]]
        print("验证得分: %d/100, 失败项: %s" % (score, failed or "无"))

        done = score >= pass_score
        if done:
            print("达到收敛阈值 → 将本轮验证结果写回文档，产出最终版")
            result = {"score": score, "checks": checks}
            build_docx(DOCX, level=level, fixes=fixes, history=history, result=result)
            build_pptx(PPTX, level=level, fixes=fixes, history=history, result=result)
            score, checks = validate(ROOT)
            failed = [c["id"] for c in checks if not c["passed"]]
            done = score >= pass_score

        status_str = "DONE" if done else ("MAX_REACHED" if it == max_iter else "ITERATING")
        entry = {
            "iteration": it, "level": level, "score": score, "failed": failed,
            "status": status_str, "push": "pending", "commit": "",
            "timestamp": now(),
        }
        history.append(entry)
        write_status(it, max_iter, pass_score, score, status_str, checks, history)
        write_issues(it, score, failed, prev_issues)
        write_report(it, max_iter, pass_score, score, status_str, checks, history)

        sha = git_commit("auto-loop: iter %d · score %d/100 · %s"
                         % (it, score, status_str))
        entry["commit"] = sha or ""
        ok, tail = git_push()
        entry["push"] = "ok" if ok else "FAILED(%s)" % tail
        print("commit %s pushed=%s%s" % (sha, ok, "" if ok else " (%s)" % tail))
        push_fail_streak = 0 if ok else push_fail_streak + 1

        # 推送结果回写状态文件并补一个小提交，保证分支上的状态与推送结果一致
        write_status(it, max_iter, pass_score, score, status_str, checks, history)
        write_report(it, max_iter, pass_score, score, status_str, checks, history)
        sha2 = git_commit("auto-loop: iter %d status-sync · push=%s"
                          % (it, entry["push"]))
        if sha2:
            entry["commit2"] = sha2
            ok2, tail2 = git_push()
            if not ok2:
                entry["push"] = "%s (sync FAILED(%s))" % (entry["push"], tail2)
                push_fail_streak += 1
        print("状态已回写并推送 (commit %s / %s)" % (sha or "-", sha2 or "-"))

        final_status = status_str
        if done:
            break
        prev_issues = failed

        if push_fail_streak >= 2:
            final_status = "PUSH_FAILED"
            write_status(it, max_iter, pass_score, score, "PUSH_FAILED", checks, history)
            write_report(it, max_iter, pass_score, score, "PUSH_FAILED", checks, history)
            git_commit("auto-loop: iter %d · PUSH_FAILED · 连续推送失败，暂停循环" % it)
            print("连续推送失败，循环暂停，请检查 GitHub 连接。")
            break

    print("\n===== 循环结束 · 最终状态: %s =====" % final_status)
    return 0 if final_status == "DONE" else 1


if __name__ == "__main__":
    sys.exit(main())
