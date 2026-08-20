# 阶段报告：把前端做成可交接的契约

> 日期：2026-08-20 · 范围：macOS + iOS（SwiftUI 两端）
> 问题：界面设计这部分能不能交给另一个 agent 做，同时保住鲁棒性与设计质量？

## 一、结论

**能，但改造之前不能。** 骨架本来就干净——`PageScaffold` / `Card` / `StatTile` 这套组件
已经在用，`DashboardView` 的 `body` 就是纯组合、没有一行逻辑，核心包的 `kit-no-ui`
硬约束也保证了 UI 碰不到业务层。

缺的是另一半：**交接方改完之后，没有任何东西能判断他改对了没有。**

四个实测出来的缺口：

| 缺口 | 改造前 | 改造后 |
|---|---|---|
| 排版令牌 | macOS 视图 **140 处**写死字号、0 处语义字体 | 0 处写死，27 个按用途命名的令牌 |
| 视图/逻辑边界 | `ArchiveView` 调 `GitService` 9 次、`LogsView` 自己用 `FileManager` 落盘 | 视图只剩布局与表单 |
| 回归护栏 | 无——`--snapshot` 出 18 张图但没东西比对 | 两条快照命令 + 三条机器可判定的约束 |
| 设计文档 | `docs/` 22 篇没有一篇讲界面 | `docs/06-design/` 两份 |

一个对照值得记下来：**iOS 侧本来就是好样本**（0 处写死字号、15 处语义字体），
macOS 侧是问题所在（140 处写死、0 处语义）。所以令牌化的目标是具体的——
让 macOS 向 iOS 看齐，不是凭空发明一套设计系统。

## 二、做了什么

### 2.1 排版令牌（`Theme.Typo`，27 个）

按**用途**命名而非字号。绝大多数映射到系统语义字体。

映射是实测出来的：macOS 的 `.body` 13 / `.callout` 12 / `.subheadline` 11 /
`.footnote` 10 / `.largeTitle` 26，与迁移前的字号逐点相同。
（`.headline` 是 **Bold** 而非 semibold，所以「13 号半粗」用 `.body.weight(.semibold)`。）

三个固定字号各有理由：`axis` 9（绘图区尺寸是算出来的，刻度必须可预测）、
`emptySymbol` 30（是图形不是文字）、`display` 22（单处使用）。
`pageTitle` / `sectionTitle` / `sidebarTitle` 也固定，因为语义档位在 17 与 22 之间跳，
两个都会明显改变现有层级——留给接手方定夺。

### 2.2 服务调用收进 `AppState`

| 视图 | 原本 | 去处 |
|---|---|---|
| `ArchiveView` | `GitService.` × 9 | `loadGit` / `gitSync` / `gitRelease` |
| `LogsView` | `ReviewService.` × 3 + 直接 `FileManager` | `refreshReview` / `appendRunLog` / `writeReviewReport` |
| `ConvertView` | `ConvertService.` × 4 | `refreshConvertEnvironment` / `convert` / `clearConvertCache` |
| `PromptsView` | `PromptService.` × 3 | `isLLMAvailable` / `refreshPromptHistory` / `rewritePrompt` |
| `CaptureView`（两端各一份） | `EventKitBridge` × 4 | `importFromApple`——**两端共用一份** |

最后一条顺带消掉了重复实现：`EventKitBridge` 按 `canImport(EventKit)` 门禁而非按 OS，
iOS 上本来就可用，此前两端各写了一遍权限流程。

视图层现在唯一剩下的服务引用是 `ConvertService.Target`——纯类型引用，
选择器要用它渲染选项，不是在调用服务。

### 2.3 三条约束（复用 `ArchExtractor.checkInvariants`）

| id | 级别 | 判定 |
|---|---|---|
| `ui-typography-tokens` | 硬约束 | 视图不得写死字号 |
| `ui-no-services` | 硬约束 | 视图不得调用服务 |
| `ui-spacing-tokens` | 参考 | 间距应落在 `Theme.Space` 档位上 |

前两条设为硬门禁，判据与仓库既有的一致：**编译器管得了的不设门禁**。
写死字号编得过、视图里跑 git 也编得过，代价要等到交接之后才显现。

第三条刻意是参考项，它的产出是**给接手方的规范化清单**（当前 63 处）。
把这些对齐到刻度会改变布局——那是设计决策，不该由重构顺手决定。

判定细节：只管 `/Views/` 与 `/Components/`（`AppState` 调服务是本职）；
`Theme.swift` 是令牌定义处，放行；服务调用看「`Service.` 后跟小写」是方法或属性，
跟大写是嵌套类型。复用 `strippedCode` 已剥离注释与字符串字面量的结果。

### 2.4 快照工具链

```
tools/snapshot.sh       macOS：从 seed/ 建夹具 → 构建 → 离屏渲染 9 页 × 明暗
tools/snapshot-ios.sh   iOS：模拟器真实截图 5 标签页 × 明暗
```

两个决定值得说明：

**比对只做逐字节判断，不算像素相似度。** 目的是告诉你该看哪几张图——看图这件事
人和 agent 都做得比任何相似度指标准。而且逐字节比对不需要图像库，
仓库「零外部依赖、离线可用」的原则不用为它破例。
另加体积下限检查：整页渲染失败的图压缩后极小，不解码就能抓到。

**iOS 不用 `ImageRenderer`，改走模拟器真实截图。** iOS 页面全是
`NavigationStack` + `List` / `Form`，都由 UIKit 支撑，`ImageRenderer` 渲不出来；
给每页做快照替身既侵入又失真。切页靠应用已有的 `--tab` 启动参数。

