# -*- coding: utf-8 -*-
"""验证检查项定义：validator 评分与 docx/pptx 渲染共用的单一事实来源。

满分 100 = 各检查项权重之和。
"""

CHECKS = [
    # ---- docx (60) ----
    {"id": "docx_exists",     "weight": 8,  "name": "docx 存在",     "desc": "output/doc/report.docx 存在且非空"},
    {"id": "docx_opens",      "weight": 8,  "name": "docx 可打开",   "desc": "python-docx 能正常解析文档"},
    {"id": "docx_paragraphs", "weight": 6,  "name": "docx 段落数量", "desc": "非空段落 >= 18"},
    {"id": "docx_headings",   "weight": 6,  "name": "docx 结构完整", "desc": "标题/章节数 >= 5"},
    {"id": "docx_length",     "weight": 8,  "name": "docx 内容量",   "desc": "全文字符数 >= 800"},
    {"id": "docx_keywords",   "weight": 8,  "name": "docx 关键内容", "desc": "包含 摘要/目标/流程/验证/迭代/流水线 全部关键词"},
    {"id": "docx_metadata",   "weight": 6,  "name": "docx 元数据",   "desc": "标题与作者元数据已填写"},
    {"id": "docx_clean",      "weight": 10, "name": "docx 无占位符", "desc": "不含禁止残留标记（清单见 PLACEHOLDER_MARKS）"},
    # ---- pptx (35) ----
    {"id": "pptx_exists",  "weight": 5,  "name": "pptx 存在",     "desc": "output/slides/deck.pptx 存在且非空"},
    {"id": "pptx_opens",   "weight": 5,  "name": "pptx 可打开",   "desc": "python-pptx 能正常解析演示文稿"},
    {"id": "pptx_slides",  "weight": 10, "name": "pptx 幻灯片数", "desc": "幻灯片 >= 6 页"},
    {"id": "pptx_title",   "weight": 4,  "name": "pptx 封面",     "desc": "第 1 页为含标题的封面页"},
    {"id": "pptx_metadata","weight": 4,  "name": "pptx 元数据",   "desc": "标题与作者元数据已填写"},
    {"id": "pptx_clean",   "weight": 7,  "name": "pptx 无占位符", "desc": "不含禁止残留标记（清单见 PLACEHOLDER_MARKS）"},
    # ---- 状态 (5) ----
    {"id": "status_written", "weight": 5, "name": "状态文件", "desc": "status/loop_status.json 存在、可解析且含迭代/得分字段"},
]

KEYWORDS = ["摘要", "目标", "流程", "验证", "迭代", "流水线"]
PLACEHOLDER_MARKS = ["TODO", "TBD", "FIXME", "占位", "xxx", "XXX"]

MIN_PARAGRAPHS = 18
MIN_HEADINGS = 5
MIN_CHARS = 800
MIN_SLIDES = 6

assert sum(c["weight"] for c in CHECKS) == 100, "检查项权重之和必须为 100"
