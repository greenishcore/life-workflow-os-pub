# 工具映射（Tool Mapping）

> 把三份调研报告（`docs/01-research/`）的结论，映射到 `architecture.md` 的「五阶段闭环 + 分层」上，形成「能力 → 落地工具 → 关键要点」的对应表。这是整合逻辑化的产物。

## 0. 五阶段闭环 × 工具总览

| 阶段 | 目标 | 核心工具 | 关键产出 |
|------|------|----------|----------|
| ① 捕捉 Capture | 多平台信息收口到 Markdown | 快捷指令、osascript(JXA)、notes-exporter、Remindian、icalBuddy/vdirsyncer | `Inbox/*.md`、`Daily/*.md` |
| ② 整理 Organize | Markdown 化 + 分类 + 链接 + 格式互转 | Obsidian（Templater/Dataview/QuickAdd）、markitdown/pandoc/ocrmypdf | 结构化 vault + 转换缓存 |
| ③ 执行 Execute | 提示词重写 → agent 执行 → 留痕 | meta-prompt 脚本、prompts/ 目录、JSONL 日志 | 提示词文档 + 产出 + run-log |
| ④ 复盘 Review | 日志聚合 → 提炼 skills → 迭代 | jq/Python 聚合、复盘报告、skills 库 | 复盘报告 + 可复用 skill |
| ⑤ 归档 Archive | 版本化 + 自动推送 + release | git、obsidian-git、gh CLI、GitHub Actions | 私有仓库 + tag/release |

## 1. 捕捉层（Apple → Markdown）

| 数据源 | 落地工具 | 方向/性质 | 要点 |
|--------|----------|-----------|------|
| 移动闪念 | 快捷指令「运行 Shell 脚本」/「追加文本」 | 单向写入 vault | 最稳链路：`cat >> $vault/Inbox/$(date +%F).md` |
| Apple Notes | `notes-exporter`（storizzi） | 单向导出 MD | 处理图片附件；**不追求双向** |
| Apple Notes（一次性迁移） | Obsidian Importer（官方） | 单向导入 | 首次建库用 |
| Apple Reminders | **Remindian** | **双向** | Obsidian Tasks ↔ Reminders/Things3 |
| Apple Reminders（只读） | Apple Reminders 插件（urishiraval） | 只读 | JXA 读系统提醒 |
| Apple Calendar | `icalBuddy` / `vdirsyncer`+`khal` → ICS | 读/同步 | 导出 `.ics` 供 Obsidian 用 |
| 浏览器剪藏/网页 | markitdown `-p url` | 单向 | URL → Markdown |

**自动化调度**：`launchd`（定时）+ `fswatch`（实时监听）+ Hazel（图形化规则）。

## 2. 整理层（Obsidian 知识库）

| 关注点 | 工具 | 要点 |
|--------|------|------|
| 目录结构 | PARA + Inbox + Daily | Projects/Areas/Resources/Archive + Inbox/Daily |
| 每日笔记/模板 | Templater + Periodic Notes + Calendar | 可编程模板 + 日/周/月框架 |
| 快速捕获 | QuickAdd + Natural Language Dates | 热键捕获 + `@today` 自然语言日期 |
| 数据查询 | Dataview | frontmatter 当数据库查询 |
| 任务 | Tasks | `- [ ]` 全文查询/过滤/截止 |
| 日历视图 | ICS 插件 / Full Calendar | `.ics`/CalDAV → 每日笔记 / 全月视图 |
| 白板/导图 | Excalidraw / Canvas | 思维导图 + 双向链接 |

## 3. 转换层（格式互转固化 pipeline）

