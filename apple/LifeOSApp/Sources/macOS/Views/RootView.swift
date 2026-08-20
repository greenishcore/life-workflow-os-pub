import SwiftUI
import LifeWorkflowKit

struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            List(selection: $state.selection) {
                ForEach(NavGroup.allCases) { group in
                    if group == .system {
                        Section { rows(for: group) }
                    } else {
                        Section(group.title) { rows(for: group) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 260)
            .safeAreaInset(edge: .top) { brand }
        } detail: {
            detail
                .safeAreaInset(edge: .bottom) { statusBar }
        }
    }

    @ViewBuilder
    private func rows(for group: NavGroup) -> some View {
        ForEach(group.destinations) { dest in
            Label(dest.title, systemImage: dest.symbol).tag(dest)
        }
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: Theme.Space.textLine) {
            Text("Life Workflow OS").font(Theme.Typo.sidebarTitle)
            Text("捕捉 → 整理 → 执行 → 复盘 → 归档")
                .font(Theme.Typo.micro)
                .foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.inlineWide)
        .padding(.bottom, Theme.Space.base)
    }

    @ViewBuilder
    private var detail: some View {
        switch state.selection {
        case .dashboard: DashboardView()
        case .archmap:   ArchMapView()
        case .capture:   CaptureView()
        case .ideas:     IdeasView()
        case .convert:   ConvertView()
        case .prompts:   PromptsView()
        case .logs:      LogsView()
        case .archive:   ArchiveView()
        case .settings:  SettingsView()
        }
    }

    private var statusBar: some View {
        HStack(spacing: Theme.Space.base) {
            if state.isLoading {
                ProgressView().controlSize(.small)
            }
            Text(state.statusMessage)
                .font(Theme.Typo.hint)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if state.conflictCount > 0 {
                // 冲突是数据风险，做成可点击的按钮直达处理入口，而不是一条静态提示
                Button {
                    state.selection = .settings
                } label: {
                    Label("\(state.conflictCount) 处同步冲突待处理",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Typo.hint)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help(state.attentionWarnings.map(\.message).joined(separator: "\n"))
            } else if !state.warnings.isEmpty {
                Label("\(state.warnings.count) 条提醒", systemImage: "info.circle")
                    .font(Theme.Typo.hint)
                    .foregroundStyle(Theme.faint)
                    .help(state.warnings.map(\.message).joined(separator: "\n"))
            }
            Text("\(state.items.count) 条记录")
                .font(Theme.Typo.hint)
                .foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, Theme.Space.inlineWide)
        .padding(.vertical, Theme.Space.inlineTight)
        .background(.bar)
    }
}
