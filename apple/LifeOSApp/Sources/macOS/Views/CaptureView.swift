import SwiftUI
import LifeWorkflowKit

struct CaptureView: View {
    @Environment(AppState.self) private var state

    @State private var text = ""
    @State private var hint = ""
    @State private var reminderList = ""
    @State private var calendarName = ""
    @State private var includeDone = false
    @State private var days = 7
    @State private var log: [String] = []
    @State private var busy = false
    @State private var captures: [(date: String, lines: [String])] = []
    @FocusState private var editorFocused: Bool

    var body: some View {
        PageScaffold(destination: .capture) {
            EmptyView()
        } content: {
            captureCard
            appleCard
            recentCard
        }
        .task {
            reminderList = state.config.defaultReminderList
            calendarName = state.config.defaultCalendar
            await refreshCaptures()
        }
    }

    // MARK: 随手记

    private var captureCard: some View {
        Card(title: "随手记", hint: "⌘↩ 直接捕获到 Inbox") {
            TextEditor(text: $text)
                .font(Theme.Typo.body)
                .frame(minHeight: 110)
                .padding(6)
                .background(Theme.pageBackground, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
                .focused($editorFocused)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("突然想到的点子、待办、一句灵感…")
                            .font(Theme.Typo.body)
                            .foregroundStyle(Theme.faint)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }

            HStack {
                Text(hint).font(Theme.Typo.hint).foregroundStyle(Theme.faint)
                Spacer()
                Button("建为想法…") { Task { await promote() } }
                    .disabled(trimmed.isEmpty)
                Button("捕获到 Inbox") { Task { await capture() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(trimmed.isEmpty)
            }
        }
    }

    // MARK: Apple 导入

    private var appleCard: some View {
        Card(title: "从 Apple 导入", hint: "写入当天 Daily 笔记的对应段落") {
            HStack(spacing: 8) {
                TextField("提醒事项列表名", text: $reminderList).frame(width: 150)
                Toggle("含已完成", isOn: $includeDone)
                Button("导入提醒") { Task { await importReminders() } }.disabled(busy)

                Divider().frame(height: 18)

                TextField("日历名", text: $calendarName).frame(width: 110)
                Stepper("\(days) 天", value: $days, in: 1...60).frame(width: 100)
                Button("导入日程") { Task { await importEvents() } }.disabled(busy)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
            }

            Text("首次运行会申请权限：系统设置 → 隐私与安全性 → 提醒事项 / 日历")
                .font(Theme.Typo.hint).foregroundStyle(Theme.faint)

            if !log.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(Theme.Typo.mono)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(height: 84)
                .padding(8)
                .background(Theme.pageBackground, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: 最近捕获

    private var recentCard: some View {
        Card(title: "最近捕获", hint: "勾选 = 已处理；「→ 想法」把它提升为带状态机的想法") {
            if captures.isEmpty {
                EmptyStateView(symbol: "tray", title: "Inbox 还是空的",
                               hint: "在上面写一句话，⌘↩ 就能落到 Inbox/")
                    .frame(height: 130)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(captures, id: \.date) { group in
                        Text(group.date)
                            .font(Theme.Typo.hintStrong)
                            .foregroundStyle(.secondary)
                        ForEach(Array(group.lines.enumerated()), id: \.offset) { _, raw in
                            CaptureRow(date: group.date, raw: raw) { await refreshCaptures() }
                        }
                    }
                }
            }
        }
    }

    // MARK: 动作

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func capture() async {
        guard !trimmed.isEmpty else { return }
        if await state.capture(trimmed) {
            hint = "已捕获"
            text = ""
            await refreshCaptures()
        } else {
            hint = "捕获失败"
        }
    }

    private func promote() async {
        guard !trimmed.isEmpty else { return }
        if let item = await state.promoteToIdea(trimmed) {
            hint = "已建为想法"
            text = ""
            state.open(item)
        }
    }

    private func refreshCaptures() async {
        captures = await state.store.captureLog(days: 7)
    }

    // 只做派发：权限流程、取数、写入 Daily 都在 AppState.importFromApple，
    // 这样改这一页的排版碰不到 EventKit。
    private func importReminders() async {
        busy = true
        defer { busy = false }
        await state.importFromApple(
            kind: .reminders, listName: reminderList, days: days,
            includeCompleted: includeDone,
            log: { line in log.append(line) })
        await refreshCaptures()
    }

    private func importEvents() async {
        busy = true
        defer { busy = false }
        await state.importFromApple(
            kind: .events, listName: calendarName, days: days,
            includeCompleted: false,
            log: { line in log.append(line) })
        await refreshCaptures()
    }

    /// 写入当天 Daily 的对应段落（重复导入是替换，不是追加）
    private func write(section: String, content: String, label: String) async {
        let note = state.store.dailyNote()
        do {
            _ = try await state.store.upsertSection(at: note, heading: section, content: content)
            log.append("✅ \(label) → \(note.lastPathComponent) 的「## \(section)」段")
            state.notify("已导入 \(label)")
            await state.reload()
        } catch {
            log.append("❌ 写入失败：\(error.localizedDescription)")
        }
    }
}

/// Inbox 里的一行：勾选完成 / 提升为想法
private struct CaptureRow: View {
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

    /// 去掉行首的 "21:03 " 时间戳
    private var cleaned: String {
        let parts = content.split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2, parts[0].contains(":"), parts[0].count <= 5 { return parts[1] }
        return content
    }

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { isDone },
                set: { _ in Task { await toggle() } }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            Text(content)
                .font(Theme.Typo.list)
                .strikethrough(isDone)
                .foregroundStyle(isDone ? Theme.faint : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("→ 想法") { Task { await promote() } }
                .buttonStyle(.link)
                .font(Theme.Typo.hint)
                .help("提升为带状态机与思路注释的想法")
        }
    }

    private func toggle() async {
        _ = try? await state.store.toggleCaptureLine(date: date, rawLine: raw)
        await onChange()
    }

    private func promote() async {
        if let item = await state.promoteToIdea(cleaned) {
            _ = try? await state.store.toggleCaptureLine(date: date, rawLine: raw)
            await onChange()
            state.open(item)
        }
    }
}
