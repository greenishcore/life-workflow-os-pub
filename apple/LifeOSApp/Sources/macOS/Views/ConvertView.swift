import SwiftUI
import UniformTypeIdentifiers
import LifeWorkflowKit

struct ConvertView: View {
    @Environment(AppState.self) private var state

    @State private var source: URL?
    @State private var target: ConvertService.Target = .pdf
    @State private var customOutput = ""
    @State private var log: [String] = []
    @State private var busy = false
    @State private var result: URL?
    @State private var isDropTargeted = false
    @State private var cache: (count: Int, bytes: Int) = (0, 0)

    var body: some View {
        PageScaffold(destination: .convert) {
            EmptyView()
        } content: {
            convertCard
            cacheCard
            toolsCard
        }
        .task { refreshCache() }
    }

    private var convertCard: some View {
        Card(title: "转换", hint: "支持把文件直接拖进虚线框") {
            dropZone

            HStack(spacing: 8) {
                Text("目标格式").font(.system(size: 12)).foregroundStyle(.secondary)
                Picker("", selection: $target) {
                    ForEach(ConvertService.Target.allCases, id: \.self) {
                        Text("\($0.rawValue) · \($0.label)").tag($0)
                    }
                }.labelsHidden().frame(width: 190)

                Text("输出到").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("留空 = 缓存目录旁的 out/", text: $customOutput)

                Button("开始转换") { Task { await convert() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(source == nil || busy)
                if busy { ProgressView().controlSize(.small) }
            }

            if !log.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 130)
                .padding(8)
                .background(Theme.pageBackground, in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Spacer()
                Button("打开产物") {
                    if let result { NSWorkspace.shared.open(result) }
                }
                .disabled(result == nil)
                Button("在访达中显示") {
                    if let result { NSWorkspace.shared.activateFileViewerSelecting([result]) }
                }
                .disabled(result == nil)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: source == nil ? "arrow.down.doc" : "doc.text")
                .font(.system(size: 22))
                .foregroundStyle(isDropTargeted ? Theme.accent : Theme.faint)
            Text(source?.lastPathComponent ?? "把 PDF / Word / PPT / HTML / Markdown 拖到这里")
                .font(.system(size: 12))
                .foregroundStyle(source == nil ? Theme.faint : .primary)
            if let source {
                Text(source.deletingLastPathComponent().path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.faint).lineLimit(1)
            }
            Button("选择文件…") { pick() }.controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .padding(12)
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
                    log.append("已拖入：\(url.lastPathComponent)")
                }
            }
            return true
        }
    }

    private var cacheCard: some View {
        Card(title: "转换缓存", hint: "键 = sha256(输入) + 转换器版本；命中即复用，不重复烧算力") {
            HStack {
                Text(cache.count == 0
                     ? "暂无缓存 · \(state.config.cacheURL.path)"
                     : "\(cache.count) 条缓存 · \(cache.bytes / 1024) KB · \(state.config.cacheURL.path)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.faint)
                Spacer()
                Button("清空缓存") {
                    let n = ConvertService.clearCache(config: state.config)
                    log.append("已清空 \(n) 条缓存")
                    refreshCache()
                }
                .disabled(cache.count == 0)
            }
        }
    }

    private var toolsCard: some View {
        Card(title: "依赖体检", hint: "缺哪个装哪个，不影响其它功能") {
            let tools = ConvertService.toolStatus()
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)], spacing: 6) {
                ForEach(tools) { tool in
                    HStack(spacing: 6) {
                        Image(systemName: tool.installed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(tool.installed ? .green : Theme.faint)
                        Text(tool.name).font(.system(size: 11, weight: .medium))
                        Text(tool.detail).font(.system(size: 11))
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

    private func convert() async {
        guard let source else { return }
        busy = true
        result = nil
        log.append("──── \(source.lastPathComponent) ────")
        let started = Date()
        defer { busy = false }

        let output = customOutput.trimmingCharacters(in: .whitespaces)
        let outcome = await ConvertService.convert(
            source: source, to: target,
            output: output.isEmpty ? nil : URL(fileURLWithPath: output),
            config: state.config,
            log: { line in Task { @MainActor in log.append(line) } })

        if outcome.ok {
            result = outcome.output
            log.append("✅ \(outcome.message)\(outcome.cached ? "（命中缓存，未重复计算）" : "")")
            state.notify("转换完成 → \(outcome.output?.lastPathComponent ?? "")")
        } else {
            log.append("❌ \(outcome.message)")
            state.notify("转换失败")
        }
        // 自动留痕：这条数据正是周复盘提炼 skill 的原料
        await state.logOperation(
            objective: "转换 \(source.lastPathComponent) → \(target.rawValue)",
            status: outcome.ok ? .success : .failed,
            tools: [ConvertService.markdownTool(), "pandoc"].compactMap { $0 },
            outputs: outcome.output.map { [$0.path] } ?? [],
            errors: outcome.ok ? [] : [outcome.message],
            duration: Date().timeIntervalSince(started),
            notes: outcome.cached ? "命中缓存" : "")
        refreshCache()
    }

    private func refreshCache() {
        cache = ConvertService.cacheStats(config: state.config)
    }
}
