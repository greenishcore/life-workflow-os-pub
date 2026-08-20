import SwiftUI
import LifeWorkflowKit

/// 手表端导航：概览 → 想法列表 → 单条详情，三层。
///
/// 用 `NavigationStack` 的层级导航而不是 iOS 那套底部标签栏：
/// 表盘太小，五个标签挤在一起点不准，而只读投影本来就是「看一眼 → 想细看再点进去」。
struct WatchRootView: View {
    @Environment(AppState.self) private var state

    /// `--screen ideas` / `--screen detail` 指定初始层级。
    ///
    /// 用途与 iOS 端的 `--tab` 一样：模拟器里注入不了点击，
    /// 自动化截图只能靠启动参数直接落到要拍的那一屏。
    enum Screen: String {
        case overview, ideas, detail

        static var launchArgument: Screen? {
            let args = CommandLine.arguments
            guard let i = args.firstIndex(of: "--screen"), i + 1 < args.count else { return nil }
            return Screen(rawValue: args[i + 1])
        }
    }

    var body: some View {
        NavigationStack {
            WatchOverviewView()
                .navigationDestination(isPresented: .constant(Screen.launchArgument == .ideas
                                                              || Screen.launchArgument == .detail)) {
                    WatchIdeasView()
                        .navigationDestination(isPresented: .constant(Screen.launchArgument == .detail)) {
                            if let first = state.items.first {
                                WatchIdeaDetailView(item: first)
                            }
                        }
                }
        }
    }
}

/// 第一层：一屏概览。抬腕就能看完，不需要滚动到底。
struct WatchOverviewView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
                    Text("\(state.summary.total)")
                        .font(Theme.Typo.metric)
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text("想法").font(Theme.Typo.list)
                        Text("推进中 \(state.summary.active) · 已完成 \(state.summary.done)")
                            .font(Theme.Typo.micro)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, Theme.Space.xs)
            }

            Section {
                WatchStatRow(label: "思路注释", value: "\(state.summary.totalNotes)",
                             hint: state.summary.total == 0 ? "—"
                                : String(format: "人均 %.1f 条",
                                         Double(state.summary.totalNotes) / Double(state.summary.total)))
                WatchStatRow(label: "连续活跃", value: "\(state.summary.streak)",
                             hint: state.summary.streak > 0 ? "天" : "今天还没记录")
                WatchStatRow(label: "跨度", value: "\(state.summary.spanDays)", hint: "天")
            }

            Section {
                NavigationLink {
                    WatchIdeasView()
                } label: {
                    Label("全部想法", systemImage: "lightbulb")
                        .font(Theme.Typo.list)
                }
            }
        }
        .navigationTitle("生活工作流")
    }
}

/// 概览里的一行统计。抽出来是因为三行结构一样，改样式只改一处。
struct WatchStatRow: View {
    let label: String
    let value: String
    var hint: String = ""

    var body: some View {
        HStack {
            Text(label).font(Theme.Typo.list)
            Spacer(minLength: Theme.Space.sm)
            Text(value).font(Theme.Typo.metricSmall)
            if !hint.isEmpty {
                Text(hint).font(Theme.Typo.micro).foregroundStyle(Theme.faint)
            }
        }
    }
}

/// 第二层：想法列表。按最近活动排序——手表上翻不了几屏，最该看的要在最前面。
struct WatchIdeasView: View {
    @Environment(AppState.self) private var state

    private var ordered: [Item] {
        state.items.sorted { ($0.lastActivity, $0.created) > ($1.lastActivity, $1.created) }
    }

    var body: some View {
        Group {
            if state.items.isEmpty {
                EmptyStateView(symbol: "lightbulb",
                               title: "还没有想法",
                               hint: "在 iPhone 或 Mac 上记一条")
            } else {
                List(ordered) { item in
                    NavigationLink {
                        WatchIdeaDetailView(item: item)
                    } label: {
                        WatchIdeaRow(item: item)
                    }
                }
            }
        }
        .navigationTitle("想法")
    }
}

struct WatchIdeaRow: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(item.title).font(Theme.Typo.list).lineLimit(2)
            HStack(spacing: Theme.Space.sm) {
                Badge(text: item.status.label, color: item.status.color)
                if let progress = item.progress, progress > 0 {
                    Text("\(progress)%").font(Theme.Typo.micro)
                        .foregroundStyle(Theme.faint)
                }
                Spacer(minLength: 0)
                Text(item.lastActivity.isEmpty ? item.created : item.lastActivity)
                    .font(Theme.Typo.micro)
                    .foregroundStyle(Theme.faint)
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

/// 第三层：单条详情。
///
/// 只放**思路注释**，不放正文——思路注释是这套系统里最独特的东西
/// （想法怎么一步步演进的），也最适合抬腕扫一眼；
/// 正文动辄几百字，在表盘上读不动，要读就去 iPhone。
struct WatchIdeaDetailView: View {
    let item: Item

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text(item.title).font(Theme.Typo.cardTitle)
                    HStack(spacing: Theme.Space.sm) {
                        Badge(text: item.status.label, color: item.status.color)
                        Badge(text: item.priority.label, color: item.priority.color)
                    }
                    if let progress = item.progress, progress > 0 {
                        ProgressView(value: Double(progress), total: 100)
                            .tint(item.status.color)
                    }
                }
                .padding(.vertical, Theme.Space.xs)
            }

            if item.thinkingNotes.isEmpty {
                Section {
                    Text("还没有思路注释").font(Theme.Typo.micro)
                        .foregroundStyle(Theme.faint)
                }
            } else {
                Section("思路轨迹") {
                    ForEach(Array(item.thinkingNotes.enumerated()), id: \.offset) { _, note in
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            Text(note.t).font(Theme.Typo.micro).foregroundStyle(Theme.faint)
                            Text(note.note).font(Theme.Typo.list)
                        }
                        .padding(.vertical, Theme.Space.xs)
                    }
                }
            }

            if !item.tags.isEmpty {
                Section {
                    HStack(spacing: Theme.Space.sm) {
                        ForEach(item.tags.prefix(3), id: \.self) { TagChip(text: $0) }
                    }
                }
            }
        }
        .navigationTitle(item.status.label)
    }
}
