import SwiftUI
import LifeWorkflowKit

struct PromptsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.isSnapshotting) private var isSnapshotting

    @State private var raw = ""
    @State private var content = ""
    @State private var currentURL: URL?
    @State private var busy = false

    var body: some View {
        SplitOrStack(isSnapshotting: isSnapshotting, leftWidth: 380) {
            leftPane
        } right: {
            rightPane
        }
        .background(Theme.pageBackground)
        .task { state.refreshPromptHistory() }
    }

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            PageHeader(title: Destination.prompts.title,
                       subtitle: Destination.prompts.subtitle) { EmptyView() }

            Card(title: "原始需求", hint: "把想让 agent 做的事，用大白话写出来") {
                TextEditor(text: $raw)
                    .font(Theme.Typo.body)
                    .frame(height: 110)
                    .padding(4)
                    .background(Theme.pageBackground, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))

                HStack {
                    Text(state.isLLMAvailable
                         ? "LLM：\(state.config.openAIModel)"
                         : "未设置 OPENAI_API_KEY，只能生成脚手架")
                        .font(Theme.Typo.hint).foregroundStyle(Theme.faint)
                    Spacer()
                    Button("生成脚手架") { Task { await generate(useLLM: false) } }
                        .disabled(raw.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                    Button("用 LLM 重写") { Task { await generate(useLLM: true) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!state.isLLMAvailable
                                  || raw.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                    if busy { ProgressView().controlSize(.small) }
                }
            }

            Card(title: "已重写的提示词", hint: "都在 prompts/01_rewritten/，随仓库版本化") {
                if state.promptHistory.isEmpty {
                    Text("还没有生成过").font(Theme.Typo.list).foregroundStyle(Theme.faint)
                } else if isSnapshotting {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(state.promptHistory.prefix(8), id: \.self) { url in
                            Text(url.deletingPathExtension().lastPathComponent)
                                .font(Theme.Typo.mono)
                        }
                    }
                } else {
                    List(state.promptHistory, id: \.self, selection: Binding(
                        get: { currentURL },
                        set: { newValue in if let newValue { open(newValue) } }
                    )) { url in
                        Text(url.deletingPathExtension().lastPathComponent)
                            .font(Theme.Typo.mono)
                            .tag(url)
                    }
                    .frame(minHeight: 180)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Card(title: "提示词文档", hint: "五段式：角色 / 背景 / 目标 / 约束 / 输出格式 / 验收标准") {
                TextEditor(text: $content)
                    .font(Theme.Typo.monoList)
                    .frame(minHeight: 420)
                    .padding(4)
                    .background(Theme.pageBackground, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))

                HStack {
                    Text(currentURL?.path ?? "")
                        .font(Theme.Typo.monoSmall)
                        .foregroundStyle(Theme.faint).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("复制") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(content, forType: .string)
                        state.notify("已复制到剪贴板")
                    }
                    Button("在访达中显示") {
                        if let currentURL { NSWorkspace.shared.activateFileViewerSelecting([currentURL]) }
                    }.disabled(currentURL == nil)
                    Button("保存修改") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(currentURL == nil)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    // MARK: 动作

    private func generate(useLLM: Bool) async {
        busy = true
        defer { busy = false }
        let outcome = await state.rewritePrompt(raw, useLLM: useLLM)
        content = outcome.content
        if let url = outcome.url { currentURL = url }
    }

    private func open(_ url: URL) {
        currentURL = url
        content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func save() {
        guard let currentURL else { return }
        do {
            try content.write(to: currentURL, atomically: true, encoding: .utf8)
            state.notify("已保存 → \(currentURL.lastPathComponent)")
        } catch {
            state.notify("保存失败：\(error.localizedDescription)")
        }
    }
}
