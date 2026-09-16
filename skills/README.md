# Skills（已安装技能）

> 来源说明：`https://arena.ai/agent/01a0a821-3f3c-7bbe-bf99-6e6793c45d81` 需要登录授权，
> 沙箱内无法直接抓取其技能包；已在本地按等价能力实现为 Python 技能模块，
> 依赖安装进仓库内 `.venv`，与本地环境打通。

## 技能清单

| 技能 | 模块 | 入口函数 | 用途 |
| --- | --- | --- | --- |
| docx 生成 | `skills/docx_skill.py` | `build_docx(path, level, fixes, history, result)` | 按内容模型生成 Word 报告 |
| pptx 生成 | `skills/pptx_skill.py` | `build_pptx(path, level, fixes, history, result)` | 按内容模型生成 PPT 演示 |
| 验证评分 | `skills/validator.py` | `validate(root) -> (score, checks)` | 15 项检查，0-100 分 |
| 检查项定义 | `skills/checklist.py` | `CHECKS / KEYWORDS / PLACEHOLDER_MARKS` | 单一事实来源 |

`level` 表示内容完整度（1=初稿 / 2=修订 / 3=完整）；`fixes` 是上一轮验证失败项集合，
用于驱动自修复（例如上一轮 `docx_clean` 失败，下一轮自动去除占位文本）。

## 本地打通

- 依赖：`python-docx`、`python-pptx` → 已装入 `.venv`
  （`python3 -m venv .venv && .venv/bin/pip install -r pipeline/requirements.txt`）
- 调用入口：`pipeline/loop.py`（自循环编排器，负责串联技能 + git 推送）
- 运行：`.venv/bin/python pipeline/loop.py`
- 产物：`output/doc/report.docx`、`output/slides/deck.pptx`
- 状态：`status/loop_status.json`、`status/issues.json`、`status/REPORT.md`（每轮 push 到分支）
