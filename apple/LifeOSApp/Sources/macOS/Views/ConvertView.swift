import SwiftUI
import UniformTypeIdentifiers
import LifeWorkflowKit

struct ConvertView: View {
    @Environment(AppState.self) private var state

    @State private var source: URL?
    @State private var target: ConvertService.Target = .pdf
    @State private var customOutput = ""
    @State private var isDropTargeted = false

    var body: some View {
        PageScaffold(destination: .convert) {
            EmptyView()
        } content: {
            convertCard
            cacheCard
            toolsCard
        }
        .task { state.refreshConvertEnvironment() }
    }

    private var convertCard: some View {
        Card(title: "转换", hint: "支持把文件直接拖进虚线框") {
            dropZone

            HStack(spacing: Theme.Space.base) {
                Text("目标格式").font(Theme.Typo.list).foregroundStyle(.secondary)
                Picker("", selection: $target) {
                    ForEach(ConvertService.Target.allCases, id: \.self) {
                        Text("\($0.rawValue) · \($0.label)").tag($0)
                    }
                }.labelsHidden().frame(width: 190)

                Text("输出到").font(Theme.Typo.list).foregroundStyle(.secondary)
                TextField("留空 = 缓存目录旁的 out/", text: $customOutput)

                Button("开始转换") { start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(source == nil || state.isConverting)
                if state.isConverting { ProgressView().controlSize(.small) }
            }

            if !state.convertLog.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.textLine) {
                        ForEach(Array(state.convertLog.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(Theme.Typo.mono)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 130)
                .padding(Theme.Space.base)
                .background(Theme.pageBackground, in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Spacer()
                Button("打开产物") {
                    if let out = state.convertResult { NSWorkspace.shared.open(out) }
                }
                .disabled(state.convertResult == nil)
                Button("在访达中显示") {
                    if let out = state.convertResult {
                        NSWorkspace.shared.activateFileViewerSelecting([out])
                    }
                }
                .disabled(state.convertResult == nil)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: Theme.Space.inlineTight) {
            Image(systemName: source == nil ? "arrow.down.doc" : "doc.text")
                .font(Theme.Typo.display)
                .foregroundStyle(isDropTargeted ? Theme.accent : Theme.faint)
            Text(source?.lastPathComponent ?? "把 PDF / Word / PPT / HTML / Markdown 拖到这里")
                .font(Theme.Typo.list)
                .foregroundStyle(source == nil ? Theme.faint : .primary)
            if let source {
                Text(source.deletingLastPathComponent().path)
                    .font(Theme.Typo.monoSmall)
                    .foregroundStyle(Theme.faint).lineLimit(1)
            }
            Button("选择文件…") { pick() }.controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .padding(Theme.Space.block)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDropTargeted ? Theme.accent.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isDropTargeted ? Theme.accent : Theme.border,
                              style: .init(lineWidth: 1, dash: [5, 4]))
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    source = url
                    state.appendConvertLog("已拖入：\(url.lastPathComponent)")
                }
            }
            return true
        }
    }

    private var cacheCard: some View {
        Card(title: "转换缓存", hint: "键 = sha256(输入) + 转换器版本；命中即复用，不重复烧算力") {
            HStack {
                Text(state.convertCache.count == 0
                     ? "暂无缓存 · \(state.config.cacheURL.path)"
                     : "\(state.convertCache.count) 条缓存 · \(state.convertCache.bytes / 1024) KB · \(state.config.cacheURL.path)")
                    .font(Theme.Typo.mono)
                    .foregroundStyle(Theme.faint)
                Spacer()
                Button("清空缓存") { state.clearConvertCache() }
                .disabled(state.convertCache.count == 0)
            }
        }
    }

    private var toolsCard: some View {
        Card(title: "依赖体检", hint: "缺哪个装哪个，不影响其它功能") {
            let tools = state.convertTools
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)], spacing: Theme.Space.inlineTight) {
                ForEach(tools) { tool in
                    HStack(spacing: Theme.Space.inlineTight) {
                        Image(systemName: tool.installed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(tool.installed ? .green : Theme.faint)
                        Text(tool.name).font(Theme.Typo.hintMedium)
                        Text(tool.detail).font(Theme.Typo.hint)
                            .foregroundStyle(Theme.faint).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
        }
    }

    // MARK: 动作

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { source = panel.url }
    }

    /// 只做派发。转换的编排、留痕、缓存刷新都在 AppState。
    private func start() {
        guard let source else { return }
        Task { await state.convert(source: source, to: target, output: customOutput) }
    }
}
