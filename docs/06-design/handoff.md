# 界面设计交接说明

> 给接手界面设计的人或 agent。读完这一份就能开工。
> 令牌与组件清单在 [design-system.md](design-system.md)。

## 你能改什么

**可以重排布局**：颜色、字号、间距、圆角，以及卡片与分栏的重新组合。

**不要动**：数据流与交互行为。按钮点下去发生什么、页面加载什么数据、
操作成功后跳到哪——这些不在这次交接范围内。

边界不是靠自觉，有三条约束在机器层面守着（见下）。

## 改哪些文件

| 目的 | 文件 |
|---|---|
| 调整令牌（颜色/字号/间距） | `apple/LifeOSApp/Sources/Shared/Theme.swift` |
| 改组件外观 | 同上，文件后半段的 `Card` / `StatTile` / … |
| 重排某一页 | `Sources/macOS/Views/*.swift`、`Sources/iOS/Views/*.swift`、`Sources/watchOS/Views/*.swift` |
| 改页面标题与副标题 | `apple/LifeOSApp/Sources/Shared/Destination.swift` |
| 改状态色 | `apple/LifeWorkflowKit/Sources/LifeWorkflowKit/Models/` 里的 `colorHex` |

**别碰** `Sources/Shared/AppState.swift`——那是业务编排，视图从它读数据、调它的方法。

## 自验：三条命令

### 1. 约束检查

```bash
cd apple/LifeWorkflowKit && swift run archmap-tool --repo ../.. --check
```

违反硬约束时退出码非零。三条约束：

| id | 级别 | 判定 |
|---|---|---|
| `ui-typography-tokens` | **硬约束** | 视图里不得出现 `.font(.system(size:`，用 `Theme.Typo` 的令牌 |
| `ui-no-services` | **硬约束** | 视图不得调用服务（`XxxService.` 后跟小写的成员，或 `EventKitBridge()`） |
| `ui-spacing-tokens` | 参考 | 间距应落在 `Theme.Space` 的档位上——**这条是清单不是门禁** |

前两条是硬门禁，判据是「编译器管不了」：写死字号编得过、视图里跑 git 也编得过，
代价要等到交接之后才显现。

`ConvertService.Target` 这类**嵌套类型引用是放行的**（选择器要用它渲染选项），
判定只看点号后面是小写（方法/属性）还是大写（类型）。

### 2. macOS 快照

```bash
bash tools/snapshot.sh --baseline    # 动手前先立基线
bash tools/snapshot.sh --compare     # 改完比对，列出有差异的页面
```

9 个页面 × 明暗两套 = 18 张。比对**只做逐字节判断**，告诉你该看哪几张图——
看图这件事你自己做得比任何相似度指标都准，而且逐字节比对不需要任何图像库。

脚本还会检查体积下限：整页渲染失败会得到一张几乎全空的图，压缩后极小，
不用解码就能抓到。

> 如果差异页远多于你改动涉及的页面，多半是动到了 `Theme.swift` 里的共用组件。

### 3. iOS 与 watchOS 快照

两端合用一份脚本（流程九成相同，分两份必然漂移）：

```bash
xcrun simctl boot 'iPhone 17 Pro' && open -a Simulator
bash tools/snapshot-sim.sh ios --baseline
bash tools/snapshot-sim.sh ios --compare

xcrun simctl boot 'Apple Watch Series 11 (46mm)' && open -a Simulator
bash tools/snapshot-sim.sh watch --baseline
bash tools/snapshot-sim.sh watch --compare
```

| | 页面 | 外观 | 张数 |
|---|---|---|---|
| iOS | 5 个标签页 | 明 + 暗 | 10 |
| watchOS | 3 层（概览 / 想法 / 详情） | **只有暗** | 3 |

**这两端走的是模拟器真实截图，不是离屏渲染**——页面全是 `NavigationStack` +
`List` / `Form`，`ImageRenderer` 渲不出来。代价是需要一台已启动的对应平台模拟器。
切屏靠启动参数（iOS 是 `--tab`，watchOS 是 `--screen`），因为模拟器里注入不了点击。

watchOS 只截暗色，是因为**它没有浅色模式**（`simctl ui appearance light` 直接返回
"Operation not supported"）。

⚠️ **这两端的逐字节比对必然报差异**——截的是整块屏幕，状态栏时钟每分钟都在变。
那份清单只用来定位该看哪几张，不能只看计数。

