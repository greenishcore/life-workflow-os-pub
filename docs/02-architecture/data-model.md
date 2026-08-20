# 统一数据模型（frontmatter schema）

> Phase 5 可视化看板的数据基础：所有想法/任务/记录统一用 frontmatter 描述，
> 使 Dataview、看板脚本、本地 HTML 看板能读同一份数据。

## 字段总表

| 字段 | 类型 | 取值/示例 | 用途 |
|------|------|-----------|------|
| `type` | string | `idea` / `task` / `daily` / `note` | 记录类型 |
| `id` | string | `2026-08-16-001` | 唯一 ID |
| `title` | string | 标题 | 展示名 |
| `created` | date | `2026-08-16` | 创建时间（时间线/热力图 X 轴） |
| `updated` | date | `2026-08-16` | 最近更新 |
| `status` | enum | `seed`/`sprout`/`doing`/`done`/`archived` | 想法状态机 |
| `priority` | enum | `high`/`medium`/`low` | 优先级 |
| `energy` | int | `0–10` | 精力投入（热力图/散点） |
| `progress` | int | `0–100` | 进度 |
| `tags` | list | `[idea, ai]` | 标签 |
| `thinking_notes` | list | 见下 | **思路注释（思维轨迹）** |
| `next_actions` | list | 待办 | 下一步 |
| `links` | list | `[["笔记A"]]` | 关联 |

## thinking_notes（思路注释）结构

```yaml
thinking_notes:
  - t: 2026-08-16
    note: 初始想法：为什么产生、想解决什么
  - t: 2026-08-17
    note: 补充/转折：受到什么影响、方向调整
```

> 这是区别于普通笔记的关键：记录「想法如何演进」，看板据此画出思维轨迹，复盘时能看到过程而非只有结论。

## 状态机

```
seed（种子）→ sprout（发芽）→ doing（推进中）→ done（完成）→ archived（归档）
```

## 想法最小示例

```markdown
---
type: idea
id: 2026-08-16-001
title: 搭建家庭影音库
created: 2026-08-16
status: doing
priority: high
energy: 8
progress: 60
tags: [life, workflow]
thinking_notes:
  - {t: 2026-08-16, note: 初始想法：把散落的记录/任务/平台打通}
  - {t: 2026-08-16, note: 调研后确定以 Markdown+Obsidian 为核心}
next_actions:
  - 落地可视化看板
---

# 搭建家庭影音库

正文（可选，叙述性内容）。
```

## 消费方

- **Obsidian 内**：Dataview 查询 frontmatter（`vault/Dashboard/看板.md`）。
- **本地 HTML 看板**：`scripts/dashboard.py` 解析 frontmatter → ECharts。
- **日志/复盘**：`scripts/log_run.py` 记录 agent 操作，与 idea 的 `id` 关联。
