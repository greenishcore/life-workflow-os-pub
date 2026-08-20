import SwiftUI
import LifeWorkflowKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 设计令牌。颜色只在这一处定义，页面里不写死。
///
/// 两端都用系统语义色而不是硬编码 hex：这样明暗主题、辅助功能的
/// 增强对比度、以及各平台自己的观感规范都自动跟随。
enum Theme {
    static let cardRadius: CGFloat = 10
    static let pad = Space.card
    static let gap = Space.block

    static let accent = Color.accentColor
    static let faint = Color.secondary.opacity(0.7)

    #if os(macOS)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let pageBackground = Color(nsColor: .windowBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    #elseif os(watchOS)
    // watchOS 上**所有自适应背景/分隔线语义色都不可用**（UIKit 头文件里
    // systemBackground / systemGroupedBackground / separator 都标了
    // API_UNAVAILABLE(watchos)），只剩固定色与 label 色。
    // 而且 watchOS 没有浅色模式，表盘永远是黑底，所以直接给定值即可，
    // 不需要「跟随主题」——这里不是偷懒，是平台本来就只有一种外观。
    static let cardBackground = Color.white.opacity(0.12)
    static let pageBackground = Color.black
    static let border = Color.white.opacity(0.2)
    #else
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let pageBackground = Color(uiColor: .systemGroupedBackground)
    static let border = Color(uiColor: .separator)
    #endif
}

// MARK: - 排版令牌

extension Theme {

    /// 排版令牌：按**用途**命名，不按字号命名。
    ///
    /// 存在的理由是**单一事实源**：迁移前全仓 154 处写死字号、21 种组合，
    /// 想把「次要说明」调大一号得翻 22 个文件。现在只改这里一处。
    /// 这是把界面设计交接出去的前提——接手方改令牌，不需要读遍所有视图。
    ///
    /// 绝大多数令牌映射到系统语义字体（`.body` / `.callout` / `.subheadline` / `.footnote`），
    /// 而不是固定字号，原因是本文件在 `Shared/` 里、两端共用：
    /// **iOS 上语义字体会跟随用户的动态字体设置，固定字号不会。**
    ///
    /// 但别指望 macOS 也有这个好处——**macOS 没有动态字体**。实测：
    /// `NSFont.preferredFont(forTextStyle: .body)` 恒为 13.0，
    /// 给视图加 `.dynamicTypeSize(.accessibility5)` 渲染结果一个像素都不变。
    /// 所以在 macOS 上换语义字体是**中性**的，好处只在 iOS 侧兑现。
    ///
    /// 换过去不改观感——实测 macOS 的语义字号正好是这几个值：
    /// `.body` 13 · `.callout` 12 · `.subheadline` 11 · `.footnote` 10 · `.largeTitle` 26，
    /// 与迁移前逐点相同（18 张页面快照里 10 张逐字节一致，其余 8 张只有亚像素级栅格差，
    /// 墨迹包围盒完全不变，即字形位置没动）。
    ///
    /// 注意 `.headline` 是 **Bold** 而非 semibold，所以「13 号半粗」用
    /// `.body.weight(.semibold)` 而不是 `.headline`。
    ///
    /// 少数标了「固定」的令牌保留精确字号，各自注明了原因。
    enum Typo {

        // MARK: 标题

        /// 页面大标题。固定：语义档位在 17（`.title2`）与 22（`.title`）之间跳，
        /// 都会明显改变现有层级，交由接手方按新设计定夺。
        static let pageTitle = Font.system(size: 20, weight: .bold)
        /// 区块小标题。固定，理由同 `pageTitle`。
        static let sectionTitle = Font.system(size: 18, weight: .semibold)
        /// 侧边栏应用名。固定：它是品牌标识，不参与正文层级。
        static let sidebarTitle = Font.system(size: 14, weight: .bold)
        /// 卡片标题（13 半粗）
        static let cardTitle = Font.body.weight(.semibold)

        // MARK: 正文

        /// 正文（13）
        static let body = Font.body
        /// 列表与表格文字（12）
        static let list = Font.callout
        static let listStrong = Font.callout.weight(.semibold)
        /// 次要说明、徽章、标签（11）——全仓用得最多的一档
        static let hint = Font.subheadline
        static let hintStrong = Font.subheadline.weight(.semibold)
        static let hintMedium = Font.subheadline.weight(.medium)
        /// 更小的辅助文字、分组标题（10）
        static let micro = Font.footnote
        static let microStrong = Font.footnote.weight(.semibold)
        static let microMedium = Font.footnote.weight(.medium)

