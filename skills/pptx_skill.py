# -*- coding: utf-8 -*-
"""pptx 生成技能：按内容模型 + 上轮验证失败项生成 PPT 演示文稿。

build_pptx(path, level=1, fixes=(), history=(), result=None)
"""
import os

from pptx import Presentation

from pipeline import content_spec as spec


def _bullets(slide, lines):
    tf = slide.placeholders[1].text_frame
    tf.clear()
    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.text = line


def _content_slide(prs, title, lines):
    s = prs.slides.add_slide(prs.slide_layouts[1])
    s.shapes.title.text = title
    _bullets(s, lines)
    return s


def _verification_bullets(result):
    if result:
        checks = result["checks"]
        passed = sum(1 for c in checks if c["passed"])
        lines = ["得分 %s/100 · %d/%d 项检查通过" % (result["score"], passed, len(checks))]
        if result["score"] >= 100:
            lines.append("全部检查项通过，结果收敛，循环终止")
        else:
            bad = [c["name"] for c in checks if not c["passed"]]
            lines.append("未通过项：" + "、".join(bad))
        lines.append("检查项定义：skills/checklist.py（15 项）")
        return lines
    return ["本轮验证结果记录于 status/REPORT.md", "15 项检查 · 满分 100 · 收敛即停止"]


def _history_bullets(history):
    if not history:
        return ["（首版文档，尚无历史迭代）"]
    return [
        "迭代 %s · %s/100 · 失败 %d 项 · %s · push:%s"
        % (h["iteration"], h["score"], len(h["failed"]), h["status"], h.get("push", "-"))
        for h in history
    ]


def _conclusion_bullets(result):
    if result and result["score"] >= 100:
        return [
            "全部验证项通过，自动循环收敛终止",
            "产物：output/doc/report.docx · output/slides/deck.pptx",
            "状态：status/ 已推送到分支，可全程追溯",
        ]
    if result:
        return [
            "得分 %s/100，下一轮继续自修复" % result["score"],
            "产物：output/doc/report.docx · output/slides/deck.pptx",
            "状态：status/ 持续推送到分支",
        ]
    return [
        "依据上一轮验证失败项自动修订",
        "本轮结果以 status/ 与分支提交记录为准",
    ]


def build_pptx(path, level=1, fixes=(), history=(), result=None):
    fixes = set(fixes)
    full = level >= 3 or bool(fixes & spec.PPTX_CONTENT_FIXES)
    meta = level >= 2 or "pptx_metadata" in fixes
    clean = level >= 2 or "pptx_clean" in fixes

    prs = Presentation()

    # 封面
    s = prs.slides.add_slide(prs.slide_layouts[0])
    s.shapes.title.text = spec.TITLE
    s.placeholders[1].text = spec.SUBTITLE

    if not full:
        # 初稿：仅 3 页，元数据缺失，含占位文本，等待自循环修复
        _content_slide(prs, "目标（初稿）", [
            "自动生成 docx / pptx 文档",
            "自验证：15 项检查，0-100 分",
            "状态推送至分支并持续自循环",
        ])
        _content_slide(prs, "流程（初稿）", [
            spec.PLACEHOLDER if not clean else "初稿：流程说明待自循环补齐",
        ])
    else:
        _content_slide(prs, "目标", [
            "docx / pptx 生成能力技能化，与本地虚拟环境打通",
            "生成 → 验证 → 推送 → 自修复，全程无人值守",
            "结果状态持久化并推送到分支，可全程追溯",
        ])
        _content_slide(prs, "技能与本地架构", [
            "skills/docx_skill.py —— Word 生成技能",
            "skills/pptx_skill.py —— PPT 生成技能",
            "skills/validator.py —— 验证评分技能（15 项检查）",
            "pipeline/loop.py —— 自循环编排器（入口）",
            "output/ + status/ —— 产物与状态目录",
        ])
        _content_slide(prs, "自循环流程", [
            "1. 生成：按内容模型产出 docx + pptx",
            "2. 验证：15 项检查，输出 0-100 分与失败项",
            "3. 推送：状态与产物 commit + push 到分支",
            "4. 决策：达标 DONE 停止；未达标带失败项进入下一轮",
        ])
        _content_slide(prs, "验证结果", _verification_bullets(result))
        _content_slide(prs, "迭代记录", _history_bullets(history))
        _content_slide(prs, "结论", _conclusion_bullets(result))

    if meta:
        cp = prs.core_properties
        cp.title = spec.TITLE
        cp.author = spec.AUTHOR
        cp.subject = spec.SUBTITLE

    os.makedirs(os.path.dirname(path), exist_ok=True)
    prs.save(path)
    return path
