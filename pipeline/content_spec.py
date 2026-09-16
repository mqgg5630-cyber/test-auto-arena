# -*- coding: utf-8 -*-
"""内容模型：docx/pptx 生成技能的单一内容来源（Single Source of Truth）。"""

TITLE = "自动循环流水线运行报告"
SUBTITLE = "Auto-Loop Pipeline · docx + pptx 自动生成与自验证"
AUTHOR = "arena-agent"

# 初稿中故意保留的占位文本，会被验证项 docx_clean / pptx_clean 拦截，驱动自修复
PLACEHOLDER = "TODO: 待补充"
PLACEHOLDER_CLEAN = "（初稿：本节待自循环补齐）"

SECTIONS = [
    {
        "key": "summary",
        "heading": "摘要",
        "body": [
            "本报告由自动循环流水线（self-loop pipeline）自动生成，用于验证「技能安装 → 本地打通 → 自循环生成 → 状态推送 → 收敛判定」的完整闭环。",
            "流水线每轮迭代执行四步：调用 docx/pptx 生成技能产出文档；调用验证技能对产物做完整性与质量评分（满分 100）；将本轮状态提交并推送到分支；根据验证失败项在下一轮自动修复。",
            "当验证得分达到收敛阈值时，流水线判定结果收敛并自动停止；否则在最大迭代次数内持续自循环。",
            "报告中的迭代记录与验证明细均取自流水线真实运行数据，而非静态文案。",
        ],
    },
    {
        "key": "goal",
        "heading": "目标",
        "body": [
            "目标一：将 docx 与 pptx 生成能力作为可复用技能安装到本地仓库，与 Python 虚拟环境打通，可被任意脚本直接调用。",
            "目标二：实现无人值守的自循环任务——生成、验证、修复、推送全部自动完成，无需人工干预。",
            "目标三：每轮迭代的结果状态（得分、失败项、推送结果）以 JSON 与 Markdown 持久化到 status/ 目录，并随提交推送到分支，形成可追溯的审计记录。",
            "目标四：收敛即停止——所有验证项通过时自动终止循环，避免无意义重复。",
        ],
    },
    {
        "key": "pipeline",
        "heading": "流程说明",
        "body": [
            "步骤 1 · 生成：skills/docx_skill.py 与 skills/pptx_skill.py 依据 pipeline/content_spec.py 的内容模型，产出 Word 报告与 PPT 演示文稿。",
            "步骤 2 · 验证：skills/validator.py 执行 15 项检查（存在性、可打开性、段落/幻灯片数量、关键内容、元数据、残留文本、状态文件），输出 0-100 分与失败项清单。",
            "步骤 3 · 推送：pipeline/loop.py 将 status/loop_status.json、status/REPORT.md 与本轮产物 git add、commit 并 push 到当前分支。",
            "步骤 4 · 决策：得分达到阈值则标记 DONE 并结束；否则把失败项写入 status/issues.json，下一轮生成时针对性修复，直至收敛或达到最大迭代次数。",
            "自修复的关键：验证失败项直接成为下一轮生成的输入（fixes 集合），循环因此具备定向改进能力，而非简单重试。",
            "产物与状态位置：output/doc/report.docx、output/slides/deck.pptx、status/loop_status.json、status/REPORT.md。",
        ],
    },
    {"key": "validation", "heading": "验证清单", "body": []},
    {"key": "iterations", "heading": "迭代记录", "body": []},
    {"key": "conclusion", "heading": "结论", "body": []},
]

# 触发「内容补全」的修复项：上一轮这些检查失败时，下一轮直接生成完整内容
DOCX_CONTENT_FIXES = {"docx_paragraphs", "docx_headings", "docx_length", "docx_keywords"}
PPTX_CONTENT_FIXES = {"pptx_slides", "pptx_title"}
