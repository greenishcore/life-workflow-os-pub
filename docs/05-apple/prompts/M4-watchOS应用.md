---
type: prompt
id: apple-m4-watchos
created: 2026-08-19
target: 构建 agent（SwiftUI · watchOS）
tags: [prompt, apple, m4]
---

# M4：watchOS 应用（捕捉端 + 一瞥端）

> 前置：`00-总纲.md` + M3 已交付 + **付费开发者账号** + **watchOS SDK 已下载**。
> 若任一前置不满足，**停止并报告**，不要用假实现绕过。

## 1. 角色
资深 watchOS 工程师，清楚手表端的真实限制：小屏、短交互、无文件系统、EventKit 只读、
WatchConnectivity 不可靠。

## 2. 背景（调研已证实的硬约束，不可绕过）
- watchOS **无 iCloud Drive**（`ubiquityIdentityToken` 恒为 nil）→ 手表不持有 vault；
- EventKit 在 watchOS **只读**（10 个写入 API 为 `__WATCHOS_PROHIBITED`）；
- App Groups **不能**用于 iPhone ↔ Watch 同步；
- 可用通道只有 **CloudKit**（需付费账号）与 **WatchConnectivity**（社区反馈不稳定）。

## 3. 目标
交付一个**只做两件事**的手表应用：
1. **抬腕说一句就记下来**（语音捕获 → CloudKit Outbox → iPhone/Mac 排空写入 Markdown）；
2. **一瞥今天该推进什么**（读 CloudKit TodayProjection）。

## 4. 约束（在总纲之上追加）
- **主通道用 CloudKit**，WatchConnectivity 仅作为「iPhone 在附近时的加速路径」，
  且必须在其失效时**自动回落**到 CloudKit —— 不得把它作为唯一通道。
- 手表**只写 Outbox，永不直接改想法**；Outbox 记录写入后由 iPhone/Mac 排空并删除。
- 手表**离线时**必须能完成捕获（本地暂存，联网后上传），且 UI 明确显示「待同步 N 条」。
- 单次交互目标 **≤ 5 秒**：抬腕 → 说 → 完成，不得有多余确认步骤。
- **不实现**：编辑、搜索、格式转换、git、写提醒事项。

## 5. 输出格式
| 界面 | 内容 |
|------|------|
| 主界面 | 「今日待推进」前 3 条（标题 + 状态点）；顶部一个大号「记一条」按钮 |
| 捕获 | 语音听写 → 确认 → 入队；显示「已记下」与待同步计数 |
| 详情（可选） | 单条想法只读详情 + 「推进到下一状态」一键操作（同样走 Outbox） |
| Complication / Smart Stack | 今日待推进条数；点击直达捕获 |

## 6. 验收标准
- [ ] `xcodebuild -scheme LifeOS-watchOS -destination 'platform=watchOS Simulator,...' build` 通过；
- [ ] 真机（Watch7,8）安装成功并截图；
- [ ] **端到端**：手表语音记一条 → 在 iPhone 上出现在 Inbox → 在 Mac 上看到对应 Markdown 文件；
- [ ] **离线专项**：手表飞行模式下记 3 条 → 恢复网络 → 3 条全部到达且不重复；
- [ ] **幂等专项**：同一条 Outbox 记录被重复排空 2 次，Markdown 中**只出现一次**；
- [ ] WatchConnectivity 断开时自动回落 CloudKit，用户无感知；
- [ ] Complication 显示正确计数并可点击进入。

## 7. 待确认问题
1. 付费开发者账号是否已就位？（无则本里程碑无法开始）
2. 是否需要「推进到下一状态」这一写操作？（会增加 Outbox 的语义复杂度）
