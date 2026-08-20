# 架构地图：可视化的架构与信息流，随代码自动更新

日期：2026-08-20 · 状态：**已交付**
方案：`~/.claude/plans/todo-prancy-rabin.md`

---

## 一、这件事要解决什么

你要一个能看懂**整个项目架构细节与信息处理流向**、并为后续迭代**提供决策支持**的东西，
形式可视化、随代码变动而更新、全部本地化。

调研发现三件决定方案的事实：

1. **现有架构文档全是静态 ASCII 图**（`architecture.md` 26 处图形字符、`architecture-v2.md` 21 处）。
   写的时候是对的，但和代码之间没有任何联系——代码改了图不会变。
2. **架构信息可以机械提取**：Swift 侧 59 个文件的 import 与类型引用可解析；
   `run-log.jsonl`、`skills/`、vault 的读写方都能通过标志符号追踪；变更频率可从 git 拿到。
3. **最关键的空白**：`architecture-v2.md:47` 的「依赖只能向下」、
   `prompts/00-总纲.md:38` 的「核心包不得 import SwiftUI」——**这些约束只是散文，
   没有任何东西在保证**。

所以这件事的价值不止于画图。**图会过时，被强制的约束不会。**

## 二、方案

三个已确认的决定（应用内一页 / CI 自动重生成并提交 / 只覆盖 Swift 端）组合起来有个张力：
页面在应用内渲染，CI 就没有产物可提交。解法是拆开——

```
apple/ 源码树
    │  ArchExtractor（纯逻辑，可测试）
    ▼
ArchModel ──► docs/02-architecture/archmap.json   （确定性，入库，可 git diff）
    │              ▲
    │              └─ CI：变更即重生成并提交；硬约束违例则 job 失败
    ▼
macOS「架构地图」页（Canvas 原生渲染）
```

**结构进 JSON，指标算在应用里**：结构变化才值得留在版本历史；
变更频率每次提交都变，入库只会制造噪音提交。

## 三、交付内容

```
apple/LifeWorkflowKit/Sources/LifeWorkflowKit/ArchMap/    （约 900 行）
├── ArchModel.swift      Codable 模型，确定性序列化
├── SourceScanner.swift  逐行扫描 import / #if os / 行数 / 顶层公开类型 / 敏感符号
├── LayerRules.swift     分层、模块归属、数据产物、五阶段闭环（声明部分）
├── ArchExtractor.swift  组装模型 + 校验约束
└── ArchMetrics.swift    变更频率与风险排序（实时算，不入库）

apple/LifeWorkflowKit/Sources/archmap-tool/main.swift     CI 与本地用的命令行
apple/LifeOSApp/Sources/macOS/Views/ArchMapView.swift     页面
apple/LifeOSApp/Sources/macOS/Components/{ArchGraph,FlowDiagram}.swift  两张图
docs/02-architecture/archmap.json                         产物（入库）
```

### 页面四块

| 块 | 内容 |
|---|---|
| 架构约束校验 | 5 条规则的通过/违反状态，每条都写明**为什么有这条规则** |
| 分层依赖图 | 表现层在上、数据层在下，箭头一律向下；反向依赖标红；悬停看详情、点击下钻到文件 |
| 信息流向 | 五阶段闭环 × 6 个数据产物，橙色实线=写入、灰色虚线=读取 |
| 改动风险排序 | `近期改动次数 × 被依赖数 ÷（有测试则减半）`，排在前面的改之前先补测试 |

风险算式刻意用一句话能解释清楚的形式，而不是黑箱评分：
常改说明还在演进，被依赖多说明改错了波及面大，有测试至少能挡一下。

### 五条被强制的约束

| 约束 | 级别 | 为什么 |
|---|---|---|
| 核心包不得 import SwiftUI/UIKit/AppKit/WatchKit | 硬 | 核心包要三端共用，一旦依赖 UI 框架跨端复用就废了 |
| 依赖只能向下 | 硬 | 底层不该知道上层存在；反向依赖会让数据层被 UI 牵着走 |
| macOS 与 iOS 的 UI 互不依赖 | 硬 | 两端刻意各写各的，互相引用等于变相共用一套界面 |
| 子进程调用限定 macOS | 硬 | iOS 沙盒不允许 fork；不隔离会在 iOS 上编译通过、运行时才炸 |
| 核心包每个模块都有测试覆盖 | 参考 | 只提示不阻断，避免为了指标写假测试 |

