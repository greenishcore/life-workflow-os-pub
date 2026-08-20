# 安装与配置指南

> 目标：五分钟把应用跑起来；Obsidian 与各类外部工具都是**可选增强**。

## 1. 最小可用（必需）

```bash
pip3 install PyQt5 pyyaml
cd life-workflow-os
./bin/lifeos doctor     # 体检：看看 vault 路径与依赖情况
./bin/lifeos            # 启动图形界面
```

打包成可双击的应用（会出现在访达/启动台，并带图标）：

```bash
bash tools/build_app.sh
open "dist/Life Workflow OS.app"
ln -sfn "$PWD/dist/Life Workflow OS.app" /Applications/   # 可选：放进启动台
```

> `.app` 是启动器型包：代码与数据仍在本仓库，`git pull` 后立即是新版本。
> 若把仓库挪了位置，重新跑一次 `tools/build_app.sh` 即可。

## 1.5 三端怎么用

一共四个入口，能力不同：

| 入口 | 怎么开 | 说明 |
|---|---|---|
| **命令行** | `./bin/lifeos <子命令>` | 捕获 / 转换 / 看板 / 提示词 / 复盘 / git 归档 |
| **Mac · PyQt 版** | `bash tools/build_app.sh` 后双击 `dist/Life Workflow OS.app` | 9 个页面，功能最全 |
| **Mac · Swift 原生版** | 见下 | 与 iOS / watchOS 同一套代码，多一个「架构地图」页 |
| **iPhone / Apple Watch** | `bash tools/try-sim.sh iphone` / `watch` | **只能跑模拟器**，原因见下 |

构建 Swift 原生 Mac 版：

```bash
cd apple/LifeOSApp && xcodegen generate
xcodebuild -project LifeOS.xcodeproj -scheme LifeOS-macOS -configuration Release \
  -derivedDataPath /tmp/lifeos-rel -quiet build
cp -R /tmp/lifeos-rel/Build/Products/Release/*.app ../../dist/LifeOS.app
open ../../dist/LifeOS.app
```

本地构建不带隔离标记，双击即可，不会被 Gatekeeper 拦。

### 模拟器里的 iPhone / Watch

```bash
bash tools/try-sim.sh iphone          # 用你自己的 vault
bash tools/try-sim.sh watch --demo    # 或用仓库自带的示例数据
```

脚本会开模拟器、构建安装、把 vault 复制进 App 容器、启动应用。
**这是单向复制**：模拟器里改的内容不会回到你的 iCloud——模拟器读不到宿主机的
iCloud Drive，这是模拟器的限制，不是应用的。

### 装到真机

需要一个**代码签名身份**，`security find-identity -p codesigning -v` 若返回
`0 valid identities found` 就还不能装。用免费 Apple ID 就够：

1. Xcode → Settings → Accounts → `+` → 加你的 Apple ID（免费账号即可）
2. 打开 `apple/LifeOSApp/LifeOS.xcodeproj`，选中 target → Signing & Capabilities
3. 勾上 Automatically manage signing，Team 选你的 Personal Team
4. 选真机 → Run

注意免费账号的两个限制：**描述文件 7 天过期**（到期要重新 Run 一次），
以及 iCloud 容器、App Groups、CloudKit、Widget 这些权益都拿不到——
手表端的数据同步因此还没实现，界面能看，数据要靠 iPhone 侧手动放。

## 2. 可选依赖（缺了只影响对应功能）

应用内「设置 → 依赖体检」随时能看到装了哪些、还缺哪些。

| 工具 | 装它才能用 | 安装 |
|------|-----------|------|
| `pandoc` | Markdown → PDF / Word / HTML | `brew install pandoc` |
| `markitdown` | PDF/PPT/Excel 等 → Markdown（比 pandoc 覆盖广） | `pipx install markitdown` |
| `xelatex` | 高质量中文 PDF（没有则自动回退 Chrome 渲染） | `brew install --cask basictex` |
| `ocrmypdf` + `tesseract` | 扫描件 OCR | `brew install ocrmypdf tesseract` |
| `gh` | 里程碑 GitHub release | `brew install gh && gh auth login` |
| notes-exporter | Apple 备忘录导出 | 见下方第 5 节 |