## 三端不是一回事

同一个令牌在三端解析出不同的绝对字号，这是对的，各自遵循各自平台的规范。
全是 `preferredFont(forTextStyle:)` 的实测值，不是估的：

| 令牌 | macOS | iOS | watchOS |
|---|---|---|---|
| `Typo.metric`（`.largeTitle`） | 26 | 34 | **36** |
| `Typo.body` | 13 | 17 | 16 |
| `Typo.list`（`.callout`） | 12 | 16 | **16** |
| `Typo.hint`（`.subheadline`） | 11 | 15 | 15 |
| `Typo.micro`（`.footnote`） | 10 | 13 | 13 |

两个要当心的地方：

1. **`body` 与 `list` 在 watchOS 上都是 16，会撞在一起。** 手表上想区分正文与列表，
   光靠这两个令牌不够，得配字重或颜色。
2. **改令牌会同时影响三端，绝对幅度还不同。** 把 `hint` 调大一档，macOS 涨 1pt，
   iOS / watchOS 基数本来就更大。改完三边的快照都要看。

watchOS 的字号不随表盘尺寸变（40mm 与 46mm 实测完全相同）。

另外：**iOS 视图目前还没迁到令牌**，它们直接用 `.font(.caption)` 这类语义字体
（15 处），没有写死字号。要不要统一到令牌是个待定的设计决策——
统一会改变 iOS 的观感（`.caption` 在 iOS 是 12pt，而 `Typo.micro` 是 13pt）。
**watchOS 视图从一开始就全用令牌写的**，可以当参考样板。

## 手表端要先知道的事

**它是只读投影，不是第三个完整端。** 这不是设计取舍，是平台约束：

| | 状态 |
|---|---|
| EventKit 写入 | `save(_:commit:)` 标了 `@available(watchOS, unavailable)`，写不了 |
| iCloud Drive | 拿不到（`ubiquityIdentityToken` 运行时为 nil） |
| App Groups / CloudKit | 都要付费开发者账号 |
| WatchConnectivity | ✅ 可用，是免费账号下唯一的数据通道 |

因此手表 target 做成了 **iOS 应用的伴侣应用**（嵌在 iOS 产物的 `Watch/` 下，
Info.plist 声明 `WKCompanionAppBundleIdentifier`）——WatchConnectivity 要求如此。

⚠️ **但同步本身还没实现。** 手表现在读的是自己容器里的 vault，快照脚本会往里塞夹具。
所以你设计的手表界面**「在真机上真能拿到数据」这件事没有验证过**，
验证需要真机联调（模拟器上 WatchConnectivity 配对不可靠），而真机需要签名身份。

三层页面：概览（一屏看完，不用滚）→ 想法列表（按最近活动排序）→ 单条详情
（只放思路注释，不放正文——正文在表盘上读不动）。

## 开工前

```bash
# 1. 确认当前是干净的
cd apple/LifeWorkflowKit && swift test && swift run archmap-tool --repo ../.. --check

# 2. 立三份基线
cd ../.. && bash tools/snapshot.sh --baseline
bash tools/snapshot-sim.sh ios --baseline
bash tools/snapshot-sim.sh watch --baseline
```

## 收工前

```bash
cd apple/LifeWorkflowKit && swift build && swift test
swift run archmap-tool --repo ../.. --check
cd ../.. && bash tools/snapshot.sh --compare
bash tools/snapshot-sim.sh ios --compare
bash tools/snapshot-sim.sh watch --compare
```

`swift build` 要求**零警告**——CI 里 `grep warning:` 命中就失败。

## 已知的、留给你的活

1. **约 60 处间距不在刻度上**（1/3/5/6/7/9/10/11/14/18/60pt）。
   `ui-spacing-tokens` 会列出 file:line。归并会改布局，所以留给你按新设计决定。
2. **`pageTitle` / `sectionTitle` / `sidebarTitle` 还是固定字号**，
   因为语义档位（17 / 22）都会明显改变现有层级。
3. **iOS 视图未迁到令牌**（见上）。watchOS 视图已经全用令牌，可作样板。
4. **手表端的数据同步没实现**——界面能设计，但拿不到真数据（见上）。
5. **Python 桌面版（`lifeos/gui/`）完全不在这套系统里**，它有自己的 QSS 调色板。