## 四、它当场就发现了一个真问题

第一次在真实仓库跑，报了 `Config（base）依赖了上层的 Store（data）`。查下来是**真的**：
`AppConfig.RootConfig.root` 返回 `VaultRoot`。

但结论不是「代码错了」，而是**我原先写的分层定义错了**。
`architecture-v2.md` 那套四层是描述 Python 版的，「基础层」在 Swift 核心包里
不对应任何独立的东西——`AppConfig` 描述数据在哪、`VaultStore` 读写数据，
两者是**同层的邻居**而非上下级。改成三层后约束通过。

这正是这个工具该干的事：**它让文档与实现的偏差第一次变得可见**。

同样地，交付过程中给 `AppState.loadArchMap` 加 `#if os(macOS)`，
也是被「子进程限定 macOS」这条约束推着做的——iOS 端编译直接报错，
而不是等运行时才发现。

## 五、验证（实际执行的命令与输出）

```
$ swift test
􁁛  Test run with 136 tests in 19 suites passed          （113 → 136，新增 23 项）

$ swift run archmap-tool --repo ../.. --check
模块 12 个 · 依赖边 27 条 · 数据产物 6 个 · 源文件 59 个
  ✅ [硬约束] 依赖只能向下
  ✅ [硬约束] 核心包不得依赖 UI 框架
  ✅ [硬约束] 子进程调用限定 macOS
  ✅ [硬约束] macOS 与 iOS 的 UI 互不依赖
  ⚠️ [参考] 核心包每个模块都有测试覆盖
✅ 硬约束全部通过                                        退出码 0

$ 连续生成两次 → diff 无差异                             （确定性，CI 不会反复提交）
$ xcodebuild macOS / iOS                                 退出码 0 / 0，警告 0 / 0
$ 快照 18 张（9 页 × 明暗双主题）
```

### 负向验证（这个功能的核心主张）

光说「能拦住违例」不算数，实际注入过两次：

```
注入 import SwiftUI 到核心包
  ❌ [硬约束] 核心包不得依赖 UI 框架 —— 1 处
        .../Stats/Aggregations.swift  核心包 import 了 SwiftUI
  退出码 1

注入未保护的 Process()
  ❌ [硬约束] 子进程调用限定 macOS —— 1 处
        .../Stats/Aggregations.swift:8  Process 未被 #if os(macOS) 包住
  退出码 1

还原后 → ✅ 硬约束全部通过
```

### 过程中修掉的三类误报

提取器第一版报了 5 处违例，其中 3 处是它自己的问题，都已修并补了回归测试：

1. **嵌套类型撞名**：把 `ArchExtractor.Result` 也登记成模块类型，导致任何用
   Swift 标准库 `Result` 的文件都被判为依赖 ArchMap。→ 只登记顶层公开类型。
2. **字符串字面量自我命中**：`watchedSymbols = ["Process("]` 这一行把自己判成违例。
   → 检测符号前先剥字符串字面量。
3. **同一问题的另一处**：`markers: ["VaultStore"]` 让声明它的文件被判成 vault 的读写方，
   还造出 4 条假依赖边。→ 类型引用判定也要剥字符串（边数 31 → 27）。

还修了一处过度归因：`AppConfig` 声明了所有产物的路径访问器，被误判成所有产物的写方。
→ 区分「声明路径」与「读写内容」，新增 `declaredBy` 字段。

## 六、怎么用

```bash
# 本地重生成
cd apple/LifeWorkflowKit && swift run archmap-tool --repo ../..

# 只校验不写文件（CI 用的就是这条）
swift run archmap-tool --repo ../.. --check
```

应用里打开「架构地图」页即可看。改完代码想立刻看到效果，点右上角「从源码重算」，
不必等 CI。CI 会在每次改动 `apple/**` 时重新生成并提交 JSON，
**并在硬约束被违反时直接让 job 失败**。

## 七、明确没做

- **不覆盖 Python 版 `lifeos/`**（按你的选择）。代价：你日常仍在用 Python 版桌面应用，
  地图不反映它。
- **不引任何图形渲染依赖**（dot/mermaid/plantuml 本机都没装，也与仓库「零外部依赖」原则冲突）。
- **不做自动布局算法**：架构是分层的，确定性布局才能用来对比「这次改动让图变成了什么样」。
- **信息流的读写方判定是粗判**（按标志符号 + 写操作关键字），
  目的是在图上区分箭头方向，不是做静态数据流分析。
