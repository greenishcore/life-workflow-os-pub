# 调研报告 R1-01：Apple 生态自动化 与 Obsidian 本地知识库

> 来源：后台检索 agent 调研，关键工具与 URL 均已 web 核实。

---

## 一、Apple Notes / Calendar / Reminders 的自动化导出与同步

### 1.1 AppleScript / JXA(osascript) 读写

**推荐方案**：用 `osascript`（AppleScript 或 JavaScript for Automation）直接读写三大 App，作为「胶水层」。可行性**高**，三大 App 都有完整脚本字典；首次运行须授予「自动化」权限（系统设置 → 隐私与安全性 → 自动化 → 允许终端/osascript 控制 Notes/Reminders/Calendar）。

- 工具：`osascript`（系统自带）、`AppleScript`、`JXA`。

**关键要点**（脚本字典核心对象/属性）：

- **Notes**：`note` 的 `name`、`body`（纯文本）、`plaintext`、`creation date`、`modification date`、`id`、`container`；附件经 `attachment` 读取（macOS 12+）。
  ```applescript
  tell application "Notes"
    repeat with n in (every note in folder "收件箱" of default account)
      get (name of n) & linefeed & (body of n)
    end repeat
  end tell
  ```
  > 注意：Notes 富文本/内嵌图片无法经 AppleScript 直接拿 HTML，正文只有纯文本；富文本需靠 1.3 的导出工具解析底层数据库。
- **Reminders**：`reminder` 的 `name`、`body`、`completed`、`completion date`、`due date`、`remind me date`、`priority`、`list`。
  ```applescript
  tell application "Reminders"
    tell list "Reminders"
      make new reminder with properties {name:"买菜", body:"牛奶 鸡蛋", due date:(current date) + 1 * days}
    end tell
  end tell
  ```
- **Calendar**：`event` 的 `summary`、`start date`、`end date`、`location`、`description`、`allday event`。
  ```applescript
  tell application "Calendar"
    every event of calendar "个人" whose start date ≥ (current date)
  end tell
  ```
- **JXA** 等价：`osascript -l JavaScript -e '...'`，如 `const Cal = Application('Calendar'); Cal.calendars[0].events().map(e => e.summary());`

**URL**：
- AppleScript 语言指南：https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/
- JXA 文档：https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/

### 1.2 Shortcuts 与文件系统 / 脚本交互

**推荐方案**：快捷指令做**移动端/菜单栏触发器**，落地动作交给「运行 Shell 脚本」或「运行 AppleScript」，结果直接写成 Obsidian Markdown。

- 关键动作：**「运行 Shell 脚本」**（仅 macOS，`/bin/zsh`，输入作参数或标准输入）、**「运行 AppleScript」**、**「运行 JXA」**；文件动作：保存/追加/获取/移动文件、新建文件夹。
- 写 vault 最稳链路：`获取剪贴板/输入 → 运行 Shell 脚本: cat >> "$HOME/Documents/vault/Inbox/$(date +%F).md" → 完成`。
- 权限坑：① 快捷指令 → 设置 → 高级 → 勾选「允许运行脚本」；② vault 目录不在允许列表时，在「运行 Shell 脚本」里允许「全部文件访问」或用「获取文件」建目录书签；③ iCloud Drive 真实路径 `~/Library/Mobile Documents/com~apple~CloudDocs/`。

**URL**：
- Apple「在 Mac 上运行 Shell 脚本」：https://support.apple.com/guide/shortcuts/run-shell-scripts-apdff9b7a9f3/mac

### 1.3 第三方工具 / 开源项目

**Apple Notes → Markdown（导出）**：

| 工具 | 用途 | URL |
|---|---|---|
| **notes-exporter**（storizzi） | 最常用导出 CLI：HTML/纯文本/**Markdown（含 Obsidian 适配）**/PDF/DOCX，处理图片附件 | https://github.com/storizzi/notes-exporter |
| **applenotes-exporter**（flkcgn） | 导出干净 `.md`，Obsidian 兼容 | https://github.com/flkcgn/applenotes-exporter |
| **apple-notes-exporter**（LorinWiedemeier） | notes-exporter 活跃 fork | https://github.com/LorinWiedemeier/apple-notes-exporter |
| **icloud-md**（coddingtonbear） | 把 Notes 当 Markdown 文件、git 风格 CLI、号称双向（实验性） | https://github.com/coddingtonbear/icloud-md |
| **Obsidian Importer**（官方） | 一次性把 Notes/OneNote/Evernote/Notion 导入 Markdown（单向） | https://github.com/obsidianmd/obsidian-importer |

**日历 CalDAV / ICS 同步**：

