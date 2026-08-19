---
type: prompt
id: apple-m3-ios
created: 2026-08-19
target: 构建 agent（SwiftUI · iOS）
tags: [prompt, apple, m3]
---

# M3：iOS 应用（随身捕捉端）

> 前置：`00-总纲.md` + M1 已交付；vault 已在 iCloud Drive 容器。

## 1. 角色
资深 iOS 工程师，熟悉 iCloud Documents、文件协调（`NSFileCoordinator`）、
分享扩展、App Intents / 快捷指令、WidgetKit。

## 2. 背景
iPhone 是「想法产生的地方」，但**不是干重活的地方**。
调研已确认 iOS 上没有 pandoc、没有可用的 git、没有 Notes API。

## 3. 目标
交付随身端：随时捕捉、随时查看看板、轻量编辑，数据与 Mac 通过 iCloud Drive 同一份 Markdown。

## 4. 约束（在总纲之上追加）
- vault 位于 **iCloud Drive 容器**；所有读写必须走 `NSFileCoordinator` + `NSFilePresenter`，
  否则会与 Obsidian / Mac 端互相覆盖。
- 必须正确处理 iCloud 的三种状态：**未下载**、**下载中**、**冲突版本**（`NSFileVersion`）。
  冲突时以 `updated` 较新者为准，并把落败版本保留到 `.conflicts/`，**不得静默丢弃**。
- **不实现**：格式转换（除自渲染 PDF）、git、Apple 便签读取。
- 便签的替代：实现 **Share Extension**（接收文本/链接/图片 → 落 Inbox）
  与 **App Intents**（供快捷指令与 Siri 调用「捕获一条想法」）。
- 离线可用：无网络时全部本地功能正常，同步在恢复后自动进行。

## 5. 输出格式
| 视图/扩展 | 关键要求 |
|-----------|----------|
| 今日 | 今天该推进什么 + 快速捕获入口 |
| 捕捉 | 大输入框、语音听写、Inbox 列表、「→ 想法」提升 |
| 想法库 | 列表 + 详情（五维度 + 思路注释时间轴，可增删） |
| 看板 | 融合时间轴 + 热力图（Swift Charts，触摸交互） |
| 设置 | iCloud 状态、同步诊断、LLM、主题 |
| Share Extension | 从任意 App 分享文本/链接 → Inbox |
| App Intents | 「记一条想法」「今天该推进什么」可被快捷指令/Siri 调用 |
| Widget（❓需付费账号） | 今日待推进 + 一键捕获 |

## 6. 验收标准
- [ ] `xcodebuild -scheme LifeOS-iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` 通过；
- [ ] 模拟器完成闭环并截图：捕获 → 提升为想法 → 加思路注释 → 看板出现生命线；
- [ ] **同步专项**：Mac 改一条、iPhone 改同一条，双方各自离线，恢复网络后
      冲突被检测、落败版本进 `.conflicts/`、无数据丢失；
- [ ] Obsidian iOS 打开同一目录，笔记显示正常、frontmatter 未被破坏；
- [ ] Share Extension 从 Safari 分享一个链接，正确落入当日 Inbox；
- [ ] 快捷指令调用 App Intent 成功写入一条捕获；
- [ ] iCloud 文件未下载时给出明确提示而非空白或崩溃。

## 7. 待确认问题
1. 是否需要 Widget？（需付费账号）
2. 分享扩展是否需要支持图片 OCR（Vision 本地识别）？