**基线不入库**：18 张约 7.2MB，每次设计改动都重传会把仓库撑大。
它是本地反馈回路，不是版本化产物。

## 三、验证

### 3.1 令牌迁移的视觉代价（18 张逐像素比对）

- **10 张逐字节相同**
- **8 张仅亚像素级栅格差**（0.02%–0.22% 像素）。墨迹包围盒完全不变，即字形没位移；
  KPI 行墨迹像素数变化 0.00%
- **1 处提示文案换行早了一个字**（提示词页的 `随仓库/版本化`）。
  无截断、无重叠、无布局破坏

排除了字体度量的可能：AppKit 层实测语义字体与固定字号的文本宽度**完全一致**（0.00%），
换行差异来自 SwiftUI 对文本样式字体的行宽取整。

### 3.2 抽服务的视觉代价

**18/18 逐字节相同。** 纯重构，零代价。

### 3.3 约束的负向验证

往 `DashboardView` 注入 1 处写死字号 + 1 处 7pt 间距 + 1 处 `GitService` 直调：

```
❌ 有 2 处硬约束违例，构建应当失败
  ❌ [硬约束] 视图不得直接调用服务  —— 1 处
        DashboardView.swift:35  视图直接调用了 GitService.status，应经由 AppState
  ❌ [硬约束] 视图不得写死字号  —— 1 处
        DashboardView.swift:31  写死字号，应改用 Theme.Typo 的令牌
--check 退出码: 1
还原后退出码: 0
```

三处全部抓到、行号准确。

### 3.4 交接彩排

把 `Theme.Typo.hint` 从 `.subheadline` 调到 `.callout`（一次真实的设计改动）：

```
未变 0 张 · 有差异 18 张
↑ 如果差异页远多于你改动涉及的页面，多半是动到了 Theme 里的共用组件。
```

18 张全部报出（改的确实是共用组件，脚注提示命中），截图确认标签确实变大；
还原后回到 18 张全等。

### 3.5 常规

```
核心包警告: 0
Test run with 158 tests in 22 suites passed
--check 退出码: 0
macOS / iOS 两端构建退出码 0，警告 0
```

## 四、一个被推翻的论据

改造中途我给 `Theme.swift` 写了这样的理由：「换语义字体是为了动态字体，
固定像素字号不响应系统的文字大小设置，是无障碍缺陷」，
还据此给快照工具加了 `--dynamic-type` 开关。

**这个论据在 macOS 上是错的。** 实测：

```
large           墨迹像素 294
xxxLarge        墨迹像素 294
accessibility5  墨迹像素 294
NSFont .body pointSize = 13.0
```

macOS 没有动态字体，`.dynamicTypeSize` 对 SwiftUI 文本完全无效。
开关已撤掉（留着会让人误以为 macOS 有这个能力），代码注释里的理由改成了
真实的那个——**单一事实源**，并把这条实测结论写进去以免将来有人再试一遍。

语义字体仍然是对的选择，但好处只在 iOS 侧兑现（`Theme.swift` 在 `Shared/` 里两端共用）。

## 五、过程中的教训

1. **用正则批量替换标识符会误伤字符串字面量。** 把 `"数据源 logs/run-log.jsonl"`
   改成了 `"数据源 state.reviewLogs/run-log.jsonl"`。是快照逐像素比对抓出来的——
   这正好证明了快照回归的价值。架构地图那轮踩过同一个坑，所以约束检查器用的是
   已剥离字符串字面量的 `strippedCode`。

2. **`grep ... | grep -v 'state\.'` 会漏掉同一行里既有 `state.` 又有服务调用的情况。**
   `PromptsView` 那处 `PromptService.rewrite(raw, useLLM:, config: state.config)`
   就这么漏了。审计必须机械精确，不能靠行级过滤。

3. **自己写的解析器要有测试。** `leadingNumbers` 把 `.padding(.horizontal, 7)` 里的
   `.horizontal` 当成「已用令牌」提前返回，漏报了所有带边指定符的间距。
   是新写的测试抓出来的，修完清单从 42 处涨到 63 处。

4. **既有测试在拦我。** `onlyOneBlockingInvariant` 断言硬约束只有 `kit-no-ui`，
   注释写着「想再加硬门禁请连同理由一起改，别无声地改回去」。
   本次照做：改名为 `blockingInvariantsAreDeliberate` 并写明判据。

## 六、留给接手方的活

1. **约 60 处间距不在刻度上**（1/3/5/6/7/9/10/11/14/18/60pt），`ui-spacing-tokens`
   列出 file:line。归并会改布局，是设计决策。
2. **三个标题令牌仍是固定字号**，语义档位（17 / 22）都会明显改变层级。
3. **iOS 视图未迁到令牌**——它们用 `.font(.caption)` 这类语义字体（15 处），
   没有写死字号。统一到令牌会改变 iOS 观感（`.caption` 是 12pt，`Typo.micro` 是 13pt），
   属设计决策。
4. **Python 桌面版（`lifeos/gui/`，3369 行）不在这套系统里**，它有自己完整的
   QSS 调色板。两端设计会继续分叉。

## 七、未验证的部分

- iOS 快照的**跨机器一致性**没验过（只在本机一台模拟器上跑过）。夹具是从 `seed/`
  重建的，理论上一致，但机型、系统版本、状态栏内容都会影响截图。
- 真正的交接**没有发生过**——彩排是我自己改了一个令牌，不是另一个 agent
  按 `handoff.md` 独立作业。文档是否够用要等第一次真实交接才知道。
