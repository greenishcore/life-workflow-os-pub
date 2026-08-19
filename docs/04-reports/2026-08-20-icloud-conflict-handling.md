# iCloud 冲突处理（补齐 M3 的硬缺口）

日期：2026-08-20 · 状态：**已交付** · 关联：`docs/05-apple/prompts/M3-iOS应用.md` §4

---

## 一、这是在补什么

M3 规格里写着：

> 必须正确处理 iCloud 的三种状态：**未下载**、**下载中**、**冲突版本**（NSFileVersion）。
> 冲突时以 `updated` 较新者为准，并把落败版本保留到 `.conflicts/`，**不得静默丢弃**。

M3 交付时这一条没做完，只做到「iCloud 路径自动启用 NSFileCoordinator」。
在 vault 真的放上 iCloud、两端同时编辑之前，这是个数据风险点。本次补齐。

## 二、做法

### 2.1 裁决逻辑做成纯函数（`ConflictPolicy`）

不碰文件系统，因此可以被完整测试。裁决顺序，每层平手才看下一层：

1. frontmatter 的 `updated` 更新者胜 —— 用户显式表达的「我改过」
2. `lastActivity` 更新者胜 —— 含思路注释日期，反映实际演进
3. 文件修改时间更晚者胜
4. **内容更长者胜** —— 同一时刻的两份里，信息多的更可能是「加了东西」
5. 全平手 —— 两份实质等价，取其一

裁决结果带一句人话解释（如「updated 更新（2026-08-19 > 2026-08-10）」），
直接显示给用户，不做黑箱。

### 2.2 落盘顺序是刻意的

```
收集候选（当前版本 + 所有冲突版本）
    ↓
ConflictPolicy 裁决
    ↓
① 先把落败版本写进 .conflicts/<日期>/     ← 万一后面失败，数据也已安全
    ↓
② 胜者不是当前文件时，才覆盖主文件
    ↓
③ 标记冲突已解决
```

归档文件是普通 Markdown，头部有 HTML 注释说明来源、原文件、保留时间，
任何编辑器都能打开对比，确认无用后自行删除。`.conflicts/` 在扫描时被跳过，
不会被当成笔记混进看板。

### 2.3 未下载状态

iCloud 特有的坑：文件在目录里列得出来，读的时候是空的。
现在扫描时先查 `ubiquitousItemDownloadingStatus`，未下载就**跳过并发起下载**，
记一条告警，而不是把它当成一条空笔记或「文件损坏」。

### 2.4 UI

- macOS 状态栏：有冲突时显示可点击的橙色警示，直达设置页
- 两端设置页：列出冲突文件、一键「处理全部冲突」、处理后展示
  「哪个版本赢了、为什么、落败的存在哪」（macOS 上可点开访达定位）

## 三、验证

```
$ swift test
􁁛  Test run with 86 tests in 14 suites passed
（本次新增 22 项：ConflictPolicy 11 + 归档与状态 7 + 落盘 4）

$ xcodebuild -scheme LifeOS-macOS build      退出码 0   警告 0
$ xcodebuild -scheme LifeOS-iOS   build      退出码 0   警告 0
$ xcodebuild -scheme LifeWorkflowKit -destination 'generic/platform=iOS'   退出码 0
macOS 快照 16 张；iOS 在模拟器上启动成功
```

新增测试覆盖的关键性质：

| 性质 | 用例 |
|---|---|
| 裁决**与候选顺序无关** | `orderIndependent`（4 种排列都裁出同一胜者） |
| **有冲突就必有保留项**，落败者数组不会为空 | `losersNeverSilentlyDropped` |
| 三方冲突一胜两留，一份不少 | `threeWayKeepsAll` |
| 远端胜出 → 主文件更新，本机版本完整保留 | `remoteWins` |
| 本机胜出 → **主文件一个字节都不动** | `localWinsLeavesFileUntouched` |
| 处理后的文件仍能正常解析，没写坏 | `fileRemainsParseable` |
| `.conflicts/` 里的文件不会被扫回看板 | `archivedFilesAreNotScanned` |
| 同名来源重复归档不互相覆盖 | `archiveDeduplicates` |

## 四、诚实说明：哪一段没被测到

**真实的 `NSFileVersion` 未解决冲突只有 iCloud 能产生，本地造不出来。**
所以没法写一个「真的制造一次冲突再解决」的端到端测试。

我的应对是把风险面压到最小：把「裁决之后做了什么」——也就是真正会丢数据的
那一段——抽成 `applyDecision(_:to:root:)` 单独测试（4 项用例，见上表）。
剩下未被自动化覆盖的，只有 `NSFileVersion.unresolvedConflictVersionsOfItem` /
`isResolved` / `removeOtherVersionsOfItem` 这几个系统 API 调用本身。

**因此这条仍需你实测**：把 vault 放上 iCloud Drive，在 Mac 和 iPhone 上
同时离线编辑同一条想法，再恢复网络，看是否按预期弹出冲突提示、处理后
`.conflicts/` 里是否留有落败版本。在你做完这个验证前，我不会说它"已经好了"。

## 五、变更清单

```
新增  Store/ConflictPolicy.swift     纯裁决逻辑
新增  Store/CloudSync.swift          下载状态 + 冲突检测/解决/归档
改动  Store/VaultRoot.swift          VaultWarning 新增 notDownloaded / conflict
改动  Store/VaultStore.swift         扫描时识别两种 iCloud 状态；resolveConflicts / downloadPending
改动  Shared/AppState.swift          冲突计数、处理入口、处理结果
改动  macOS/Views/RootView.swift     状态栏冲突警示（可点击）
改动  macOS/Views/SettingsView.swift iCloud 同步卡片
改动  iOS/Views/SettingsView.swift   iCloud 同步分组
新增  Tests/ConflictTests.swift      22 项测试
```
