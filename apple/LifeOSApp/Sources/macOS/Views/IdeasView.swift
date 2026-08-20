import SwiftUI
import LifeWorkflowKit

struct IdeasView: View {
    @Environment(AppState.self) private var state
    @Environment(\.isSnapshotting) private var isSnapshotting

    @State private var search = ""
    @State private var statusFilter: Status?
    @State private var typeFilter: ItemType?
    @State private var selectedID: String?
    @State private var draft: Item?
    @State private var isDirty = false
    @State private var showDeleteConfirm = false

    private var filtered: [Item] {
        state.items
            .filter { statusFilter == nil || $0.status == statusFilter }
            .filter { typeFilter == nil || $0.type == typeFilter }
            .filter { $0.matches(search) }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    var body: some View {
        SplitOrStack(isSnapshotting: isSnapshotting, leftWidth: 330) {
            listPane
        } right: {
            editorPane
        }
        .background(Theme.pageBackground)
        .onAppear { syncSelection() }
        .onChange(of: state.items.count) { _, _ in syncSelection() }
        .onChange(of: state.pendingItemID) { _, id in
            guard let id else { return }
            selectedID = id
            loadDraft()
            state.pendingItemID = nil
        }
        .onChange(of: state.pendingNewItem) { _, pending in
            guard pending else { return }
            state.pendingNewItem = false
            Task { await createNew() }
        }
        .onChange(of: selectedID) { _, _ in loadDraft() }
    }

    // MARK: 左：列表

    private var listPane: some View {
        VStack(spacing: Theme.Space.base) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.faint)
                TextField("搜索标题 / 标签 / 思路注释 / 正文…", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(Theme.Space.base)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: Theme.Space.inlineTight) {
                Picker("", selection: $statusFilter) {
                    Text("全部状态").tag(Status?.none)
                    ForEach(Status.allCases, id: \.self) { Text($0.label).tag(Status?.some($0)) }
                }
                Picker("", selection: $typeFilter) {
                    Text("全部类型").tag(ItemType?.none)
                    ForEach(ItemType.allCases, id: \.self) { Text($0.label).tag(ItemType?.some($0)) }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if filtered.isEmpty {
                EmptyStateView(symbol: "lightbulb", title: "没有匹配的想法",
                               hint: search.isEmpty ? "按 ⌘N 新建一条" : "换个关键词试试")
            } else if isSnapshotting {
                // ImageRenderer 不渲染 List，快照时改用普通堆叠
                VStack(spacing: Theme.Space.textLine) {
                    ForEach(filtered.prefix(8)) { ItemRow(item: $0, selected: $0.id == selectedID) }
                    Spacer(minLength: 0)
                }
            } else {
                List(filtered, selection: $selectedID) { item in
                    ItemRow(item: item, selected: item.id == selectedID).tag(item.id)
                }
                .listStyle(.inset)
            }

            HStack {
                Text("显示 \(filtered.count) / 共 \(state.items.count) 条")
                    .font(Theme.Typo.hint).foregroundStyle(Theme.faint)
                Spacer()
                Button { Task { await createNew() } } label: {
                    Label("新建", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .padding(Theme.Space.block)
    }

    // MARK: 右：编辑器

    @ViewBuilder
    private var editorPane: some View {
        if let binding = draftBinding {
            ScrollViewOrStack(isSnapshotting: isSnapshotting) {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    TextField("想法标题", text: binding.title)
                        .textFieldStyle(.plain)
                        .font(Theme.Typo.sectionTitle)
                        .padding(Theme.Space.base)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 6))
                        .onChange(of: binding.wrappedValue.title) { _, _ in isDirty = true }

                    attributesCard(binding)
                    thinkingNotesCard(binding)
                    nextActionsCard(binding)
                    bodyCard(binding)
                    actionsRow(binding)
                }
                .padding(Theme.Space.card)
            }
        } else {
            EmptyStateView(symbol: "lightbulb", title: "还没有选中任何想法",
                           hint: "从左边挑一条，或按 ⌘N 新建",
                           actionTitle: "新建想法") { Task { await createNew() } }
        }
    }

    private func attributesCard(_ item: Binding<Item>) -> some View {
        Card(title: "属性") {
            HStack(spacing: Theme.Space.inlineWide) {
                labeled("状态") {
                    Picker("", selection: item.status) {
                        ForEach(Status.allCases, id: \.self) { s in
                            Label(s.label, systemImage: "circle.fill").tag(s)
                        }
                    }.labelsHidden().frame(width: 110)
                }
                labeled("优先级") {
                    Picker("", selection: item.priority) {
                        ForEach(Priority.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.labelsHidden().frame(width: 80)
                }
                labeled("类型") {
                    Picker("", selection: item.type) {
                        ForEach(ItemType.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.labelsHidden().frame(width: 90)
                }
                Spacer()
            }

            HStack(spacing: Theme.Space.card) {
                labeled("精力") {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(item.wrappedValue.energy ?? 0) },
                            set: { item.wrappedValue.energy = Int($0); isDirty = true }
                        ), in: 0...10, step: 1)
                        Text("\(item.wrappedValue.energy ?? 0)")
                            .font(Theme.Typo.monoList)
                            .frame(width: 22)
                    }
                }
                labeled("进度") {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(item.wrappedValue.progress ?? 0) },
                            set: { item.wrappedValue.progress = Int($0); isDirty = true }
                        ), in: 0...100, step: 5)
                        Text("\(item.wrappedValue.progress ?? 0)%")
                            .font(Theme.Typo.monoList)
                            .frame(width: 38)
                    }
                }
            }

