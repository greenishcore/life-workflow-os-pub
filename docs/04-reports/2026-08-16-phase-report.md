# 阶段性报告：生活工作流改造项目（第一期 · 检索与规划）

> 日期：2026-08-16
> 项目：`life-workflow-os/`
> 阶段：R1 检索调研 + R2 架构整合 + R3 分阶段规划

---

## 摘要

本报告完成了「生活工作流改造项目」的第一期工作：**先检索 → 再整合逻辑化 → 后规划**，产出了三份检索报告、一套整合架构、一张七阶段路线图，并把具体工具映射到每个环节。核心结论是：以**本地 Markdown + frontmatter 为唯一事实源、Obsidian 为知识库中枢、Git/GitHub 为版本归档、脚本与 agent 为自动化引擎**，搭建一个「捕捉 → 整理 → 执行 → 复盘 → 归档」的五阶段闭环。

---

## 一、检索结论（R1）

三路并行检索已核实真实可用的工具与链路，关键取舍如下：

### 1.1 Apple 生态 → Markdown

| 需求 | 结论 | 工具 |
|------|------|------|
| Apple Notes 导出 | **单向导出**，不追求双向（底层私有格式，无可靠双向） | [notes-exporter](https://github.com/storizzi/notes-exporter) / [Obsidian Importer](https://github.com/obsidianmd/obsidian-importer) |
| 提醒事项 | **双向同步**（唯一可靠双向桥） | [Remindian](https://github.com/Santofer/Remindian) |
| 日历 | 导出 `.ics`/CalDAV 进 Obsidian | [icalBuddy](https://github.com/peterwooley/icalBuddy) / [vdirsyncer](https://github.com/pimutils/vdirsyncer) / [ICS 插件](https://github.com/muness/obsidian-ics) / [Full Calendar](https://github.com/obsidian-community/obsidian-full-calendar) |
| 移动捕获 | 快捷指令「运行 Shell 脚本」直写 vault `Inbox/` | 快捷指令 + `/bin/zsh` |
| 自动化调度 | 定时/实时监听 | `launchd` + `fswatch` + Hazel |

### 1.2 格式互转固化（省算力）

- **收敛为一条 pipeline**：`任意格式 → Markdown（中间态）→ 目标格式`。
- 工具：[markitdown](https://github.com/microsoft/markitdown)（→MD）+ [pandoc](https://pandoc.org)（MD→PDF/docx）+ [ocrmypdf](https://github.com/ocrmypdf/OCRmyPDF)（扫描件）+ [zerox](https://github.com/getomni-ai/zerox)（保表格，按需）。
- **缓存键 = sha256(输入) + 转换器版本**，命中即复用，避免重复跑 OCR/LLM。

### 1.3 日志、提示词、归档、看板

| 能力 | 结论 |
|------|------|
| agent 日志 | 自建 **JSONL**（字段见 `templates/log-entry.md`）+ jq/Python 聚合复盘；规模化再迁 [Langfuse](https://langfuse.com) |
| 提示词重写 | meta-prompt 把口语需求转**五段式 Markdown**，存 `prompts/` 纳入 git |
| GitHub 归档 | [obsidian-git](https://github.com/Vinzent03/obsidian-git) 自动 push + `gh release` 打里程碑 + Actions 定时备份 |
| 融合时间看板 | **组合自建**：frontmatter 统一字段 + [Kanban](https://github.com/obsidian-community/obsidian-kanban) / [Heatmap Calendar](https://github.com/Richardsl/heatmap-calendar-obsidian) / [Timeline](https://github.com/George-debug/obsidian-timeline) / ECharts；「思维轨迹」用 Kanban 注释 + obsidian-git Diff 历史 |

完整细节见 `docs/01-research/`。

---

## 二、整合架构（R2）

详见 `docs/02-architecture/architecture.md` 与 `tool-mapping.md`，核心如下：

```
捕捉 Capture ─► 整理 Organize ─► 执行 Execute ─► 复盘 Review ─► 归档 Archive
   (Apple→MD)     (Obsidian)      (提示词→agent→日志)  (日志聚合→skills)  (git/GitHub)
                          ▲                                      │
                          └──────────── 本地 Markdown 事实源 ◄─────┘
```

**核心数据模型**——「想法」作为一等公民，携带五个维度：`时间 + 状态(seed→sprout→doing→done→archived) + 优先级 + 标签 + 思路注释(思维轨迹)`，这是融合时间看板的数据基础。

**分层**：交互层（Apple/Obsidian/浏览器）→ 数据层（Markdown+frontmatter）→ 逻辑层（脚本+agent）→ 归档层（git/GitHub）。

---

## 三、分阶段实施规划（R3）

详见 `docs/03-roadmap/roadmap.md`。依赖顺序与里程碑：

| Phase | 内容 | 里程碑 |
|-------|------|--------|
| **0 基础设施** | git 仓库 + 目录约定 + 模板 + `.gitignore` | M1 地基 |
| **1 捕捉层** | Apple 便签/日历/提醒 → Markdown | M2 数据打通 |
| **2 知识库** | Obsidian vault + 插件 + 想法状态机 | M2 |
| **3 转换层** | markitdown/pandoc/ocrmypdf pipeline + 缓存 | M3 自动化闭环 |
| **4 执行与日志** | 提示词重写 + agent JSONL 日志 | M3 |
| **5 可视化** | 融合时间看板（Kanban/Heatmap/Timeline） | M4 可视化+归档 |
| **6 归档** | obsidian-git + gh release + Actions | M4 |
| **7 演进** | 复盘 → 提炼 skills → 迭代 | M5 持续演进 |

---

## 四、本期已交付物

```
life-workflow-os/
├── README.md                              # 项目愿景 + 目录 + 设计原则
├── .gitignore                             # 隐私/缓存/产物排除
├── templates/
│   ├── daily-note.md                      # 每日笔记模板
│   ├── idea.md                            # 想法模板（含思路注释思维轨迹）
│   ├── log-entry.md                       # agent 日志 JSONL schema
│   └── prompt.md                          # 五段式提示词模板
└── docs/
    ├── 01-research/                       # 三份检索报告 + 汇总
    ├── 02-architecture/                   # architecture.md + tool-mapping.md
    ├── 03-roadmap/roadmap.md              # 七阶段路线图
    └── 04-reports/                        # 本报告
```

---

## 五、下一步（Phase 0 启动清单）

1. `git init` + 创建 GitHub **私有仓库**（`gh repo create --private`）。
2. 确认 vault 根目录与 PARA 目录（Inbox/Daily/Projects/Areas/Resources/Archive）。
3. 在 Obsidian 中安装核心插件：Templater、Dataview、Kanban、Tasks、QuickAdd、Calendar、Obsidian Git、Remindian、ICS/Full Calendar。
4. 把 `templates/` 接入 Templater，跑通第一条「想法 → 看板」链路。
5. 配置 obsidian-git 自动 commit+push，完成 M1 验收。

> 后续每完成一个 Phase，都会在本目录产出对应的阶段总结（复盘 + 下阶段调整），并打 tag/release 归档到 GitHub。
