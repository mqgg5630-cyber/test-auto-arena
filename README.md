# test-auto-arena

自动循环流水线（self-loop pipeline）：安装 docx/pptx 生成与验证技能，与本地打通，
自动生成 docx + pptx 产物，将每轮结果状态 push 到分支，自动循环直到验证全部通过（收敛即停）。

## 目录

- `skills/` — 已安装技能（docx 生成 / pptx 生成 / 验证评分）
- `pipeline/` — 自循环编排器（`loop.py` 入口）+ 内容模型 + 配置
- `output/` — 生成产物：`doc/report.docx`、`slides/deck.pptx`
- `status/` — `loop_status.json` / `issues.json` / `REPORT.md`（每轮 push 到分支，可追溯）

## 运行

```bash
python3 -m venv .venv
.venv/bin/pip install -r pipeline/requirements.txt
.venv/bin/python pipeline/loop.py
```

## 闭环逻辑

1. **生成**：`docx_skill` + `pptx_skill` 按内容模型产出文档
2. **验证**：`validator` 执行 15 项检查（0-100 分）
3. **推送**：状态 + 产物 `git commit` + `git push` 到当前分支
4. **决策**：得分 ≥ `pass_score`（默认 100）→ `DONE` 自动停止；
   否则失败项写入 `status/issues.json`，下一轮针对性自修复

已收敛后重复运行会直接退出，不会重复迭代。
