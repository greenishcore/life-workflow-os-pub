# Life Workflow OS（生活工作流）

> 把散落在便签、日历、提醒、PDF、聊天记录、agent 会话里的信息，
> 收成一个**本地优先、可版本化、可自动化**的个人系统 —— 现在它是一个可双击打开的桌面应用。

闭环：**捕捉 → 整理 → 执行 → 复盘 → 归档**，数据始终是你自己的本地 Markdown。

![闭环](assets/icon-1024.png)

## 快速开始

```bash
# 1) 打包成 macOS 应用（生成 dist/Life Workflow OS.app）
bash tools/build_app.sh

# 2) 双击运行，或：
open "dist/Life Workflow OS.app"

# 3) 想放进启动台
ln -sfn "$PWD/dist/Life Workflow OS.app" /Applications/
```

不想打包也可以直接跑：

```bash
./bin/lifeos            # 图形界面
./bin/lifeos doctor     # 依赖与配置体检
```

**依赖**：macOS + Python 3.10+ + `PyQt5` + `PyYAML`。
其余（pandoc / markitdown / ocrmypdf / gh）都是**可选**的，缺了只影响对应功能，
应用内「设置 → 依赖体检」会告诉你缺什么、装了有什么用。

```bash
pip3 install PyQt5 pyyaml                     # 必需
brew install pandoc gh && pipx install markitdown   # 按需
```

## 应用能做什么

界面按五阶段闭环组织，一屏一件事：

| 页面 | 作用 |
|------|------|
| **看板** | 融合时间轴（X=时间 · Y=精力 · 点径=优先级 · 颜色=状态 · 横线=思维轨迹）、活跃热力图、状态分布、标签 TopN、最近思维轨迹 |
| **快速捕获** | ⌘↩ 一键落到 Inbox；从 Apple 提醒/日历/备忘录导入；把随手记**一键提升为想法** |
| **想法库** | 想法的完整读写：状态机、优先级、精力、进度、标签、**思路注释时间轴**、下一步、正文 |
| **格式转换** | 任意格式 → Markdown（带缓存）→ PDF/Word/HTML，支持拖拽，命中缓存会明确告诉你 |
| **提示词工作台** | 把口语需求重写成五段式提示词文档并版本化留档（可接 LLM） |
| **运行日志与复盘** | 记录每次 agent 操作，聚合成成功率/工具 TopN/错误 TopN，一键生成周复盘 |
| **版本归档** | git 状态、提交推送、里程碑 tag + GitHub release、提交历史 |
| **设置** | vault 位置、明暗主题、Apple 默认值、LLM 配置、依赖体检 |

想法是一等公民，带五个维度：**时间 + 状态 + 优先级 + 标签 + 思路注释（思维轨迹）**。
状态机：`seed 种子 → sprout 发芽 → doing 推进中 → done 完成 → archived 归档`。

**思路注释**是这套系统区别于普通笔记的地方：它记录「为什么会想到它、想法怎么变的」，
复盘时看到的是过程，不只是结论。看板上每条想法因此是一条**生命线**而非一个孤点。

## 命令行

GUI 与命令行共用同一套核心逻辑（`lifeos/`），改哪边都是同一份数据：

```bash
./bin/lifeos capture "突然想到的点子"        # 捕获
./bin/lifeos convert 论文.pdf --to docx      # 转换（自动缓存）
./bin/lifeos prompt "帮我做个看板" [--llm]   # 提示词重写
./bin/lifeos log --objective "转换论文" --status success --tools markitdown
./bin/lifeos review --since 2026-08-12       # 周复盘
./bin/lifeos dashboard                       # 生成自包含 HTML 看板
./bin/lifeos sync -m "阶段成果"               # 提交并推送
./bin/lifeos release v0.3.0 "本阶段成果"      # 里程碑
./bin/lifeos doctor                          # 体检
```

`scripts/` 下的老命令（`capture.sh` / `convert.sh` / `dashboard.py` / …）全部保留，
参数与输出不变，内部转调上面这套 —— 既有的 GitHub Actions、launchd、Makefile 无需改动。

## 目录结构

```
life-workflow-os/
├── lifeos/                # ★ 核心包（UI 无关）
│   ├── config.py          #   单一配置源
│   ├── models.py          #   Item / ThinkingNote / RunLog / 状态机
│   ├── frontmatter.py     #   确定性 YAML 序列化
│   ├── repository.py      #   vault 读写（原子写 + 回收站）
│   ├── stats.py           #   看板聚合
│   ├── html_dashboard.py  #   自包含 HTML 看板（内联 SVG，零外部依赖）
│   ├── cli.py             #   命令行入口
│   ├── services/          #   convert / prompts / runlog / review / apple / archive
│   └── gui/               #   ★ PyQt5 桌面应用（theme / charts / widgets / pages）
├── vault/                 # 你的知识库（Markdown 唯一事实源）
├── scripts/               # 兼容壳 + AppleScript
├── tools/                 # 打包 / 图标 / GUI 冒烟测试
├── tests/                 # 单元测试（44 项）
├── docs/                  # 调研 / 架构 / 路线图 / 阶段报告
└── bin/lifeos             # 启动器
```

## 设计原则

1. **本地优先** —— 数据是纯文本 Markdown，不锁死在任何 SaaS，也不锁死在本应用。
2. **可版本化** —— 一切纳入 git；序列化确定性，只读浏览不产生 diff。
3. **可复盘** —— agent 每次操作都留痕，日志能聚合成可执行的改进项。
4. **算力经济** —— 格式转换按 `sha256(输入)+转换器版本` 缓存，不重复烧算力。
5. **降级而非崩溃** —— 缺依赖只让对应功能降级，并明确告诉你缺什么。

## 与 Obsidian 的关系

vault 就是标准的 Obsidian 库，格式完全兼容，两边可以同时用。
但**不装 Obsidian 也能用全部功能** —— 看板、编辑、查询、任务现在都由应用自己提供。
插件清单见 [SETUP.md](SETUP.md)，现在是「推荐」而非「必装」。

## 开发

```bash
python3 -m unittest discover -s tests    # 核心层测试
python3 tools/smoke_gui.py               # GUI 离屏冒烟（8 页 × 明暗双主题）
python3 tools/make_icon.py               # 重新生成图标
bash tools/build_app.sh                  # 重新打包 .app
```

架构说明见 [docs/02-architecture/architecture-v2.md](docs/02-architecture/architecture-v2.md)。

## 仓库

GitHub（私有）：https://github.com/greenishcore/life-workflow-os

## 状态

- [x] Phase 0–3：骨架 / 捕捉 / 知识库 / 格式转换
- [x] Phase 4–5：提示词与日志 / 融合时间看板
- [x] Phase 6–7：GitHub 归档自动化 / 复盘与技能库
- [x] **Phase 8：重构为分层架构，交付桌面应用**（本次）
- [ ] 持续迭代：由日常使用驱动