| 工具 | 用途 | URL |
|---|---|---|
| **icalBuddy** | 命令行打印 macOS 日历事件/任务 | https://github.com/peterwooley/icalBuddy（`brew install ical-buddy`） |
| **vdirsyncer** | CalDAV/CardDAV ↔ 本地目录双向同步（可连 iCloud，需 App 专用密码） | https://github.com/pimutils/vdirsyncer |
| **khal** | 终端日历 UI，读 vdirsyncer 同步的本地文件 | https://github.com/pimutils/khal |

### 1.4 Apple Notes ↔ Obsidian「双向」同步结论

**推荐方案：不要追求真双向**，采用「**Notes 做移动捕获 → 单向导出/导入 Obsidian**」。

- 事实：Apple Notes 底层是私有格式（SQLite + protobuf），官方无同步 API，**不存在可靠开箱即用的双向同步**。icloud-md 属实验项目、依赖非公开接口，易碎。
- **补充（2026-08 更新）**：storizzi/notes-exporter 自 v1.3.0 起提供基于 AppleScript 的**回写双向同步**（`--sync` / `--sync-only` / `--create-new`，带 `.conflict.md` 冲突检测）。它仍是 AppleScript 方案（macOS-only、依赖备忘录 App），非原生 API，但比 icloud-md 可靠、维护活跃，可作为「需要回写时」的务实选择。
- 限制：双向方案普遍有「富文本/图片/附件回写丢失」「冲突合并缺失」「依赖非公开接口随 macOS 升级失效」。
- 务实替代：移动端用 Notes/Drafts/快捷指令捕获 → 定期跑 notes-exporter 或 Obsidian Importer 单向汇入；需要「回写 Apple」时用 Reminders 插件单独走提醒事项。

---

## 二、Obsidian 本地知识库最佳实践

### 2.1 Vault 目录结构

**推荐方案**：**PARA（项目/领域/资源/归档）+ 每日笔记 + Inbox**，兼顾「行动」与「长期知识」。

```
vault/
├─ Inbox/            # 临时捕获，定期清空
├─ Daily/            # 每日笔记 2026-01-20.md
├─ Projects/         # 有目标、有截止的事
├─ Areas/            # 持续维护无截止（健康、财务、家庭）
├─ Resources/        # 兴趣主题、参考资料
├─ Archive/          # 已完结/失效
├─ Templates/        # Templater 模板
└─ Attachments/      # 图片/附件
```

- 若偏「卡片式笔记」可选 **Zettelkasten**（`Inbox` + `Fleeting` + `Literature` + `Permanent`，`[[wiki 链接]]` 互链、时间戳唯一 ID）。
- 两者可并存：PARA 管「项目与生活」，Zettelkasten 管「原子知识」。

**URL**：PARA（https://fortelabs.com/blog/para/）、Zettelkasten（https://zettelkasten.de/introduction/）

### 2.2 核心社区插件清单

| 插件 | 用途（一句话） | URL |
|---|---|---|
| **Templater** | 可编程模板（变量、JS 脚本） | https://github.com/SilentVoid13/Templater |
| **Dataview** | vault 当数据库，动态列表/表格 | https://github.com/blacksmithgu/obsidian-dataview |
| **Kanban** | 看板视图管理卡片/任务 | https://github.com/mgmeyers/obsidian-kanban（已迁 obsidian-community/obsidian-kanban） |
| **Excalidraw** | 手绘图表/白板 | https://github.com/zsviczian/obsidian-excalidraw-plugin |
| **Obsidian Git** | 定时 git 提交 + 远程备份与历史 | https://github.com/Vinzent03/obsidian-git |
| **Calendar** | 侧栏月历，点日期建/开每日笔记 | https://github.com/liamcain/obsidian-calendar-plugin |
| **Tasks** | 全文任务管理：查询/过滤/分组/截止 | https://github.com/obsidian-tasks-group/obsidian-tasks |
| **QuickAdd** | 一键捕获、宏、菜单命令 | https://github.com/chhoumann/quickadd |
| **Natural Language Dates** | `@today`/`@next monday` 自然语言日期 | https://github.com/argenos/nldates-obsidian |
| **Periodic Notes** | 日/周/月笔记框架 | https://github.com/liamcain/obsidian-periodic-notes |

### 2.3 每日笔记 + 想法捕捉（Inbox）工作流

**推荐方案**：**「全局快速捕获 → 每日笔记聚合 → 定期清空 Inbox」**。

- 用 **QuickAdd** 配「Capture」宏：热键唤起 → 追加到 `Inbox/待处理.md` 或当天 `Daily/YYYY-MM-DD.md` 的「## Inbox」段。
- 每日笔记模板固定三段：`## 今日任务`（Tasks 查询）、`## 日志`、`## 捕获`。
- 每日/每周回顾用 **Dataview** 汇总未完成项：```` ```dataview
TASK FROM "Inbox" WHERE !completed
``` ````
- 用 **Natural Language Dates** + **Tasks** 加 `📅 2026-01-21`、`⏳`、`#标签`，按到期日查询。

