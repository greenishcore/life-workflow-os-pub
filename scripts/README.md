# 脚本使用说明（scripts/）

每个脚本均可独立运行，也可被 launchd / 快捷指令 / agent 调用。

| 脚本 | 用途 | 依赖 | 用法 |
|------|------|------|------|
| `capture.sh` | 快速捕获想法到 `vault/Inbox/当天.md` | 无 | `./capture.sh "点子"` 或 `echo x \| ./capture.sh` |
| `convert.sh` | 任意格式 → Markdown(缓存) → pdf/docx/html | markitdown / pandoc | `./convert.sh in.pdf --to pdf` |
| `Makefile` | 批量转换（增量构建） | convert.sh | `make all` / `make md` |
| `reminders2obsidian.sh` | Apple 提醒 → Markdown 写进每日笔记 | osascript | `./reminders2obsidian.sh [列表]` |
| `calendar2md.sh` | Apple 日历 → Markdown 写进每日笔记 | osascript | `./calendar2md.sh [日历] [天数]` |
| `notes2obsidian.sh` | Apple Notes 单向导出 → vault | notes-exporter | `./notes2obsidian.sh` |
| `log_run.py` | agent 操作 JSONL 日志 | python3 | `python3 log_run.py --objective ...` |
| `rewrite_prompt.py` | 口语需求 → 五段式提示词文档 | python3（可选 LLM API） | `python3 rewrite_prompt.py "需求"` |

## 依赖安装（未装时）

```bash
# 格式转换
brew install pandoc
brew install --cask basictex   # 生成 PDF 需要 xelatex（或 brew install --cask mactex-no-gui）
pipx install markitdown        # 或 pip install 'markitdown[all]'

# OCR（扫描件）
brew install ocrmypdf tesseract

# 文件监听 / 日历 CLI（可选）
brew install fswatch ical-buddy
```

## 首次运行 Apple 脚本的权限

`reminders2obsidian.sh` / `calendar2md.sh` 首次运行会请求「自动化」权限：
系统设置 → 隐私与安全性 → 自动化 → 允许「终端 / osascript」控制「提醒事项 / 日历」。

## 定时任务（launchd）

```bash
mkdir -p ~/Library/LaunchAgents
cp scripts/launchd/com.me.reminders2obsidian.plist ~/Library/LaunchAgents/
# 改掉 plist 里的脚本路径与 Label 后装载：
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.me.reminders2obsidian.plist
# 卸载：
launchctl bootout gui/$(id -u)/com.me.reminders2obsidian
```
