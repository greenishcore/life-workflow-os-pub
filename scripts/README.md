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
| `dashboard.py` | vault frontmatter → 融合时间看板 HTML | python3 + PyYAML | `python3 dashboard.py` |

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
bash scripts/launchd/install.sh              # 用默认提醒列表
bash scripts/launchd/install.sh 我的提醒      # 或指定列表名
# 卸载：
launchctl bootout gui/$(id -u)/com.lifeos.sync && rm ~/Library/LaunchAgents/com.lifeos.sync.plist
```

安装器按你的真实路径生成 plist 再装载——launchd 不展开 `$HOME`，
路径必须是绝对的，手改容易改错，而改错了 launchd 只会静默不跑。
