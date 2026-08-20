# 设计系统

> 三端（macOS / iOS / watchOS）共用一份令牌与组件，都在
> [`apple/LifeOSApp/Sources/Shared/Theme.swift`](../../apple/LifeOSApp/Sources/Shared/Theme.swift)。
> 改设计从这个文件开始。

## 一、颜色

**没有调色板，用的是系统语义色。** 这是有意的：明暗主题、辅助功能的增强对比度、
以及各平台自己的观感规范都会自动跟随，不需要每端维护一套色值。

| 令牌 | 含义 |
|---|---|
| `Theme.accent` | 强调色（跟随系统强调色设置） |
| `Theme.faint` | 更淡的次要文字（`secondary` 的 70% 不透明度） |
| `Theme.cardBackground` | 卡片底色 |
| `Theme.pageBackground` | 页面底色 |
| `Theme.border` | 分隔线与描边 |

后三个按平台取不同的系统色，已在 `Theme` 里分好：macOS 用 `NSColor`，iOS 用 `UIColor`。

**watchOS 是例外，只能给定值。** 实测：`systemBackground` / `systemGroupedBackground` /
`secondarySystemGroupedBackground` / `separator` 在 watchOS 上**全部标了
`API_UNAVAILABLE(watchos)`**，只剩固定色（`.systemRed` 等）与 label 色。
而且 **watchOS 没有浅色模式**（`simctl ui appearance light` 返回 "Operation not supported"），
表盘永远黑底，所以直接写死是对的——不是偷懒，是平台只有一种外观。

**状态色不在这里**，它们由模型层用十六进制串携带（`Status.colorHex` / `Priority.colorHex` /
`RunLog.Status.colorHex` / `Skill.Status.colorHex`），`Theme.swift` 里的 `Color(hex:)`
负责转换。这么绕一道是因为核心包不能 import SwiftUI（`kit-no-ui` 硬约束），
而状态到颜色的映射属于领域知识，该跟着模型走。**要改状态色请改核心包的 `colorHex`。**

## 二、排版

按**用途**命名，不按字号命名。绝大多数映射到系统语义字体。

### 标题

| 令牌 | 实际 | 用途 |
|---|---|---|
| `Typo.pageTitle` | 20 bold（固定） | 页面大标题 |
| `Typo.sectionTitle` | 18 semibold（固定） | 区块小标题 |
| `Typo.sidebarTitle` | 14 bold（固定） | 侧边栏应用名 |
| `Typo.cardTitle` | `.body.weight(.semibold)` | 卡片标题 |

### 正文

| 令牌 | 实际 | macOS 字号 | 用途 |
|---|---|---|---|
| `Typo.body` | `.body` | 13 | 正文 |
| `Typo.list` / `listStrong` | `.callout` | 12 | 列表与表格 |
| `Typo.hint` / `hintStrong` / `hintMedium` | `.subheadline` | 11 | 次要说明、徽章、标签（**用得最多**） |
| `Typo.micro` / `microStrong` / `microMedium` | `.footnote` | 10 | 更小的辅助文字、分组标题 |

### 数字与等宽

| 令牌 | 实际 | 用途 |
|---|---|---|
| `Typo.metric` | `.largeTitle` 圆角粗体（26） | KPI 大数字 |
| `Typo.metricSmall` | `.body` 圆角粗体（13） | 卡片内小数字 |
| `Typo.mono` / `monoSmall` / `monoList` | 11 / 10 / 12 等宽 | 路径、哈希、时间戳、数值对齐 |

### 固定字号（三个，各有理由）

| 令牌 | 字号 | 为什么不用语义字体 |
|---|---|---|
| `Typo.axis` | 9 | 图表刻度。绘图区尺寸是算出来的，刻度字号必须可预测 |
| `Typo.emptySymbol` | 30 | 空态大图标，它是图形不是文字 |
| `Typo.display` | 22 | 架构地图的模块计数，单处使用 |

`pageTitle` / `sectionTitle` / `sidebarTitle` 也是固定的：语义档位在 17（`.title2`）
与 22（`.title`）之间跳，两个都会明显改变现有层级，留给你按新设计定夺。

### 三端的实际字号

同一个令牌在三端解析出不同的绝对字号，这是对的——各自遵循各自平台的规范。
下表全是 `preferredFont(forTextStyle:)` 的实测值：

| 令牌 | macOS | iOS | watchOS |
|---|---|---|---|
| `Typo.metric`（`.largeTitle`） | 26 | 34 | **36** |
| `Typo.body` | 13 | 17 | 16 |
| `Typo.list`（`.callout`） | 12 | 16 | **16** |
| `Typo.hint`（`.subheadline`） | 11 | 15 | 15 |
| `Typo.micro`（`.footnote`） | 10 | 13 | 13 |

