import SwiftUI
import LifeWorkflowKit

/// 今日：一屏回答「现在该推进什么」，外加一个随手记入口。
struct TodayView: View {
    @Environment(AppState.self) private var state
    @State private var quickText = ""
    @FocusState private var quickFocused: Bool

    /// 与快捷指令「今天该推进什么」用同一套逻辑，避免两处规则漂移
    private var toAdvance: [Item] {
        IdeaActions.todayFocus(state.items, limit: .max)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        TextField("随手记一条…", text: $quickText, axis: .vertical)
                            .lineLimit(1...4)
                            .focused($quickFocused)
                        Button {
                            Task { await capture() }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill").font(.title2)
                        }
                        .disabled(quickText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("快速捕获")
                }

                Section {
                    HStack {
                        stat("\(state.summary.total)", "想法")
                        Divider()
                        stat("\(state.summary.active)", "推进中")
                        Divider()
                        stat("\(state.summary.totalNotes)", "思路注释")
                        Divider()
                        stat("\(state.summary.streak)", "连续活跃")
                    }
                    .frame(maxWidth: .infinity)
                }

                Section("待推进") {
                    if toAdvance.isEmpty {
                        ContentUnavailableView("今天没有待推进的想法",
                                               systemImage: "checkmark.circle",
                                               description: Text("去「捕捉」记一条，或把某个种子推进到发芽"))
                    } else {
                        ForEach(toAdvance) { item in
                            NavigationLink {
                                IdeaDetailView(itemID: item.id)
                            } label: {
                                IdeaRow(item: item)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("推进") { Task { await advance(item) } }
                                    .tint(.green)
                            }
                        }
                    }
                }

                if !recentTrajectory.isEmpty {
                    Section("最近的思维轨迹") {
                        ForEach(Array(recentTrajectory.enumerated()), id: \.offset) { _, row in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Circle().fill(row.item.status.color).frame(width: 6, height: 6)
                                    Text(row.item.title).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(row.date).font(.caption2).foregroundStyle(Theme.faint)
                                }
                                Text(row.note).font(.callout)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("今日")
            .refreshable { await state.reload() }
        }
    }

    private var recentTrajectory: [(date: String, note: String, item: Item)] {
        Array(Stats.trajectory(state.items).prefix(5))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func capture() async {
        let text = quickText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if await state.capture(text) {
            quickText = ""
            quickFocused = false
        }
    }

    private func advance(_ item: Item) async {
        guard var target = state.items.first(where: { $0.id == item.id }) else { return }
        let result = IdeaActions.advance(&target)
        guard result.didAdvance else { state.notify(result.message); return }
        _ = await state.save(&target)
        state.notify(result.message)
    }
}

/// 想法列表行（iOS 版，触摸友好）
struct IdeaRow: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(item.status.color).frame(width: 7, height: 7)
                Text(item.title).font(.body).lineLimit(1)
                Spacer()
                if item.priority == .high {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption).foregroundStyle(item.priority.color)
                }
            }
            HStack(spacing: 8) {
                Text(item.lastActivity).font(.caption2).foregroundStyle(Theme.faint)
                if !item.thinkingNotes.isEmpty {
                    Label("\(item.thinkingNotes.count)", systemImage: "text.quote")
                        .font(.caption2).foregroundStyle(Theme.faint)
                }
                if let progress = item.progress, progress > 0 {
                    Text("\(progress)%").font(.caption2).foregroundStyle(Theme.faint)
                }
                ForEach(item.tags.prefix(2), id: \.self) { tag in
                    Text("#\(tag)").font(.caption2).foregroundStyle(Theme.accent)
                }
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }
}
