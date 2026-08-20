import SwiftUI
import LifeWorkflowKit

struct IdeasView: View {
    @Environment(AppState.self) private var state
    @State private var search = ""
    @State private var statusFilter: Status?

    private var filtered: [Item] {
        state.items
            .filter { statusFilter == nil || $0.status == statusFilter }
            .filter { $0.matches(search) }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    var body: some View {
        NavigationStack {
            List {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        search.isEmpty ? "还没有想法" : "没有匹配的想法",
                        systemImage: "lightbulb",
                        description: Text(search.isEmpty ? "去「捕捉」记一条" : "换个关键词试试"))
                } else {
                    ForEach(filtered) { item in
                        NavigationLink {
                            IdeaDetailView(itemID: item.id)
                        } label: {
                            IdeaRow(item: item)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "搜索标题 / 标签 / 思路注释 / 正文")
            .navigationTitle("想法")
            .refreshable { await state.reload() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("全部状态") { statusFilter = nil }
                        Divider()
                        ForEach(Status.allCases, id: \.self) { s in
                            Button(s.label) { statusFilter = s }
                        }
                    } label: {
                        Label(statusFilter?.label ?? "筛选",
                              systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            if let item = try? await state.store.create(title: "未命名想法") {
                                await state.reload()
                                state.notify("已新建「\(item.title)」")
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

/// 想法详情：五个维度全可编辑 + 思路注释时间轴。
///
/// 用 itemID 而不是 Item 值：列表刷新后要拿到最新副本，
/// 否则编辑的是过期快照，保存时会覆盖掉别处的改动。
struct IdeaDetailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    let itemID: String

    @State private var draft: Item?
    @State private var isDirty = false
    @State private var newNote = ""
    @State private var showDelete = false

    var body: some View {
        Group {
            if let binding = draftBinding {
                Form {
                    Section {
                        TextField("标题", text: binding.title, axis: .vertical)
                            .font(.headline)
                    }

                    Section("属性") {
                        Picker("状态", selection: binding.status) {
                            ForEach(Status.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        Picker("优先级", selection: binding.priority) {
                            ForEach(Priority.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        stepperRow("精力", value: Binding(
                            get: { binding.wrappedValue.energy ?? 0 },
                            set: { binding.wrappedValue.energy = $0 }
                        ), range: 0...10, suffix: "")
                        stepperRow("进度", value: Binding(
                            get: { binding.wrappedValue.progress ?? 0 },
                            set: { binding.wrappedValue.progress = $0 }
                        ), range: 0...100, step: 5, suffix: "%")
                        HStack {
                            Text("标签")
                            TextField("逗号分隔", text: Binding(
                                get: { binding.wrappedValue.tags.joined(separator: ", ") },
                                set: {
                                    binding.wrappedValue.tags = $0.split(separator: ",")
                                        .map { $0.trimmingCharacters(in: .whitespaces) }
                                        .filter { !$0.isEmpty }
                                }
                            ))
                            .multilineTextAlignment(.trailing)
                        }
                    }

                    Section {
                        ForEach(binding.wrappedValue.thinkingNotes) { note in
                            VStack(alignment: .leading, spacing: Theme.Space.textLine) {
                                Text(note.t).font(.caption2).foregroundStyle(Theme.faint)
                                Text(note.note).font(.callout)
                            }
                            .swipeActions {
                                Button("删除", role: .destructive) {
                                    binding.wrappedValue.thinkingNotes.removeAll { $0.id == note.id }
                                    isDirty = true
                                }
                            }
                        }
                        HStack {
                            TextField("补一条思路…", text: $newNote, axis: .vertical)
                            Button {
                                addNote(binding)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                            .disabled(newNote.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } header: {
                        Text("思路注释（思维轨迹）")
                    } footer: {
                        Text("记录「为什么想到它、想法怎么变的」——复盘时看的是过程，不只是结论")
                    }

                    Section("下一步") {
                        TextEditor(text: Binding(
                            get: { binding.wrappedValue.nextActions.joined(separator: "\n") },
                            set: {
                                binding.wrappedValue.nextActions = $0.components(separatedBy: "\n")
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty }
                            }
                        ))
                        .frame(minHeight: 60)
                    }

                    Section("正文") {
                        TextEditor(text: binding.body)
                            .font(.system(.callout, design: .monospaced))
                            .frame(minHeight: 140)
                    }

                    Section {
                        Button("归档", systemImage: "archivebox") {
                            Task { await archive() }
                        }
                        Button("删除", systemImage: "trash", role: .destructive) {
                            showDelete = true
                        }
                    } footer: {
                        if let url = binding.wrappedValue.url {
                            Text(url.lastPathComponent).font(.caption2)
                        }
                    }
                }
                .onChange(of: draft) { _, _ in isDirty = true }
            } else {
                ContentUnavailableView("找不到这条想法", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(draft?.title ?? "想法")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { Task { await save() } }
                    .disabled(!isDirty)
                    .fontWeight(isDirty ? .semibold : .regular)
            }
        }
        .confirmationDialog("移到回收站？", isPresented: $showDelete, titleVisibility: .visible) {
            Button("移到回收站", role: .destructive) { Task { await delete() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("不是永久删除，可以从 vault 的 .trash/ 找回")
        }
        .task { load() }
    }

    private var draftBinding: Binding<Item>? {
        guard draft != nil else { return nil }
        return Binding(get: { draft ?? Item() }, set: { draft = $0 })
    }

    private func stepperRow(
        _ label: String, value: Binding<Int>,
        range: ClosedRange<Int>, step: Int = 1, suffix: String
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value.wrappedValue)\(suffix)").foregroundStyle(.secondary)
            }
        }
    }

    private func load() {
        draft = state.items.first { $0.id == itemID }
        isDirty = false
    }

    private func addNote(_ binding: Binding<Item>) {
        let text = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        binding.wrappedValue.thinkingNotes.append(ThinkingNote(note: text))
        newNote = ""
        isDirty = true
    }

    private func save() async {
        guard var item = draft else { return }
        if await state.save(&item) {
            draft = item
            isDirty = false
        }
    }

    private func archive() async {
        guard var item = draft else { return }
        await state.archive(&item)
        dismiss()
    }

    private func delete() async {
        guard let item = draft else { return }
        await state.delete(item)
        dismiss()
    }
}
