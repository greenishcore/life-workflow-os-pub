# 安装与配置指南（Phase 0–2 落地）

> 从零把本仓库跑起来，打通「捕捉 → 知识库 → 转换 → 日志 → 归档」的最小闭环。

## 0. 前置

- macOS（本机已就绪：git / gh / python3 / node / brew / osascript）
- 安装 [Obsidian](https://obsidian.md/)
- 依赖（按需，见 `scripts/README.md`）：
  ```bash
  brew install pandoc fswatch ical-buddy
  brew install ocrmypdf tesseract            # 扫描件 OCR 才需要
  pipx install markitdown                    # 或 pip install 'markitdown[all]'
  pipx install notes-exporter                # Apple Notes 导出才需要
  ```

## 1. 把 vault 目录作为 Obsidian 库打开

Obsidian → 「打开文件夹作为库」→ 选择本仓库的 `vault/` 目录。
（若你想把 vault 放到别处，见文末「vault 位置」说明。）

## 2. 安装社区插件

设置 → 第三方插件 → 关闭安全模式 → 浏览社区插件，安装并启用：

| 插件 | 用途 |
|------|------|
| Templater | 用 `vault/Templates/` 做可编程模板 |
| Dataview | frontmatter 当数据库查询，是看板数据源 |
| Kanban | 进度/优先级/状态看板 |
| Tasks | `- [ ]` 全文任务查询 |
| QuickAdd | 热键一键捕获到 Inbox |
| Calendar + Periodic Notes | 每日/周/月笔记 |
| Obsidian Git | 自动 commit+push 版本归档 |
| Remindian | Apple 提醒事项双向同步 |
| ICS 或 Full Calendar | 日历导入 |
| Excalidraw | 思维导图/白板 |
| Heatmap Calendar + Timeline | 融合时间的可视化（Phase 5） |

## 3. 配置 Templater

Templater 设置 → 模板文件夹设为 `vault/Templates`。
新建笔记时用 `idea.md` / `daily-note.md` 模板。

## 4. 配置 Obsidian Git（归档）

- 设置 → Obsidian Git → 开启 **Auto backup**，commit interval 建议 10 分钟；
- 勾选 **Push on backup**、**Pull before push**；
- 认证用 **Personal Access Token (PAT)** 或系统 git 凭据。

## 5. 配置 Remindian（提醒双向）

按 Remindian README 授权后，Obsidian Tasks ↔ Apple Reminders 双向同步：
https://github.com/Santofer/Remindian

## 6. 跑通同步脚本（首次）

```bash
cd life-workflow-os
chmod +x scripts/*.sh scripts/*.py

./scripts/capture.sh "测试：我的第一条想法"          # 快速捕获
./scripts/reminders2obsidian.sh 提醒事项             # 提醒 → Daily
./scripts/calendar2md.sh 个人 7                      # 日历 → Daily
./scripts/convert.sh 某个.pdf --to pdf               # 转换（需装依赖）
python3 scripts/rewrite_prompt.py "帮我做个看板"     # 提示词重写（脚手架）
python3 scripts/log_run.py --objective "冒烟测试" --status success  # 记一条日志
```

首次运行 Apple 脚本会弹「自动化」权限，允许即可。

## 7. 定时同步（可选）

```bash
cp scripts/launchd/com.me.reminders2obsidian.plist ~/Library/LaunchAgents/
# 改 plist 内脚本路径后：
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.me.reminders2obsidian.plist
```

## 8. 查看融合时间看板

```bash
# 本地 HTML 看板（融合时间/精力/优先级/状态/思路注释）
python3 scripts/dashboard.py
open vault/Dashboard/index.html

# Obsidian 内看板：打开 vault/Dashboard/看板.md（Dataview + Kanban + Tasks）
```

## vault 位置说明

- 默认 vault = 本仓库 `vault/` 目录，脚本默认 `VAULT_DIR=$ROOT/vault`。
- 若想独立存放，复制 `vault/` 到任意位置，并在调用脚本时设 `VAULT_DIR=/你的/路径`：
  ```bash
  VAULT_DIR="$HOME/Documents/ObsidianVault" ./scripts/capture.sh "点子"
  ```
- 建议：含隐私的 vault 单独建**私有**仓库；本仓库只放系统/脚本/模板/文档。
