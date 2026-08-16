# 调研汇总（R1）

> 三路并行检索的合并结论索引。完整正文见同目录三份报告。

## 报告清单

| 文件 | 领域 | 一句话结论 |
|------|------|------------|
| `research-01-apple-obsidian.md` | Apple 生态 + Obsidian | Notes 单向导出、Reminders 双向（Remindian）、日历走 ICS/Full Calendar；Obsidian 用 PARA + Templater/Dataview/Tasks/QuickAdd |
| `research-02-format-log-prompt.md` | 格式互转 + 日志 + 提示词 | markitdown/pandoc/ocrmypdf 固化 pipeline + sha256 缓存；JSONL 日志 + jq 复盘；meta-prompt 重写为五段式提示词 |
| `research-03-github-dashboard.md` | GitHub 归档 + 可视化看板 | obsidian-git 自动推送 + gh release 归档；frontmatter 统一字段 + Kanban/Heatmap/Timeline/ECharts 组合看板 |

## 跨领域关键结论（整合后）

1. **数据核心是 Markdown + frontmatter**：所有平台、所有格式最终收口为带 frontmatter 的 Markdown，作为唯一事实源。
2. **Apple Notes 不双向、Reminders 才双向**：Notes 单向导出（notes-exporter / Obsidian Importer），提醒事项用 Remindian 双向。
3. **格式互转收敛为一条 pipeline**：任意格式 → Markdown（中间态）→ 目标格式，`sha256+版本` 缓存省算力。
4. **日志自建 JSONL 优先**：记录「提示词 → 工具/技能 → 产出 → 错误 → 耗时 → 成本」，jq/Python 聚合复盘，规模化再迁 Langfuse。
5. **提示词先重写再执行**：meta-prompt 把口语需求转为五段式 Markdown，存入 `prompts/` 纳入 git。
6. **看板组合自建**：无开箱即用融合方案，靠统一 frontmatter 字段 + Kanban/Heatmap/Timeline/Charts/ECharts 组合。
7. **归档靠 git 全家桶**：obsidian-git 自动 commit+push 私有仓库，gh release 打里程碑，Actions 定时备份。

## 后续衔接

- 架构整合 → `../02-architecture/architecture.md` + `tool-mapping.md`
- 实施顺序 → `../03-roadmap/roadmap.md`
- 阶段报告 → `../04-reports/`
