# 阶段报告：拆分代码与个人数据，开源化改造

> 日期：2026-08-20 · 状态：改造完成并验证，等待发布
> 结果：仓库从「代码 + 作者的笔记」变成「纯代码」，个人数据迁至 `~/LifeWorkflowOS/`

## 一、起因与决策

### 1.1 触发事件

GitHub Actions 配额耗尽。调研后确认两件事：

- **公开仓库的 GitHub 托管标准 runner 免费不限量**，macOS 也在内；私有仓库 Free 版每月 2000 分钟（Linux 计），**macOS 按 10 倍扣、Windows 按 2 倍扣**。
- 本仓库的消耗集中在 `swift-kit` job：`macos-15` 上跑 checkout → 零警告构建 → 154 项测试 → iOS 交叉编译，四步且无构建缓存，每次 `apple/**` 推送都触发。历史 22 条提交里 16 条命中它的路径过滤。

配额问题有四种解法（改触发条件、自托管 runner、缩短 job、拆仓库）。选择**拆仓库**，因为它同时解决另一个更重要的目标：**让别人也能用这套系统**。

### 1.2 为什么不是「把现有私有仓改成公开」

现有仓库的 22 条历史里有作者的个人笔记。即便用 `git-filter-repo` 重写后 force-push，**被覆盖的旧提交在 GitHub 垃圾回收前仍可通过 SHA 直接访问**，存在残留窗口。

因此改为：**把重写后的干净历史推到一个新仓库**，原私有仓库保持私有不动、作为完整存档。新仓库从未见过 vault 内容，残留风险为零。

### 1.3 为什么删掉 vault 还不够

存量其实不重：vault 只跟踪了 16 个文件，其中大半是模板和目录说明，真实笔记 3 篇。

真正的问题是**增量**——这个系统被设计成会持续累积个人内容：

| 路径 | 会累积什么 | 原 `.gitignore` |
|---|---|---|
| `vault/Inbox`、`Daily`、`Projects` | 想法、每日笔记 | ❌ 只挡了三个转换缓存目录 |
| `logs/run-log.jsonl` | 应用自动记录的每次操作 | ❌ 只挡了 `*.private.jsonl` |
| `prompts/00_inbox/` | 原始自然语言输入 | ❌ |

而 `generate-dashboard.yml` 是 `git add -A` + 自动 push。也就是说，公开之后**每记一条想法，机器人会替你发布出去**。

所以这次改造的核心不是「删文件」，而是**把默认数据落点搬出仓库**。

## 二、改造内容

### 2.1 数据落点（核心改动）

`lifeos/config.py` 新增 `LIFEOS_HOME`（默认 `~/LifeWorkflowOS`），`vault` / `logs` / `prompts` / `skills` 全部搬出仓库。

改动前的默认值是 `REPO_ROOT / "vault"`——**任何人 clone 下来一用，笔记就写进 git 工作区**，正是本次要逃离的陷阱，只是换了个人踩。

配套新增 `seed/`，装随仓库分发的种子内容：

```
seed/
├── vault/       骨架与笔记模板  ── 缺了就补
├── examples/    示例笔记        ── 只在 vault 还没有任何笔记时放一次
├── skills/      内置 skills     ── 缺了就补
└── prompts/     提示词模板       ── 缺了就补
```

两条规则不同，是因为解决的问题不同：

- **模板缺了就补**：误删能自动恢复，升级仓库不会覆盖你改过的模板（只在文件不存在时复制）。
- **示例笔记只放一次**：否则你删掉示例之后，每次启动它们又会冒出来。判据是「vault 里有没有非模板、非 README 的 `.md`」。

播种做成**显式方法 `seed_once()`，刻意不放进 `ensure_dirs()`**。后者的职责是建目录；往用户 vault 里写内容是另一回事。混在一起的直接后果是测试和脚本会意外多出文件——改造过程中就因此挂掉 3 个用例（详见 §4.1）。

### 2.2 复用性修复（三个真 bug）

审查中发现的问题，都不是隐私问题，是**别人拿去用会坏**：