        // MARK: 数字

        /// KPI 大数字（26 粗体圆角）
        static let metric = Font.system(.largeTitle, design: .rounded).weight(.bold)
        /// 卡片内小数字（13 粗体圆角）
        static let metricSmall = Font.system(.body, design: .rounded).weight(.bold)

        // MARK: 等宽（路径、哈希、时间戳、数值对齐）

        static let mono = Font.system(.subheadline, design: .monospaced)      // 11
        static let monoSmall = Font.system(.footnote, design: .monospaced)    // 10
        static let monoList = Font.system(.callout, design: .monospaced)      // 12

        // MARK: 固定字号

        /// 图表坐标刻度。固定：绘图区尺寸是算出来的，刻度字号必须可预测。
        static let axis = Font.system(size: 9)
        /// 空态大图标。固定：它是图形不是文字。
        static let emptySymbol = Font.system(size: 30)
        /// 单处使用的大号数字（架构地图的模块计数）
        static let display = Font.system(size: 22)
    }

    /// 间距刻度。**是从全仓实际用法里量出来的，不是拍脑袋定的。**
    ///
    /// 统计结果：纵向（`VStack(spacing:)`）用 2 / 4；横向（`HStack(spacing:)`）
    /// 用 6 / 10 / 14 这条 4pt 阶梯；容器内边距用 8 / 12 / 16 / 20。
    ///
    /// 按**用途**命名而不是 xs / sm / md：这实际是一把 2pt 的梯子，
    /// 用 t 恤尺码命名只会退化成「给数字换个名字」，说不清 6 和 8 该用哪个。
    ///
    /// 历史教训：这把刻度第一版只收了 2/4/8/12/16/20，是从「已经在用的取值」里
    /// 挑的——但挑的时候只统计了恰好落在预设值上的那些，属于循环论证，
    /// 结果把 6/10/14 这条完整的横向阶梯整个漏掉，让约束误报了 39 处。
    enum Space {
        /// 2 — 同一组内两行文字之间
        static let textLine: CGFloat = 2
        /// 4 — 紧凑元素之间
        static let tight: CGFloat = 4
        /// 6 — 行内小元素（徽章、标签）之间
        static let inlineTight: CGFloat = 6
        /// 8 — 最常用：小容器内边距、一般间隙
        static let base: CGFloat = 8
        /// 10 — 行内中等元素之间
        static let inline: CGFloat = 10
        /// 12 — 卡片之间
        static let block: CGFloat = 12
        /// 14 — 行内宽间隔（并列的信息组）
        static let inlineWide: CGFloat = 14
        /// 16 — 卡片内边距
        static let card: CGFloat = 16
        /// 20 — 页面内边距
        static let page: CGFloat = 20
    }

    /// **不是设计间距**，是为了让开系统控件或绘图区而留的固定量。
    ///
    /// 单独放一处，是因为把它们混进 `Space` 会有两个坏处：
    /// 既会被「间距应落在刻度上」的约束误报，
    /// 也会让接手方以为调这两个数属于调间距——它们各自跟着别的东西走。
    enum Layout {
        /// iOS 底部标签栏的高度余量：浮层提示要浮在它上面，不是设计间距
        static let tabBarClearance: CGFloat = 60
        /// 图表绘图区右侧留白：给最后一个刻度标签让位，跟着 `Typo.axis` 走
        static let chartTrailingInset: CGFloat = 18
    }
}