| 需求 | 工具 | 命令要点 |
|------|------|----------|
| 任意格式 → MD | `markitdown` | `markitdown in.pdf > out.md` |
| MD → PDF | `pandoc --pdf-engine=xelatex` | 中文加 `-V CJKmainfont` |
| MD → docx / docx → MD | `pandoc` | `-f docx -t gfm` |
| 扫描 PDF 加文本层 | `ocrmypdf` | `ocrmypdf --skip-text in.pdf out.pdf` |
| 扫描件 → 结构化 MD（保表格） | `zerox`（视觉模型） | 最贵，按需启用 |

**固化策略**：`raw/ → md/ → out/` 目录 + `sha256(输入)+转换器版本` 缓存键；`convert.sh` + `Makefile` 增量构建。

## 4. 执行与日志层（提示词 → agent → 日志）

| 环节 | 落地 | 要点 |
|------|------|------|
| 提示词重写 | meta-prompt 脚本 | 口语需求 → 五段式 Markdown（角色/目标/约束/输出格式/验收标准） |
| 提示词存放 | `prompts/00_inbox + 01_rewritten + 02_templates` | 原话与重写稿分开，纳入 git |
| agent 日志 | JSONL（`logs/<date>/<session_id>.jsonl`）+ Markdown run-log | 字段见 `templates/log-entry.md` |
| 复盘聚合 | `jq` / Python | 失败 TopN、耗时 TopN、重复 error |
| 现成 tracing（可选） | Langfuse（自托管） | 规模上来再迁 |

## 5. 可视化层（融合时间的看板）

| 维度 | 工具 | 展示 |
|------|------|------|
| 进度/优先级/状态 | Kanban | 卡片 + 注释 + 内链 |
| 时间/精力密度 | Heatmap Calendar | GitHub 风格热力图 |
| 想法演进 | Timeline / obsidian-timelive | 竖轴时间线 |
| 聚合统计 | Obsidian Charts / Charts View | 折线/柱状/饼图 |
| 文本时间线 | Mermaid timeline/gantt、markwhen | 原生渲染 |
| 思维轨迹 | obsidian-git Diff 历史 + Kanban 注释 | 「想法→推进→完成」版本演进 |
| 独立 HTML 看板 | gray-matter → JSON → ECharts/vis-timeline | 单文件 `index.html`，可发 GitHub Pages |

**统一数据源**：frontmatter 字段约定 `date / status / priority / energy / tags / progress / thinking_notes`，Dataview 做单一数据源，多视图分头渲染。

## 6. 归档层（GitHub）

| 动作 | 工具 | 要点 |
|------|------|------|
| 自动 commit+push | obsidian-git | 每 10 分钟，PAT 认证，忽略 workspace.json |
| 创建/管理仓库 | `gh` CLI | `gh repo create --private`、`gh release create` |
| 定时备份 | GitHub Actions `cron` | `actions/checkout` + commit + push |
| 里程碑归档 | tag + release | 语义化 `v0.1.0`，release notes 写阶段成果 |
| 隐私 | `.gitignore` + 私有仓库 | 排除 `.obsidian/workspace*.json`、`.trash/`、`.env`、token |

## 7. 分层视图（对应 architecture.md §5）

| 层 | 落地工具 |
|----|----------|
| 交互层 | Apple 应用 / 快捷指令 / Obsidian / 浏览器 / 看板 HTML |
| 数据层 | Markdown + frontmatter（`*.md`） |
| 逻辑层 | osascript/JXA、convert.sh、Makefile、meta-prompt 脚本、日志聚合脚本 |
| 归档层 | git + GitHub + Actions |

## 8. 关键取舍（整合后的决策）

1. **Apple Notes 不双向同步**：单向导出，避免依赖非公开接口。
2. **提醒事项才双向**：Remindian 是唯一可靠双向桥。
3. **日志自建 JSONL 优先**：轻量可控；Langfuse 留作规模化升级。
4. **看板组合自建**：无单一开箱即用方案，靠 frontmatter 统一字段 + 多插件/多库组合。
5. **转换用内容寻址缓存**：`sha256+版本` 命中即复用，最省算力。
