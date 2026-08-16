# 架构总览（逻辑整合）

> 本文描述**概念框架与信息流闭环**，是后续所有工具选型与阶段规划的上位逻辑。
> 具体工具映射见同目录 `tool-mapping.md`（待检索结果补全）。

## 1. 一句话架构

**「捕捉 → 整理 → 执行 → 复盘 → 归档」五阶段闭环**，以本地 Markdown 为唯一事实源（single source of truth），以 Obsidian 为知识库中枢，以 Git/GitHub 为版本归档，以脚本 + agent 为自动化引擎。

```
          ┌──────────────────────────────────────────────────────────┐
          │                    本地 Markdown 事实源                    │
          │              （Obsidian vault = 知识库中枢）                 │
          └───────────────┬──────────────────────┬───────────────────┘
                          │                      │
        ┌─────────────────▼─────┐      ┌─────────▼───────────┐
        │ ① 捕捉 Capture         │      │ ④ 复盘 Review        │
        │ Apple便签/日历/提醒     │      │ 日志聚合→提炼skills   │
        │ 快捷指令/浏览器剪藏     │      │ 改进提示词与流程      │
        └─────────────────┬─────┘      └─────────▲───────────┘
                          │                      │
                          ▼                      │
        ┌─────────────────────┐      ┌───────────┴───────────┐
        │ ② 整理 Organize      │      │ ③ 执行 Execute         │
        │ Markdown化/分类/链接  │      │ 提示词重写→agent执行    │
        │ 格式互转(pipeline)   │      │ 结构化日志(成果+过程)    │
        └─────────────────────┘      └───────────────────────┘
                          │                      │
                          └──────────┬───────────┘
                                     ▼
                          ┌─────────────────────┐
                          │ ⑤ 归档 Archive       │
                          │ git commit/tag/release │
                          │ GitHub 私有仓库 + Actions │
                          └─────────────────────┘
```

## 2. 核心数据模型

### 2.1 想法 / 点子（Idea）
把「想法」作为一等公民，具备**时间 + 状态 + 优先级 + 标签 + 思路注释（思维轨迹）**五个维度，以支撑融合时间的可视化看板。

```yaml
type: idea
id: 2025-xx-xx-idea-001
created: 2025-xx-xx
updated: 2025-xx-xx
status: seed | sprout | doing | done | archived
priority: high | medium | low
tags: [..]
thinking_notes:            # ← 思路注释：思维轨迹，带时间戳的增量记录
  - {t: 2025-xx-xx, note: "初始想法…"}
  - {t: 2025-xx-xx, note: "补充/转折…"}
next_actions: []
links: []
```

- **状态机**：`seed（种子）→ sprout（发芽）→ doing（推进中）→ done（完成）→ archived（归档）`
- **思路注释**是区别于普通笔记的关键：它记录「这个想法为什么产生、如何演进、被什么影响」，复盘时能看到完整思维轨迹而非只有结论。

### 2.2 记录（Note / Daily）
- 每日笔记：当日主线 + 想法 Inbox + 进度 + 复盘。
- 普通笔记：永久笔记、文献笔记、会议记录等（可套用 Zettelkasten 或 PARA）。

### 2.3 任务（Task）
- 从想法/笔记中拆出的可执行项，可关联日历/提醒。
- 状态：`todo → doing → done`，附截止时间、优先级。

### 2.4 Agent 运行记录（Run Log）
- 每次 agent 操作的完整留痕：输入提示词、工具、过程摘要、产出、错误、耗时、模型、复盘备注。
- 结构化（JSONL）供程序聚合，同时生成可读 Markdown 供人浏览。

## 3. 信息流拓扑

### 3.1 输入侧（多平台 → 本地 Markdown）
| 来源 | 方向 | 落点 |
|------|------|------|
| Apple 便签 | → Markdown | `inbox/` 或指定目录 |
| Apple 日历 | → ICS/Markdown | 可被 Obsidian 查询 |
| Apple 提醒事项 | → Markdown 任务 | `tasks/` |
| PDF / Word / 网页 | → Markdown（pipeline） | `inbox/` 或知识库 |
| 浏览器剪藏 | → Markdown | `inbox/` |
| 语音/随手记 | → Markdown | `inbox/` |

### 3.2 中枢侧（Obsidian 知识库）
- 统一收口为 Markdown，按约定目录组织、互相 `[[链接]]`。
- 用社区插件做每日笔记、看板、时间线、查询聚合。

### 3.3 执行侧（提示词 → agent → 日志）
```
自然语言需求 ──(重写润色)──> prompts/xxx.md ──(agent 读取执行)──> 产出文件
                                                    └──> logs/run-log.jsonl（成果+过程）
```
- **提示词文档**纳入版本控制，可追溯每次执行到底让 agent 做了什么。
- **日志**沉淀经验，复盘时提炼出可复用的 skills。

### 3.4 输出侧（本地 → GitHub 归档）
- 阶段性成果 `commit`，里程碑打 `tag`，重要版本发 `release`。
- GitHub Actions 可定时自动同步、备份、生成文档。

## 4. 算力经济层（格式互转固化）

- 所有「格式转换」收敛到唯一 pipeline：**任意格式 → Markdown（中间态）→ 目标格式**。
- 已转换结果**缓存**，相同输入+参数直接命中缓存，不重复调用大模型/重型工具。
- 转换路径写成脚本固化，可复现、可版本化。

## 5. 分层视图

| 层 | 职责 | 主要载体 |
|----|------|----------|
| 交互层 | 捕捉、浏览、看板 | Apple 应用 / 快捷指令 / Obsidian / 浏览器 |
| 数据层 | 唯一事实源 | Markdown 文件 + frontmatter |
| 逻辑层 | 重写、转换、同步、日志 | 脚本（shell/python/node）+ agent |
| 归档层 | 版本控制与备份 | Git + GitHub + Actions |

## 6. 待检索补全项（TODO）

- [ ] Apple → Markdown 的具体工具与脚本
- [ ] Obsidian 插件清单与目录约定
- [ ] PDF/Markdown 转换 pipeline 的工具选型
- [ ] agent 日志的现成方案 vs 自研轻量方案
- [ ] 提示词重写的 meta-prompt 模板
- [ ] GitHub Actions 自动化方案
- [ ] 融合时间的看板技术选型