1. **`scripts/launchd` 的 plist 写死了作者的绝对路径。** 别人装上这个定时任务直接是坏的。改为 `com.lifeos.sync.plist.template` + `install.sh`：安装器按真实仓库位置生成 plist，并从 `lifeos` 配置里读出 vault 路径写进 `EnvironmentVariables`，避免「应用读 A、定时任务写 B」。
   之所以要脚本而不是让用户手改：launchd 不展开 `$HOME` 之类的变量，路径必须绝对，而**改错了 launchd 只会静默不跑**。

2. **`GitService` 的用例断言仓库目录名必须叫 `life-workflow-os`。** 任何人 clone 成别的目录名都会失败。改为断言「找到的根是本文件的某级祖先」——这才是 `findRepository` 真正该保证的性质。（顺带：两边都要 `resolvingSymlinksInPath()`，否则 `/tmp` 与 `/private/tmp` 的软链会造成假失败。）

3. **交叉验证夹具由作者的 3 篇真实笔记生成。** 测试数据永久编码了个人内容。改为由 `seed/examples` 生成，`genfixtures.sh` 的来源同步调整。

### 2.3 仓库层面

- **补 `LICENSE`（AGPL-3.0）**。此前没有许可证——法律上别人不能用，「可复用」是句空话。
- **删掉 `generate-dashboard.yml` 与 `vault-backup.yml`**。这两个 workflow 的职责就是把 vault 自动提交上去，在公开仓库里是持续泄漏管道。
- **`archmap.yml` 改回随 `apple/**` 变更重算**。之前限成每周一次纯粹是因为私有仓库上 macOS runner 按 10 倍扣配额；公开后这个理由消失。不会形成触发环路——它提交的是 `docs/02-architecture/archmap.json`，不匹配 `apple/**`。
- **`test.yml` 增加 `seed/**` 触发**：夹具由它生成，改了要重跑。
- **`logs/bench.jsonl` → `docs/02-architecture/bench-baseline.jsonl`**。基准现在写进用户自己的数据目录；仓库里这份留作「在什么硬件上该跑出什么数」的参考快照。
- **`.gitignore` 加锚定规则** `/vault/`、`/logs/`、`/prompts/`、`/skills/`：数据默认本就在仓库外，这是双保险。前导斜杠只锚定仓库根，不会误伤 `seed/vault`。

### 2.4 历史清理

用 `git-filter-repo` 处理：

- **整体摘除 `vault/`**，不逐个点名删除。理由：历史上 vault 下曾存在 19 个路径（含后来删掉的 Obsidian 个人配置），逐个点名等于赌「有没有漏掉某个」，整体摘除没有这个赌。
- **mailmap 统一提交身份**为 GitHub noreply 邮箱。公开仓库的提交邮箱是爬虫的标准食粮。

22 条提交中有 1 条只改动 vault，重写后变空被剪掉；本次改造提交 1 条，最终仍是 22 条。

## 三、验证

全部实跑，输出如下：

```
$ python3 -m unittest discover -s tests
----------------------------------------------------------------------
Ran 44 tests in 0.035s

OK

$ cd apple/LifeWorkflowKit && swift test
􁁛  Test run with 154 tests in 22 suites passed after 1.473 seconds.

$ python3 tools/smoke_gui.py
✅ 全部页面通过

$ swift run archmap-tool --repo ../.. --out /tmp/a1.json   # 两次，比对
约束校验：
  ✅ [硬约束] 核心包不得依赖 UI 框架
✅ 硬约束全部通过
两次输出逐字节相同 ✅
```

iOS 交叉编译单独验（注意取真实退出码，不能被管道末端的命令掩盖）：

```
$ set -o pipefail
$ xcodebuild -scheme LifeWorkflowKit -destination 'generic/platform=iOS' -quiet build > /tmp/ios.log 2>&1
$ echo $?
0
$ grep -c 'error:' /tmp/ios.log
0
```

### 3.1 播种行为专项验证

```
首次播种后 vault： README.md ×3, daily-note.md, idea.md, log-entry.md,
                  prompt.md, 示例-把纸质书笔记数字化.md, 示例-搭建家庭影音库.md
skills: README.md, _template.md, convert-document.md

删掉示例 + 有了自己的笔记后再播种，示例复活了吗： ❌ 没有（正确）
误删模板后补回来了吗： True
```