### 2.4 把 Apple 日历 / 提醒同步进 Obsidian

| 方案 | 工具 | 关键要点 | URL |
|---|---|---|---|
| Reminders 读入 | **Apple Reminders 插件**（urishiraval） | JXA 读系统提醒，渲染列表/看板；只读、仅 macOS | https://github.com/urishiraval/obsidian-apple-reminders-plugin |
| Reminders 双向 | **Remindian** | Obsidian Tasks ↔ Apple Reminders/Things3 双向、标签映射、菜单栏 | https://github.com/Santofer/Remindian |
| Reminders 其他 | obsidian-applekit-plugin / apple-reminders-sync | 同步 Reminders | https://github.com/tariqwest/obsidian-applekit-plugin · https://github.com/stengland/obsidian-apple-reminders-sync |
| 日历 ICS | **ICS 插件**（muness） | `.ics`/CalDAV 解析写入每日笔记 | https://github.com/muness/obsidian-ics |
| 日历全视图 | **Full Calendar**（官方社区） | 完整月历视图，事件存 frontmatter，支持 CalDAV(beta) | https://github.com/obsidian-community/obsidian-full-calendar |

落地链：Apple 日历导出/分享成 CalDAV 或 `.ics` → ICS 插件定时拉取 → 每日笔记 Dataview/Tasks 查询；或 Full Calendar 直接挂 CalDAV。提醒事项走 Remindian 双向。

---

## 三、数据格式与互操作

### 3.1 Apple 数据 → Markdown 转换要点

- 正文：Notes 的 `body`/`plaintext` 已是纯文本，直接作 Markdown 段落；标题用 note `name`，加 frontmatter（`title/created/modified/tags`）。
- 图片/附件：导出工具抽到 `Attachments/` 并改写为 `![[图片名]]`；纯 AppleScript 拿不到内嵌图，必须走工具。
- 富文本转 md：HTML 用 `pandoc -f html -t gfm`。
- 日期/时区：统一 ISO 8601（`YYYY-MM-DD HH:mm`）。

### 3.2 本地文件监控 / 同步方案

| 方案 | 工具 | 关键要点 | URL |
|---|---|---|---|
| 定时任务 | **launchd** | `~/Library/LaunchAgents/*.plist`；`StartCalendarInterval`/`StartInterval`；`WatchPaths` 只监听顶层；`ProgramArguments` 填脚本 | https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html |
| 实时监听 | **fswatch** | `brew install fswatch`；`fswatch -o ~/vault \| xargs -n1 -I{} your-script.sh`，递归、`--exclude` | https://github.com/emcrisostomo/fswatch |
| 图形化规则 | **Hazel** | 商业 App，按规则监听：重命名/移动/打标签/跑脚本 | https://www.noodlesoft.com/ |

launchd plist 示例（每 30 分钟把 Reminders 导出到 vault）：
```xml
<dict>
  <key>Label</key><string>com.me.reminders2obsidian</string>
  <key>ProgramArguments</key>
  <array><string>/usr/bin/osascript</string><string>/Users/me/scripts/reminders2obsidian.scpt</string></array>
  <key>StartInterval</key><integer>1800</integer>
</dict>
```
装载：`launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.me.reminders2obsidian.plist`

---

## 最推荐落地组合

1. **移动端捕获**：iPhone 用「快捷指令 + 运行 Shell 脚本/追加文本」把闪念写进 vault `Inbox/`（或先记 Apple Notes 再导出）。
2. **Notes→Obsidian**：单向导出，用 `notes-exporter`（https://github.com/storizzi/notes-exporter）定期汇入，放弃不靠谱双向。
3. **提醒事项双向**：装 **Remindian**（https://github.com/Santofer/Remindian）打通 Obsidian Tasks ↔ Apple Reminders。
4. **日历**：Apple 日历导出 `.ics`/CalDAV → **ICS 插件**（https://github.com/muness/obsidian-ics）写进每日笔记，或 **Full Calendar**（https://github.com/obsidian-community/obsidian-full-calendar）全月视图。
5. **自动化与备份**：`launchd` 定时跑 `osascript` 同步脚本 + **Obsidian Git**（https://github.com/Vinzent03/obsidian-git）版本备份；核心插件组合 Templater + Dataview + Tasks + QuickAdd + Calendar。

*工具名与 URL 均经 web_search 核实；AppleScript/JXA 属性名以对应 App「脚本字典」为准。*
