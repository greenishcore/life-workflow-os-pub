# iOS App Intents：快捷指令与 Siri 捕获

日期：2026-08-20 · 状态：**已交付** · 关联：`docs/05-apple/prompts/M3-iOS应用.md`

---

## 一、为什么是 App Intents 而不是分享扩展

M3 规格里写的是「Share Extension + App Intents」两条并行，作为 iOS 上
**替代「读 Apple 便签」**的方案（便签无公开 API，这条调研早已确认）。

本次动手前先核实了一个前提，结果推翻了分享扩展这条路：

> **App Groups 需要付费开发者账号**，免费 Personal Team 无法使用。

而分享扩展是独立进程，要访问 vault 就必须通过 App Group 共享那个书签
（vault 是用户在文档选择器里选的目录，授权信息存在 App 的 UserDefaults 里）。
没有 App Group，扩展进程根本够不到 vault。

**App Intents 不受此限**：声明在主 App target 里的 Intent 跑在 App 自己的进程中，
直接读得到书签。而且能力反而更强——快捷指令、Siri、锁屏与控制中心都能触发。

所以：**分享扩展延后到有付费账号时再做，本次交付 App Intents。**

## 二、交付内容

`Sources/iOS/Intents/` 276 行，五个动作 + 一个实体：

| Intent | 作用 | 预置语音短语 |
|---|---|---|
| `CaptureIdeaIntent` | 一句话捕获到 Inbox | 「用生活工作流记一条」 |
| `CreateIdeaIntent` | 直接建成带状态机的想法 | 「用生活工作流新建想法」 |
| `AddThinkingNoteIntent` | 给某条想法补一条**思路注释** | 「用生活工作流补一条思路」 |
| `AdvanceIdeaIntent` | 推进到状态机下一步 | 「用生活工作流推进想法」 |
| `TodayFocusIntent` | 今天该推进什么 | 「生活工作流今天该推进什么」 |

`IdeaEntity`（`AppEntity` + `EntityStringQuery`）让「想法」成为快捷指令里
**可搜索、可引用**的实体，于是用户能拼出组合流程，例如
「找到状态是推进中的想法 → 给它加一条思路注释」，而不只是调用孤立动作。

全部 `openAppWhenRun = false`：不弹界面直接写文件，「嘿 Siri，记一条」才是几秒钟的事。

### 「补一条思路注释」为什么值得单独做成 Intent

思路注释是这套系统区别于普通笔记的地方——它记录想法**如何演进**。
但如果每次都要打开 App、找到那条想法、点进去、再打字，实际上就不会记。
做成 Siri 可直接调用的动作，思维轨迹才有可能真的被留下来。

## 三、把逻辑下沉，让 Intent 可被测试

Intent 跑在快捷指令/Siri 的调用链里，很难自动化验证。
所以实际动作全部下沉到核心包的 `IdeaActions`，Intent 只做薄适配：

```
IdeaActions.advance(_:)      推进状态 + 自动留痕
IdeaActions.todayFocus(_:limit:)  今日待推进的筛选与排序
IdeaActions.makeIdea(from:firstNote:)  随手记 → 想法
```

顺带消除了三处重复实现：iOS「今日」页、macOS 捕捉页、App Intent
原本各写了一遍「什么算待推进」「推进时记什么」，现在共用同一套规则，
不会再出现两处规则漂移。

## 四、验证

```
$ swift test
􁁛  Test run with 94 tests in 15 suites passed        （新增 8 项 IdeaActions）

$ xcodebuild -scheme LifeOS-iOS   build       退出码 0   警告 0
$ xcodebuild -scheme LifeOS-macOS build       退出码 0   警告 0
$ xcodebuild -scheme LifeWorkflowKit -destination 'generic/platform=iOS'   退出码 0
macOS 快照 16 张；iOS 在模拟器上正常启动
```

**Intent 注册验证**（查已构建的 App bundle）：

```
Metadata.appintents/extract.actionsdata
  ✅ CaptureIdeaIntent  ✅ CreateIdeaIntent  ✅ AddThinkingNoteIntent
  ✅ AdvanceIdeaIntent  ✅ TodayFocusIntent  ✅ IdeaEntity
  ✅ 5 个 shortTitle · 10 处 applicationName 占位（= 我写的 10 条短语）
  ✅ 全部 5 条短语文本
二进制
  ✅ 参数对话（"想记点什么？"）、错误文案、结果文案 全部就位
```

新增测试盯住的性质：推进会自动留痕且刷新 `updated`；**已在末态时什么都不改**
（不留空注释、不刷新 `updated`）；完整走一遍状态机恰好 4 步；今日待推进
**不含种子与完成**；超长首行截断到 60 字；空文本不产生想法。

### 一次自我纠错

验证 Intent 文案时我先用 `strings` 查主可执行文件，全部查不到，一度以为有问题。
实际是两个方法学错误叠加：`strings` 默认只抓 ASCII 序列会跳过中文；
且 Debug 构建的主可执行文件只是 40KB 的桩，真正代码在 `.debug.dylib`（3.5MB）里。
换成对 dylib 做字节匹配后全部命中——**是我的检查方式错了，不是代码有问题**。

## 五、仍需你实测的部分

Intent 的注册、编译、文案都已验证，但**没有在模拟器里真正触发过一次**——
Siri 与快捷指令的调用链无法在当前条件下自动化（iOS Simulator 集成仍卡在
`sudo xcode-select`）。请手动确认：

1. 装上 App 后，打开「快捷指令」App → 搜索「生活工作流」，应能看到 5 个动作；
2. 拖一个「记一条想法」出来运行，看内容是否落进 vault 的 Inbox；
3. 对 Siri 说「用生活工作流记一条」。

## 六、延后的部分

| 项目 | 原因 |
|---|---|
| Share Extension | **App Groups 需付费账号**，扩展进程够不到 vault |
| Widget / 控制中心小组件 | 同样需要付费账号 |
| macOS 端也接入 App Intents | 技术上可行（Mac 有快捷指令），但 macOS 的 vault 来自 AppConfig 而非书签，需另写一套解析；本次不做，避免为了共享而共享 |
