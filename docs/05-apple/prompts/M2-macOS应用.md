---
type: prompt
id: apple-m2-macos
created: 2026-08-19
target: 构建 agent（SwiftUI · macOS）
tags: [prompt, apple, m2]
---

# M2：macOS 应用（主力工作台）

> 前置：`00-总纲.md` + M1 已交付。

## 1. 角色
资深 macOS 应用工程师，熟悉 SwiftUI 在 Mac 上的实际坑位
（窗口管理、侧边栏、表格、菜单栏命令、沙盒与安全作用域、AppleScript 桥接）。

## 2. 背景
现有 PyQt5 版 Mac 应用已跑通 8 个页面，是**交互规格的参照物**
（截图与实现见 `lifeos/gui/`）。本任务是用 SwiftUI 重做并**超越**它：
Mac 端要承担三端里最重的活——格式转换、git 归档、Apple 便签、复盘。

## 3. 目标
交付可替代 Python 版的原生 Mac 应用，覆盖六条主线全量功能。

## 4. 约束（在总纲之上追加）
- 使用 `NavigationSplitView`，侧边栏按五阶段闭环分组（总览/捕捉/整理/执行/复盘/归档）。
- 图表用 **Swift Charts**；必须支持明暗主题，且**不依赖任何网络资源**。
- 长任务（pandoc 转换、git push、AppleScript）走后台 `Task`，UI 不冻结，
  并有**可取消**与**实时日志输出**。
- 调用外部命令（pandoc / git / osascript）必须：
  统一封装、带超时、错误不抛到 UI 层而是返回结果对象、缺失时给出**具体安装命令**。
- 沙盒：若开启 App Sandbox，需正确声明 `com.apple.security.files.user-selected.read-write`
  与 AppleEvents 权限；vault 访问用安全作用域书签持久化。
- 转换缓存键与 Python 版一致：`sha256(输入) + 转换器版本`。

## 5. 输出格式
八个视图，与现有 Python 版功能对齐但交互更原生：

| 视图 | 关键要求 |
|------|----------|
| 看板 | 融合时间轴（生命线）、活跃热力图、状态分布、标签 TopN、最近思维轨迹；点击可跳转 |
| 快速捕获 | ⌘↩ 落 Inbox；Inbox 行「→ 想法」一键提升；Apple 提醒/日历/便签导入 |
| 想法库 | 三栏（列表/编辑器）；五维度控件；思路注释时间轴可增删；⌘S 保存、⌘N 新建 |
| 格式转换 | 拖拽入窗；缓存命中显式提示；依赖体检 |
| 提示词工作台 | 生成/编辑/留档；LLM Key 存 **Keychain** |
| 日志与复盘 | 运行日志表 + 统计图 + 一键生成周复盘 |
| 版本归档 | git 状态/提交/推送/tag/release；中文文件名正确显示（`core.quotepath=false`） |
| 设置 | vault 位置（含 iCloud 容器）、主题、Apple 默认值、LLM、依赖体检 |

## 6. 验收标准
- [ ] `xcodebuild -scheme LifeOS-macOS build` 零错误零警告；
- [ ] 八个视图均可打开、可交互，提供明暗两套截图；
- [ ] 用同一个 vault，**Swift 版与 Python 版交替编辑同一条想法 10 次**，
      内容零丢失、`git diff` 无噪音行；
- [ ] 转换：同一 PDF 连续转两次，第二次**命中缓存**且耗时 < 1s；
- [ ] git：在测试仓库完成 commit + push，中文文件名显示正确；
- [ ] AppleScript：提醒/日历导入写入当日 Daily 的对应段落，**重复导入是替换不是追加**；
- [ ] 权限被拒时给出具体的系统设置路径，不是一句「失败」；
- [ ] 关闭 App 后重启，vault 访问权限仍然有效（书签生效）。

## 7. 待确认问题
1. 是否开启 App Sandbox？（不开发布受限，开了 AppleScript 与任意路径访问要额外配置）
2. 是否需要菜单栏常驻图标 + 全局快捷键唤起「快速捕获」浮窗？