⚠️ **`body` 与 `list` 在 watchOS 上都是 16，会撞在一起。** 手表上想区分正文与列表，
不能只靠这两个令牌，得配字重或颜色。

watchOS 的字号**不随表盘尺寸变**（40mm 与 46mm 实测完全相同），这点可以放心。

### 一条要知道的事实

**macOS 没有动态字体。** 实测：`NSFont.preferredFont(forTextStyle: .body)` 恒为 13.0，
给视图加 `.dynamicTypeSize(.accessibility5)` 渲染结果一个像素都不变。

所以用语义字体在 macOS 上是**中性**的，好处在 iOS 与 watchOS 兑现（那两端会跟随
用户的「文字大小」设置）。别在 macOS 上花力气做动态字体适配，那是空的。

## 三、间距

| 令牌 | 值 |
|---|---|
| `Space.xs` / `sm` / `md` / `lg` / `xl` / `xxl` | 2 / 4 / 8 / 12 / 16 / 20 |
| `Theme.pad` | = `Space.xl`（16），卡片内边距 |
| `Theme.gap` | = `Space.lg`（12），卡片之间 |
| `Theme.cardRadius` | 10 |

**这套刻度目前没有被完全落实。** 仓库里还散着约 60 处不在档位上的取值
（1/3/5/6/7/9/10/11/14/18/60pt）。它们没有被强行归并，因为对齐到刻度会改变布局——
那是设计决策，不该由重构顺手决定。

完整清单由 `ui-spacing-tokens` 约束列出，跑一次就能拿到：

```bash
cd apple/LifeWorkflowKit && swift run archmap-tool --repo ../.. --check
```

也可以在 macOS 应用的「架构地图」页直接看。

## 四、组件

都在 `Theme.swift` 里，三端可用。

| 组件 | 用途 | 关键参数 |
|---|---|---|
| `Card` | 带标题的卡片容器 | `title`、`hint`（标题右侧的小字说明） |
| `StatTile` | KPI 数字块 | `label`、`value`、`delta`、`color` |
| `Badge` | 状态/优先级色标签 | `text`、`color`、`filled` |
| `TagChip` | `#标签` 小胶囊 | `text` |
| `PageHeader` | 页面标题栏 | `title`、`subtitle`、`actions` |
| `EmptyStateView` | 空态提示 | `symbol`、`title`、`hint`、可选按钮 |
| `PageScaffold` | 页面统一外框（标题 + 可滚动内容） | `destination`、`actions`、`content` |
| `SplitOrStack` | 左右分栏（快照模式自动降级为 HStack） | `isSnapshotting`、`leftWidth` |

页面标题与副标题的文案不在视图里，在
[`Destination.swift`](../../apple/LifeOSApp/Sources/Shared/Destination.swift)——
它同时是侧边栏导航的数据源，改文案改那里。

## 五、三个绕不开的坑

这三条不是设计问题，是平台与工具的限制，改布局时会撞上：

1. **`ImageRenderer` 不给 `ScrollView` 里的内容做布局**，渲染出来是空白。
   macOS 的 `PageScaffold` 因此有一个 `isSnapshotting` 环境值：快照时换成固定高度的
   `VStack`。你新增的滚动容器如果要出现在快照里，得照这个做。

2. **`NavigationSplitView` / `HSplitView` / `List` / `Form` 由 AppKit / UIKit 支撑**，
   `ImageRenderer` 渲染它们只得到占位图。macOS 端用 `SplitOrStack` 绕过；
   iOS 与 watchOS 的页面全是 `NavigationStack` + `List` / `Form`，
   所以**这两端根本不用 ImageRenderer**，改用模拟器真实截图（见 [handoff.md](handoff.md)）。

3. **`onContinuousHover` 在 watchOS 不可用**（手表没有指针）。
   `HeatmapCalendar` 因此把悬停整段包在 `#if !os(watchOS)` 里。
   新增任何依赖悬停的交互，都要考虑手表上退化成什么。

## 六、Python 桌面版不在这套系统里

`lifeos/gui/` 是另一套：PyQt5 + QSS，有自己完整的调色板
（`lifeos/gui/theme.py`，15 个颜色 × 明暗两套，硬编码 hex）。

它与 SwiftUI 这套**没有共享任何令牌**，两边设计会各自演进。
本轮交接不覆盖它——如果你同时改了两边，注意它们不会自动保持一致。
