# 分阶段实施路线图（Roadmap）

> 阶段骨架基于「先基础设施 → 再打通数据 → 再自动化与可视化 → 最后迭代演进」的依赖顺序。
> 每个阶段的**具体工具选型已回填到** `../02-architecture/tool-mapping.md`（检索整合产物），本文保留阶段目标与验收标准。

## 依赖关系总览

```
Phase 0 基础设施 ──► Phase 1 捕捉 ──► Phase 2 知识库 ──► Phase 3 格式转换
                                                              │
Phase 7 演进 ◄── Phase 6 归档 ◄── Phase 5 可视化 ◄── Phase 4 执行与日志
                                                              │
                                                    Phase 8 产品化（软件形态）
```

## Phase 0 — 基础设施与版本控制

**目标**：建立可版本化、可复用的项目地基。
- [ ] 初始化 git 仓库 + GitHub 私有仓库
- [ ] 确立目录约定（inbox/tasks/notes/projects/logs/prompts）
- [ ] 落地模板（日记 / 想法 / 日志 / 提示词）与 `.gitignore`
- [ ] 配置 git 身份与 `gh` CLI 认证

**交付物**：可 `git push` 的空仓库 + 目录 + 模板。
**验收**：`git commit && git push` 全链路跑通。

## Phase 1 — 捕捉层：多平台 → Markdown

**目标**：把 Apple 便签/日历/提醒、PDF、剪藏等信息统一收口到本地 Markdown。
- [ ] Apple 便签 → Markdown 导出脚本（AppleScript/JXA 或第三方工具）
- [ ] 日历 → ICS 导出 + 提醒 → Markdown 任务
- [ ] 输入统一落点 `inbox/`，附 frontmatter（来源、时间）

**交付物**：`scripts/sync-apple.*` 系列脚本。
**验收**：一键把当日便签/日历/提醒同步为 Markdown。

## Phase 2 — 知识库层：Obsidian

**目标**：建立本地优先的知识库中枢。
- [ ] 创建 Obsidian vault（= 本仓库的笔记目录）
- [ ] 安装并配置核心插件（每日笔记 / 模板 / 查询 / 看板 / 时间线）
- [ ] 建立想法状态机与 `[[链接]]` 约定

**交付物**：可用的 Obsidian vault 配置。
**验收**：新想法能按模板落盘、被查询、被看板展示。

## Phase 3 — 转换层：格式互转固化

**目标**：PDF/Markdown/Word 等互转固化为可复用、可缓存的 pipeline。
- [ ] 选型转换工具（pandoc / markitdown / OCR）
- [ ] 封装「任意格式 → Markdown → 目标格式」脚本
- [ ] 结果缓存，避免重复计算

**交付物**：`scripts/convert.*` + 缓存目录约定。
**验收**：同一文件二次转换命中缓存、秒级返回。

## Phase 4 — 执行与日志层：提示词重写 + agent 日志

**目标**：让每次 agent 交互「先重写提示词、再执行、再留痕」。
- [ ] 提示词重写 meta-prompt 模板
- [ ] 提示词文档落盘 `prompts/` 并纳入 git
- [ ] agent 操作日志结构（JSONL + Markdown），记录成果与过程

**交付物**：`templates/prompt.md` 流程 + `scripts/log.*` 记录器。
**验收**：任意一次 agent 交互可追溯「提示词 → 过程 → 产出 → 复盘」。

## Phase 5 — 可视化层：融合时间的看板

**目标**：把时间、优先级、标签、想法演进融合进新颖看板。
- [x] 选型看板/时间线技术（Obsidian 插件 或 本地 HTML）→ ECharts + Dataview/Kanban
- [x] 从 Markdown/JSON 数据源生成看板 → `scripts/dashboard.py`（解析 frontmatter）
- [x] 展示「想法时间线 + 思路注释轨迹 + 进度」→ 日历热力图 + 状态分布 + 融合散点 + 思路注释清单

**交付物**：`scripts/dashboard.py` → `vault/Dashboard/index.html`（本地 HTML）+ `vault/Dashboard/看板.md`（Obsidian Dataview/Kanban）。
**验收**：看板能回答「这个想法何时产生、如何演进、现在到哪一步」。（已用 3 条样例数据验证）

## Phase 6 — 归档层：GitHub 版本归档与自动化

**目标**：阶段性成果自动版本化 + 归档。
- [x] Obsidian Git / 定时脚本自动 commit + push → `scripts/sync.sh` + obsidian-git 插件（见 SETUP.md）
- [x] 里程碑 tag + release 约定 → `scripts/release.sh`，已发布 v0.1.0
- [x] GitHub Actions：定时备份、生成文档、归档 → `vault-backup.yml` + `generate-dashboard.yml`

**交付物**：`scripts/sync.sh`、`scripts/release.sh`、`.github/workflows/*.yml`。
**验收**：笔记/文档改动自动进入版本历史，里程碑可回溯。（v0.1.0 已发布）

## Phase 7 — 演进层：skills 持续完善

**目标**：把「复盘 → 提炼 → 迭代」变成常态机制。
- [x] 从 run-log 聚合经验，识别可复用的 skills → `scripts/weekly_review.py`
- [x] 周期性复盘（每周/每月）产出改进项 → `templates/weekly-review.md`
- [x] 提示词库与 skills 库版本化演进 → `skills/`（README + 模板 + convert-document 示例）

**交付物**：`scripts/weekly_review.py` + `skills/` 库 + 周复盘模板。
**验收**：每次迭代都让「提示词质量」与「执行可复现性」可度量提升。（机制已就绪，由日常使用驱动）

## Phase 8 — 产品化：从脚本集合到桌面应用

**目标**：把已跑通的能力收敛成一个可交付、可长期使用的软件。
- [x] 抽出 UI 无关的核心包 `lifeos/`（配置/模型/序列化/仓库/服务/统计）
- [x] frontmatter 确定性序列化：只读不产生 diff、二次保存稳定、特殊字符往返安全
- [x] PyQt5 桌面应用：8 个页面按五阶段闭环组织，明暗双主题
- [x] 看板从只读变可写：想法五维度全部可编辑，思路注释可增删
- [x] 图表改原生绘制，去掉 ECharts CDN 依赖（离线可用）
- [x] 补上 Inbox → 想法 的断口（一键提升）
- [x] 老命令全部保留为兼容壳，CI/launchd/Makefile 零改动
- [x] 打包为 macOS `.app`（图标 + 自动化权限声明）
- [x] 测试：核心层 44 项单测 + GUI 离屏冒烟

**交付物**：`lifeos/` 包、`bin/lifeos` 启动器、`dist/Life Workflow OS.app`、
`tests/`、`tools/`、`docs/02-architecture/architecture-v2.md`。
**验收**：不装 Obsidian、断网状态下，能完成「捕捉 → 建为想法 → 编辑思路注释 →
在看板上看到轨迹 → 记录一次运行 → 生成周复盘 → 提交归档」的完整闭环。（已验证）

---

## 里程碑（Milestone）建议

| 里程碑 | 覆盖阶段 | 标志 |
|--------|----------|------|
| M1 地基 | Phase 0 | 仓库+模板跑通 |
| M2 数据打通 | Phase 1–2 | Apple 数据进 Obsidian |
| M3 自动化闭环 | Phase 3–4 | 转换+提示词+日志闭环 |
| M4 可视化+归档 | Phase 5–6 | 看板+GitHub 自动归档 |
| M5 持续演进 | Phase 7 | 复盘驱动的 skills 迭代 |
| M6 产品化 | Phase 8 | 分层重构 + 可双击运行的桌面应用 |