            labeled("标签") {
                TextField("用逗号分隔：life, workflow, pkms", text: Binding(
                    get: { item.wrappedValue.tags.joined(separator: ", ") },
                    set: {
                        item.wrappedValue.tags = $0.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        isDirty = true
                    }
                ))
            }

            Text(metaLine(item.wrappedValue))
                .font(Theme.Typo.hint).foregroundStyle(Theme.faint)
                .textSelection(.enabled)
        }
    }

    private func thinkingNotesCard(_ item: Binding<Item>) -> some View {
        Card(title: "思路注释（思维轨迹）",
             hint: "记录「为什么想到它、想法怎么变的」——复盘时看的是过程，不只是结论") {
            if item.wrappedValue.thinkingNotes.isEmpty {
                Text("还没有思路注释。第一条建议写「为什么会想到这个」。")
                    .font(Theme.Typo.list).foregroundStyle(Theme.faint)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(item.wrappedValue.thinkingNotes.enumerated()), id: \.element.id) { index, note in
                        HStack(alignment: .top, spacing: Theme.Space.inline) {
                            // 时间轴：竖线 + 节点
                            VStack(spacing: 0) {
                                Circle().fill(Theme.accent).frame(width: 6, height: 6).padding(.top, Theme.Space.inlineTight)
                                if index < item.wrappedValue.thinkingNotes.count - 1 {
                                    Rectangle().fill(Theme.border).frame(width: 1)
                                }
                            }
                            .frame(width: 6)

                            Text(note.t)
                                .font(Theme.Typo.mono)
                                .foregroundStyle(Theme.faint)
                                .frame(width: 72, alignment: .leading)
                                .padding(.top, Theme.Space.textLine)

                            Text(note.note)
                                .font(Theme.Typo.list)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, Theme.Space.textLine)

                            Button {
                                item.wrappedValue.thinkingNotes.removeAll { $0.id == note.id }
                                isDirty = true
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.faint)
                            }
                            .buttonStyle(.borderless)
                            .help("删除这条注释")
                        }
                        .padding(.vertical, Theme.Space.textLine)
                    }
                }
            }

            AddNoteField { text in
                item.wrappedValue.thinkingNotes.append(ThinkingNote(note: text))
                isDirty = true
            }
        }
    }

    private func nextActionsCard(_ item: Binding<Item>) -> some View {
        Card(title: "下一步（Next Actions）", hint: "一行一条") {
            TextEditor(text: Binding(
                get: { item.wrappedValue.nextActions.joined(separator: "\n") },
                set: {
                    item.wrappedValue.nextActions = $0.components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    isDirty = true
                }
            ))
            .font(Theme.Typo.list)
            .frame(height: 64)
            .padding(Theme.Space.tight)
            .background(Theme.pageBackground, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
        }
    }

    private func bodyCard(_ item: Binding<Item>) -> some View {
        Card(title: "正文（Markdown）") {
            TextEditor(text: Binding(
                get: { item.wrappedValue.body },
                set: { item.wrappedValue.body = $0; isDirty = true }
            ))
            .font(Theme.Typo.monoList)
            .frame(minHeight: 150)
            .padding(Theme.Space.tight)
            .background(Theme.pageBackground, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
        }
    }

    private func actionsRow(_ item: Binding<Item>) -> some View {
        HStack {
            if isDirty {
                Label("未保存的修改", systemImage: "circle.fill")
                    .font(Theme.Typo.hint).foregroundStyle(.orange)
            }
            Spacer()
            Button("在访达中显示") {
                if let url = item.wrappedValue.url {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            .disabled(item.wrappedValue.url == nil)

            Button("归档") { Task { await archive() } }
            Button("删除") { showDeleteConfirm = true }
                .foregroundStyle(.red)
            Button("保存") { Task { await save() } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
        }
        .confirmationDialog(
            "把「\(item.wrappedValue.title)」移到回收站？",
            isPresented: $showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("移到回收站", role: .destructive) { Task { await delete() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("不是永久删除，可以从 vault 的 .trash/ 找回。")
        }
    }

    // MARK: 辅助

    private var draftBinding: Binding<Item>? {
        guard draft != nil else { return nil }
        return Binding(
            get: { draft ?? Item() },
            set: { draft = $0; isDirty = true }
        )
    }

    private func labeled<V: View>(_ title: String, @ViewBuilder content: () -> V) -> some View {
        HStack(spacing: Theme.Space.inlineTight) {
            Text(title).font(Theme.Typo.list).foregroundStyle(.secondary)
            content()
        }
    }

    private func metaLine(_ item: Item) -> String {
        var parts = ["id \(item.id)", "创建 \(item.created)"]
        if !item.updated.isEmpty { parts.append("更新 \(item.updated)") }
        if let url = item.url { parts.append(url.lastPathComponent) }
        if let root = item.rootID { parts.append("根：\(root)") }
        return parts.joined(separator: "   ·   ")
    }

    private func syncSelection() {
        if selectedID == nil || !state.items.contains(where: { $0.id == selectedID }) {
            selectedID = filtered.first?.id
        }
        loadDraft()
    }

    private func loadDraft() {
        draft = state.items.first { $0.id == selectedID }
        isDirty = false
    }

    private func save() async {
        guard var item = draft else { return }
        if await state.save(&item) {
            draft = item
            isDirty = false
        }
    }

    private func createNew() async {
        do {
            let item = try await state.store.create(title: "未命名想法")
            await state.reload()
            selectedID = item.id
            loadDraft()
            state.notify("已新建想法，改个标题吧")
        } catch {
            state.notify("新建失败：\(error.localizedDescription)")
        }
    }

    private func archive() async {
        guard var item = draft else { return }
        await state.archive(&item)
        draft = item
        isDirty = false
    }

    private func delete() async {
        guard let item = draft else { return }
        await state.delete(item)
        selectedID = nil
        draft = nil
    }
}

// MARK: - 子视图

private struct ItemRow: View {
    let item: Item
    let selected: Bool

    var body: some View {
        HStack(spacing: Theme.Space.base) {
            VStack(alignment: .leading, spacing: Theme.Space.textLine) {
                HStack(spacing: Theme.Space.inlineTight) {
                    Circle().fill(item.status.color).frame(width: 7, height: 7)
                    Text(item.title)
                        .font(Theme.Typo.cardTitle)
                        .lineLimit(1)
                }
                HStack(spacing: Theme.Space.tight) {
                    Text(item.lastActivity)
                        .font(Theme.Typo.mono)
                        .foregroundStyle(Theme.faint)
                    if !item.thinkingNotes.isEmpty {
                        Text("✎\(item.thinkingNotes.count)")
                            .font(Theme.Typo.hint).foregroundStyle(Theme.faint)
                            .help("\(item.thinkingNotes.count) 条思路注释")
                    }
                    ForEach(item.tags.prefix(2), id: \.self) { TagChip(text: $0) }
                    Spacer(minLength: 0)
                }
            }
            if item.priority == .high { Badge(text: "高", color: item.priority.color) }
            ProgressRing(value: item.progress ?? 0)
        }
        .padding(.vertical, Theme.Space.tight)
        .contentShape(Rectangle())
    }
}

private struct ProgressRing: View {
    let value: Int

    var body: some View {
        ZStack {
            Circle().stroke(Theme.border, lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(value) / 100)
                .stroke(Theme.accent, style: .init(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(value)").font(Theme.Typo.axis).foregroundStyle(.secondary)
        }
        .frame(width: 30, height: 30)
    }
}

/// 回车即添加一条思路注释
private struct AddNoteField: View {
    let onAdd: (String) -> Void
    @State private var text = ""

    var body: some View {
        HStack(spacing: Theme.Space.base) {
            TextField("补一条思路…（回车添加，自动记今天的日期）", text: $text)
                .onSubmit(add)
            Button("添加", action: add).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func add() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        onAdd(t)
        text = ""
    }
}

/// 正常模式用 ScrollView，快照模式用 VStack（ImageRenderer 不给 ScrollView 布局）
struct ScrollViewOrStack<Content: View>: View {
    let isSnapshotting: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if isSnapshotting {
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView { content }
        }
    }
}
