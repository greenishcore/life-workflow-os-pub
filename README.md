# Life Workflow OS（生活工作流改造项目）

> 把「记录 → 思考 → 执行 → 复盘 → 归档」的个人生活工作流，改造成一个可复用、可版本化、可自动化的本地优先系统。

## 愿景

把散落在不同平台（Apple 便签/日历/提醒、PDF、Markdown、聊天记录、agent 会话）的信息，汇聚成一个**以本地 Markdown 为核心、以 Obsidian 为知识库、以 Git/GitHub 为版本归档、以脚本与 agent 为自动化引擎**的统一工作流。

## 核心能力（目标）

| 能力 | 说明 | 状态 |
|------|------|------|
| 文字记录与进度管理 | 每日想法/点子捕捉 + 思路注释 + 进度看板 | 📋 规划中 |
| 融合时间的可视化看板 | 把时间、优先级、标签、想法演进融合进同一看板 | 📋 规划中 |
| 多平台数据链路 | Apple 便签/日历/提醒 ↔ Markdown/Obsidian | 📋 规划中 |
| 本地知识库 | Obsidian vault + 社区插件最佳实践 | 📋 规划中 |
| 格式互转固化 | PDF/Markdown/Word 等互转的可复用 pipeline | 📋 规划中 |
| agent 操作日志 | 每次 agent 操作的成果与过程结构化记录，供复盘 | 📋 规划中 |
| 提示词重写工作流 | 交互前把自然语言重写/润色为提示词文档再执行 | 📋 规划中 |
| GitHub 版本归档 | 阶段性成果 commit/tag/release + 自动推送 | 📋 规划中 |

## 目录结构

```
life-workflow-os/
├── docs/
│   ├── 01-research/      # 检索调研报告（各领域）
│   ├── 02-architecture/  # 逻辑化整合架构
│   ├── 03-roadmap/       # 分阶段实施路线图
│   └── 04-reports/       # 阶段性报告输出
├── templates/            # 日记/想法/日志/提示词 模板
├── prompts/              # 重写后的提示词文档（纳入版本控制）
├── scripts/              # 自动化脚本（同步/转换/日志/看板生成）
├── logs/                 # agent 操作日志（结构化 JSONL + Markdown）
├── .github/workflows/    # GitHub Actions 自动化
└── README.md
```

## 设计原则

1. **本地优先（Local-first）**：数据以纯文本 Markdown 落盘，不锁死在某个 SaaS。
2. **可版本化**：一切文档与脚本纳入 Git，阶段性成果打 tag/release。
3. **可复盘**：agent 的每次操作都留痕（输入提示词、过程、产出、耗时、错误）。
4. **算力经济**：格式转换固化为可复用、可缓存的 pipeline，避免重复计算。
5. **先检索、再整合、后规划**：不拍脑袋，先调研真实可用的工具与链路。

## 快速开始

环境要求与安装步骤见 [SETUP.md](SETUP.md)。最小闭环：

```bash
# 1. 装依赖（格式转换 / 同步）
brew install pandoc ocrmypdf tesseract fswatch ical-buddy pipx && pipx install markitdown

# 2. 快速捕获一条想法
./scripts/capture.sh "突然想到的点子"

# 3. 格式转换（任意 → Markdown(缓存) → pdf/docx）
./scripts/convert.sh 输入.pdf --to pdf

# 4. 交互前重写提示词 + 执行后记日志
python3 scripts/rewrite_prompt.py "你的口语需求"
python3 scripts/log_run.py --objective "做了什么" --status success
```

## 仓库

- GitHub（私有）：https://github.com/greenishcore/life-workflow-os

## 状态

- [x] 项目骨架建立
- [x] 三路检索调研完成（`docs/01-research/`）
- [x] 架构整合文档完成（`docs/02-architecture/`）
- [x] 分阶段路线图完成（`docs/03-roadmap/roadmap.md`）
- [x] 阶段性报告输出（`docs/04-reports/2026-08-16-phase-report.md`）
- [x] Phase 0–3 脚本与配置落地（`scripts/`、`SETUP.md`、`.github/workflows/`）
- [x] 推送到 GitHub 私有仓库（`main` 分支）
- [x] Phase 5 可视化看板（`scripts/dashboard.py` → `vault/Dashboard/index.html` + Obsidian Dataview/Kanban）
- [x] notes-exporter 补装（`~/tools/notes-exporter`，v1.3.0 支持双向回写）
- [ ] Phase 6 归档自动化收尾 + Phase 7 复盘/技能演进 — 待下一阶段