### 3.2 「陌生人首次运行」模拟

清空数据目录后跑 `./bin/lifeos doctor`：

```
配置来源: default
  ✅ vault    <LIFEOS_HOME>/vault
  ✅ logs     <LIFEOS_HOME>/logs
  ✅ prompts  <LIFEOS_HOME>/prompts
  ✅ cache    <LIFEOS_HOME>/.cache
扫描到 2 条记录
```

关键点：**数据全部落在仓库之外**，且看板不是空的（2 条示例笔记）。运行后 `git status` 无新增文件——仓库没有被写脏。

### 3.3 清理效果核验

| 检查 | 结果 |
|---|---|
| 历史中 `vault/` 路径数 | 0 |
| 历史 blob 全文扫描个人邮箱 | 0 命中 |
| 工作区扫描个人路径 / 笔记标题 | 0 命中 |
| 提交作者身份 | 统一为 noreply 邮箱 |

## 四、过程中的教训

### 4.1 播种不该是建目录的副作用

第一版把 `seed_once()` 写进了 `ensure_dirs()`，结果 3 个仓库测试直接挂掉——它们建了临时 vault，播种往里塞了示例笔记，计数全部对不上。

试过用「vault 是否已存在」当判据，也不行：测试的 vault 本来就不存在。

最后的结论是这个设计本身有问题，不是判据没调好：**`ensure_dirs()` 的职责是建目录，往用户的 vault 里写内容是另一回事。** 拆开之后测试恢复正常，而且顺带得到了更好的语义（模板补、示例不补）。

值得记下来的是：**是测试先发现了这个设计问题**，不是先想明白再改的。

### 4.2 管道会吞掉退出码

`xcodebuild ... | tail -6` 之后 `echo $?` 拿到的是 `tail` 的退出码，永远是 0。这个坑在之前的阶段踩过一次（一个 `&&` 链让失败的 iOS 构建打印了「✅ 通过」），这次又差点重蹈。验证构建结果时必须 `set -o pipefail` 或直接重定向到文件再取 `$?`。

## 五、遗留

### 5.1 需要用户操作

- **`~/.config` 属主是 root**（由 `~/.config/fish` 带出来），导致 `~/.config/lifeos/config.json` 写不进去，**GUI 设置页的「保存」会失败**。这是既存环境问题，与本次改造无关。修复：`sudo chown -R $(whoami) ~/.config`。
  在修好之前，改配置只能靠环境变量，而**从访达启动的 GUI 读不到 shell 里 export 的变量**。
- **创建公开仓库并推送**——不可逆的对外发布，需人工执行。

### 5.2 未验证的部分

诚实标注，这些没跑过：

- `scripts/launchd/install.sh` 只做了语法检查与 `plutil -lint` 校验，**没有真正 bootstrap 装载过**。
- iCloud 的**跨设备同步**只是把文件放进了 iCloud Drive 目录，实际同步到 iPhone 的效果没验证。
- 公开仓库上的 CI 行为（免费不限量、`archmap.yml` 的 push 触发）在仓库建起来之前无法验证。

### 5.3 不在本次范围

- Python 侧 `weekly_review.py` 未同步提炼规则（有意不重复实现）。
- 架构地图仍不覆盖 Python 版 `lifeos/`。
- 分享扩展、Widget、真机安装仍被免费账号与签名身份阻塞。

## 六、迁移后的结构

```
公开仓库（代码）                     个人数据（不进任何远端）
├── lifeos/        Python 核心+GUI    ~/LifeWorkflowOS/
├── apple/         Swift 包 + 应用    ├── logs/      运行日志
├── seed/          种子模板与示例      ├── prompts/   提示词
├── scripts/ tools/ docs/ tests/     ├── skills/    沉淀的技能
└── LICENSE        AGPL-3.0          └── .cache/

                                     iCloud Drive/LifeWorkflowOS/
                                     └── vault/     笔记（本地 git，无远端）
```

vault 用 `git init --separate-git-dir` 把 `.git` 放在 iCloud 之外——否则 iCloud 会去同步 git 的内部文件并制造冲突。日志与提示词**刻意不放 iCloud**：JSONL 频繁追加容易产生同步冲突，而它们也不需要跨设备。