LLM 提示词重写（可选）：

```bash
export OPENAI_API_KEY=sk-...        # Key 只走环境变量，不落盘
# Base URL 与模型在「设置 → 提示词重写用的 LLM」里改，支持任意 OpenAI 兼容接口
```

## 3. Apple 数据导入的权限

首次在「快速捕获」页点导入提醒/日程时，系统会弹自动化授权。
若被拒或没弹，去 **系统设置 → 隐私与安全性 → 自动化**，
允许 `Life Workflow OS`（或你的终端）控制「提醒事项」「日历」「备忘录」。

导入结果写入当天 `vault/Daily/YYYY-MM-DD.md` 的「## 提醒」「## 日程」段，
重复导入是**替换该段**而不是不断追加。

## 4. Obsidian（可选）

vault 就是标准 Obsidian 库，两边可以同时开、互不干扰。
不装也能用应用的全部功能；装了适合做双链漫游、图谱、移动端查看。

Obsidian → 「打开文件夹作为库」→ 选 `~/LifeWorkflowOS/vault/`。推荐插件：

| 插件 | 用途 |
|------|------|
| Templater | 用 vault 里的 `Templates/` 做可编程模板 |
| Dataview | frontmatter 当数据库查询 |
| Kanban / Tasks | 看板与任务视图 |
| Calendar + Periodic Notes | 每日/周/月笔记 |
| Obsidian Git | 自动 commit+push（与应用的「版本归档」二选一即可） |
| Remindian | Apple 提醒事项双向同步 |
| Excalidraw | 思维导图/白板 |

> 数据格式完全一致：应用写出的 frontmatter 与手写笔记逐字节同风格，
> Dataview 查询、Obsidian 链接都照常工作。

## 5. Apple 备忘录导出（可选）

```bash
git clone https://github.com/storizzi/notes-exporter.git ~/tools/notes-exporter
cd ~/tools/notes-exporter && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
```

之后在「快速捕获 → 导入备忘录」直接用（需备忘录 App 处于打开状态）。

## 6. 定时任务（可选）

```bash
bash scripts/launchd/install.sh              # 用默认提醒列表
bash scripts/launchd/install.sh 我的提醒      # 或指定列表名
```

安装器会按你的真实路径生成 plist（launchd 不展开 `$HOME`，路径必须绝对），
并从 `lifeos` 的配置里读出 vault 位置，避免「应用读 A、定时任务写 B」。

卸载：

```bash
launchctl bootout gui/$(id -u)/com.lifeos.sync && rm ~/Library/LaunchAgents/com.lifeos.sync.plist
```

## 7. vault 位置

默认 `~/LifeWorkflowOS/vault`——**在仓库之外**，这样升级代码不碰笔记、
笔记也不会被误提交进 git。要换：

- **界面**：设置 → 知识库位置 → 浏览 → 应用（写入 `~/.config/lifeos/config.json`）
- **命令行**：`VAULT_DIR=/你的/路径 ./bin/lifeos capture "点子"`
- **整体搬家**：`LIFEOS_HOME=/你的/路径`（vault / logs / prompts / skills 一起挪）

优先级：**环境变量 > `~/.config/lifeos/config.json` > 默认值**。

### 放进 iCloud（多设备共用）

```bash
export LIFEOS_HOME="$HOME/Library/Mobile Documents/com~apple~CloudDocs/LifeWorkflowOS"
```

iOS 端不需要这个环境变量：它用文档选择器让你直接选中 iCloud Drive 里的
同一个文件夹（免费 Apple ID 也能用，不需要 iCloud 容器权益）。

> 想给笔记做版本控制，就在 vault 所在目录单独 `git init`——**不要**把它放进
> 本仓库。如果 vault 在 iCloud 里，用 `git init --separate-git-dir=~/.lifevault.git .`
> 把 `.git` 放到 iCloud 之外，否则 iCloud 会去同步 git 内部文件并制造冲突。

## 8. 自检

```bash
./bin/lifeos doctor                      # 路径 + 外部工具 + vault 扫描
python3 -m unittest discover -s tests    # 核心层 44 项测试
python3 tools/smoke_gui.py               # GUI 8 页 × 明暗双主题冒烟
```
