---
skill_id: convert-document
name: 文档格式互转 pipeline
status: verified
created: 2026-08-16
tags: [conversion, pandoc, markitdown]
---

# 文档格式互转 pipeline

## 触发条件（何时用）
- 需要把 PDF / docx / pptx / html 等转成 Markdown，或把 Markdown 转成 PDF / docx / html。

## 依赖
- 脚本：`scripts/convert.sh`（封装 markitdown + pandoc + Chrome headless）
- 工具：`markitdown`（含 pdf/docx/pptx/xlsx/xls extras）、`pandoc`、`ocrmypdf`（扫描件）

## 目标
- 一条命令完成「任意格式 → Markdown（缓存）→ 目标格式」，重复转换命中缓存零成本。

## 步骤
1. 确认输入文件与目标格式。
2. 运行 `scripts/convert.sh <输入> --to <pdf|docx|html|md> -o <输出>`。
3. 扫描件先 `ocrmypdf --skip-text in.pdf out.pdf` 加文本层。
4. 检查输出；如需保表格的复杂扫描件，改用 `zerox`（视觉模型，按需）。

## 脚本
```bash
./scripts/convert.sh 输入.pdf --to pdf          # PDF 转 PDF（规范化）
./scripts/convert.sh 输入.docx --to md          # docx → Markdown
./scripts/convert.sh 输入.md --to pdf -o 输出.pdf # Markdown → PDF
```

## 验收标准
- [x] md→html / md→docx / md→pdf / docx→md / pdf→md 均已实测通过
- [x] 二次转换命中 sha256 缓存（`[cache-hit]`）
- [x] 中文与加粗/列表内容无损

## 注意 / 踩过的坑
- `pandoc` 不读 PDF（PDF 是输出-only）；PDF→Markdown 走 markitdown 或 OCR。
- 生成 PDF 无 xelatex 时自动回退 Chrome headless（本机已回退可用）。
- markitdown 需 `[docx,pptx,xlsx,pdf]` extras 才能转 Office 格式（已装）。

## 效果评分
- 2026-08-16 | 5 | 端到端验证通过，缓存与中文保真正常
