import SwiftUI
import LifeWorkflowKit

/// 捕捉：大输入框 + Inbox 清单 + 一键提升为想法。
/// iOS 上不做格式转换、git、Apple 便签（调研已确认这三件在 iOS 上不可行或做不好）。
struct CaptureView: View {
    @Environment(AppState.self) private var state

    @State private var text = ""
    @State private var captures: [(date: String, lines: [String])] = []
    @State private var importing = false
    @State private var importLog = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("突然想到的点子、待办、一句灵感…", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($focused)
                    HStack {
                        Button("建为想法") { Task { await promote() } }
                            .buttonStyle(.bordered)
                            .disabled(trimmed.isEmpty)
                        Spacer()
                        Button("捕获到 Inbox") { Task { await capture() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(trimmed.isEmpty)
                    }
                } header: {
                    Text("随手记")
                } footer: {
                    Text("落到 vault 的 Inbox/当天.md，和 Mac 端是同一份数据")
                }

                Section {
                    Button {
                        Task { await importReminders() }
                    } label: {
                        Label("导入提醒事项到今天", systemImage: "checklist")
                    }
                    .disabled(importing)
                    Button {
                        Task { await importEvents() }
                    } label: {
                        Label("导入未来 7 天日程", systemImage: "calendar")
                    }
                    .disabled(importing)
                    if !importLog.isEmpty {
                        Text(importLog).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("从 Apple 导入")
                } footer: {
                    Text("写入当天 Daily 笔记的对应段落；重复导入是替换，不会越堆越多。\nApple 便签没有公开 API，iOS 上无法读取——请用「分享」把内容发到本应用。")
                }

                Section("最近捕获") {
                    if captures.isEmpty {
                        ContentUnavailableView("Inbox 还是空的", systemImage: "tray")
                    } else {
                        ForEach(captures, id: \.date) { group in
                            ForEach(Array(group.lines.enumerated()), id: \.offset) { _, raw in
                                CaptureLineRow(date: group.date, raw: raw) {
                                    await refresh()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("捕捉")
            .refreshable { await refresh() }
            .task { await refresh() }
        }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func capture() async {
        guard !trimmed.isEmpty else { return }
        if await state.capture(trimmed) {
            text = ""
            focused = false
            await refresh()
        }
    }

    private func promote() async {
        guard !trimmed.isEmpty else { return }
        if await state.promoteToIdea(trimmed) != nil {
            text = ""
            focused = false
            await refresh()
        }
    }

    private func refresh() async {
        captures = await state.store.captureLog(days: 7)
    }

    // 只做派发：权限流程、取数、写入 Daily 都在 AppState.importFromApple，
    // 与 macOS 端共用同一份实现。
    private func importReminders() async {
        await runImport(.reminders, listName: state.config.defaultReminderList)
    }

    private func importEvents() async {
        await runImport(.events, listName: state.config.defaultCalendar)
    }

    private func runImport(_ kind: AppleImportKind, listName: String) async {
        importing = true
        defer { importing = false }
        await state.importFromApple(
            kind: kind, listName: listName, days: 7, includeCompleted: false,
            log: { line in importLog = line })
        await refresh()
    }

}

private struct CaptureLineRow: View {
    @Environment(AppState.self) private var state
    let date: String
    let raw: String
    let onChange: () async -> Void

    private var isDone: Bool { raw.hasPrefix("- [x]") }

    private var content: String {
        for prefix in ["- [x] ", "- [ ] ", "- "] where raw.hasPrefix(prefix) {
            return String(raw.dropFirst(prefix.count))
        }
        return raw
    }

    private var cleaned: String {
        let parts = content.split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2, parts[0].contains(":"), parts[0].count <= 5 { return parts[1] }
        return content
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    _ = try? await state.store.toggleCaptureLine(date: date, rawLine: raw)
                    await onChange()
                }
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isDone ? Color.accentColor : Theme.faint)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(content)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? Theme.faint : .primary)
                Text(date).font(.caption2).foregroundStyle(Theme.faint)
            }
            Spacer()
        }
        .swipeActions(edge: .trailing) {
            Button("→ 想法") {
                Task {
                    if await state.promoteToIdea(cleaned) != nil {
                        _ = try? await state.store.toggleCaptureLine(date: date, rawLine: raw)
                        await onChange()
                    }
                }
            }
            .tint(.orange)
        }
    }
}