extension Color {
    /// 从 `#rrggbb` 构造。模型层用十六进制串携带状态色，避免核心包依赖 SwiftUI。
    init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt64(cleaned, radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension Status {
    var color: Color { Color(hex: colorHex) }
}

extension Priority {
    var color: Color { Color(hex: colorHex) }
}

extension RunLog.Status {
    var color: Color { Color(hex: colorHex) }
}

// MARK: - 复用组件

/// 带标题的卡片容器
struct Card<Content: View>: View {
    let title: String
    var hint: String = ""
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.inline) {
            if !title.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.base) {
                    Text(title).font(Theme.Typo.cardTitle)
                    if !hint.isEmpty {
                        Text(hint).font(Theme.Typo.hint).foregroundStyle(Theme.faint)
                    }
                    Spacer(minLength: 0)
                }
            }
            content
        }
        .padding(Theme.pad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

/// KPI 数字块
struct StatTile: View {
    let label: String
    let value: String
    var delta: String = ""
    var color: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.textLine) {
            Text(value)
                .font(Theme.Typo.metric)
                .foregroundStyle(color ?? .primary)
            Text(label).font(Theme.Typo.hint).foregroundStyle(.secondary)
            Text(delta).font(Theme.Typo.hint).foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(Theme.pad)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1)
        )
    }
}

/// 状态 / 优先级色标签
struct Badge: View {
    let text: String
    let color: Color
    var filled = false

    var body: some View {
        Text(text)
            .font(Theme.Typo.hint)
            .padding(.horizontal, Theme.Space.base)
            .padding(.vertical, Theme.Space.textLine)
            .foregroundStyle(filled ? .white : color)
            .background(filled ? color : color.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 5))
    }
}

struct TagChip: View {
    let text: String
    var body: some View {
        Text("#\(text)")
            .font(Theme.Typo.hint)
            .padding(.horizontal, Theme.Space.inlineTight)
            .padding(.vertical, Theme.Space.textLine)
            .foregroundStyle(Theme.accent)
            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}

/// 页面标题栏
struct PageHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Theme.Space.textLine) {
                Text(title).font(Theme.Typo.pageTitle)
                Text(subtitle).font(Theme.Typo.list).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: Theme.Space.base) { actions }
        }
    }
}

/// 空态提示
struct EmptyStateView: View {
    let symbol: String
    let title: String
    var hint: String = ""
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Space.base) {
            Image(systemName: symbol)
                .font(Theme.Typo.emptySymbol)
                .foregroundStyle(Theme.faint)
            Text(title).font(Theme.Typo.body).foregroundStyle(.secondary)
            if !hint.isEmpty {
                Text(hint)
                    .font(Theme.Typo.hint)
                    .foregroundStyle(Theme.faint)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, Theme.Space.tight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.page)
    }
}

/// 快照模式标记。
///
/// ImageRenderer 不会给 ScrollView 里的内容做布局（渲染出来是空白），
/// 所以离屏快照时改用固定高度的 VStack。这个开关只影响截图，不影响真实交互。
private struct SnapshotModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isSnapshotting: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}

/// 页面统一外框：标题 + 可滚动内容
struct PageScaffold<Actions: View, Content: View>: View {
    let destination: Destination
    var subtitleOverride: String?
    @ViewBuilder let actions: Actions
    @ViewBuilder let content: Content

    @Environment(\.isSnapshotting) private var isSnapshotting

    private var inner: some View {
        VStack(alignment: .leading, spacing: Theme.gap + 2) {
            PageHeader(title: destination.title,
                       subtitle: subtitleOverride ?? destination.subtitle) { actions }
            content
            if isSnapshotting { Spacer(minLength: 0) }
        }
        .padding(Theme.Space.page)
    }

    var body: some View {
        Group {
            if isSnapshotting {
                inner.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView { inner }
            }
        }
        .background(Theme.pageBackground)
    }
}


/// 正常模式用 HSplitView（可拖动分栏），快照模式退化为 HStack。
///
/// HSplitView / NavigationSplitView 都是 AppKit 支撑的容器，
/// ImageRenderer 渲染它们只会得到一个「禁止」占位图。
struct SplitOrStack<Left: View, Right: View>: View {
    let isSnapshotting: Bool
    var leftWidth: CGFloat = 340
    @ViewBuilder let left: Left
    @ViewBuilder let right: Right

    var body: some View {
        #if os(macOS)
        if isSnapshotting {
            HStack(spacing: 0) {
                left.frame(width: leftWidth)
                Divider()
                right.frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            HSplitView {
                left.frame(minWidth: 280, idealWidth: leftWidth, maxWidth: 480)
                right.frame(minWidth: 420)
            }
        }
        #else
        HStack(spacing: 0) {
            left.frame(width: leftWidth)
            Divider()
            right.frame(maxWidth: .infinity, alignment: .topLeading)
        }
        #endif
    }
}
