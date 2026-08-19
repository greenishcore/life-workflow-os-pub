import SwiftUI
import LifeWorkflowKit

/// 设计令牌。颜色只在这一处定义，页面里不写死。
enum Theme {
    static let cardRadius: CGFloat = 10
    static let pad: CGFloat = 16
    static let gap: CGFloat = 12

    static let accent = Color.accentColor
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let pageBackground = Color(nsColor: .windowBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let faint = Color.secondary.opacity(0.7)
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
        VStack(alignment: .leading, spacing: 10) {
            if !title.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    if !hint.isEmpty {
                        Text(hint).font(.system(size: 11)).foregroundStyle(Theme.faint)
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
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(color ?? .primary)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(delta).font(.system(size: 11)).foregroundStyle(Theme.faint)
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
            .font(.system(size: 11))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(filled ? .white : color)
            .background(filled ? color : color.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 5))
    }
}

struct TagChip: View {
    let text: String
    var body: some View {
        Text("#\(text)")
            .font(.system(size: 11))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
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
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 20, weight: .bold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) { actions }
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
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(Theme.faint)
            Text(title).font(.system(size: 13)).foregroundStyle(.secondary)
            if !hint.isEmpty {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faint)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
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
        .padding(20)
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
    }
}
