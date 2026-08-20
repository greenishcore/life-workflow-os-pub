import SwiftUI
import LifeWorkflowKit

struct SettingsView: View {
    @Environment(AppState.self) private var state

    @State private var roots: [AppConfig.RootConfig] = []
    @State private var reminderList = ""
    @State private var calendarName = ""
    @State private var baseURL = ""
    @State private var model = ""

    var body: some View {
        PageScaffold(destination: .settings) {
            Button("保存设置") { Task { await save() } }.buttonStyle(.borderedProminent)
        } content: {
            if state.conflictCount > 0 || state.pendingDownloadCount > 0
                || !state.conflictReports.isEmpty {
                syncCard
            }
            rootsCard
            appleCard
            llmCard
            diagnosticsCard
        }
        .task { load() }
    }

    // MARK: iCloud 同步

    private var syncCard: some View {
        Card(title: "iCloud 同步",
             hint: "冲突处理遵循：updated 更新者胜；落败版本一律保留到 .conflicts/，绝不丢弃") {
            if state.conflictCount > 0 {
                ForEach(Array(state.attentionWarnings.enumerated()), id: \.offset) { _, w in
                    Label(w.message, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Typo.list).foregroundStyle(.orange)
                }
                HStack {
                    Spacer()
                    Button("处理全部冲突") { Task { await state.resolveConflicts() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.isResolvingConflicts)
                    if state.isResolvingConflicts { ProgressView().controlSize(.small) }
                }
            }

            if state.pendingDownloadCount > 0 {
                HStack {
                    Label("\(state.pendingDownloadCount) 个文件尚未从 iCloud 下载",
                          systemImage: "icloud.and.arrow.down")
                        .font(Theme.Typo.list).foregroundStyle(.secondary)
                    Spacer()
                    Button("发起下载") { Task { await state.downloadPending() } }
                }
            }

            if !state.conflictReports.isEmpty {
                Divider()
                Text("最近一次处理结果").font(Theme.Typo.hintStrong)
                    .foregroundStyle(.secondary)
                ForEach(state.conflictReports) { report in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.message).font(Theme.Typo.hint)
                        ForEach(report.archived, id: \.self) { url in
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } label: {
                                Text(url.lastPathComponent)
                                    .font(Theme.Typo.monoSmall)
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: vault 根

    private var rootsCard: some View {
        Card(title: "知识库位置",
             hint: "复合 vault：想法/日记可放 iCloud（手机能看到），隐私与大体积内容留本地") {
            ForEach(Array(roots.enumerated()), id: \.offset) { index, root in
                HStack(spacing: 8) {
                    Image(systemName: root.needsCoordination ? "icloud" : "internaldrive")
                        .foregroundStyle(root.needsCoordination ? Theme.accent : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(root.displayName).font(Theme.Typo.listStrong)
                        Text(root.path).font(Theme.Typo.mono)
                            .foregroundStyle(Theme.faint).textSelection(.enabled)
                        Text(root.folders.isEmpty ? "兜底根（其余目录都落这里）"
                                                  : "归属：\(root.folders.joined(separator: " / "))")
                            .font(Theme.Typo.hint).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("选择…") { pick(index: index) }
                    Button("打开") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: root.path))
                    }
                    if roots.count > 1 {
                        Button {
                            roots.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("移除这个根")
                    }
                }
                .padding(.vertical, 4)
                if index < roots.count - 1 { Divider() }
            }

            HStack {
                Button {
                    addICloudRoot()
                } label: {
                    Label("添加 iCloud 根（同步子集）", systemImage: "icloud.and.arrow.up")
                }
                .disabled(roots.contains { $0.id == "icloud" })
                Spacer()
            }

            if !state.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(state.warnings.enumerated()), id: \.offset) { _, w in
                        Label(w.message, systemImage: "exclamationmark.triangle")
                            .font(Theme.Typo.hint).foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var appleCard: some View {
        Card(title: "Apple 默认值", hint: "捕捉页导入时的默认列表 / 日历名") {
            HStack(spacing: 14) {
                HStack { Text("提醒事项列表").font(Theme.Typo.list); TextField("", text: $reminderList) }
                HStack { Text("日历名").font(Theme.Typo.list); TextField("", text: $calendarName) }
            }
        }
    }

    private var llmCard: some View {
        Card(title: "提示词重写用的 LLM",
             hint: "OpenAI 兼容接口；API Key 走环境变量 OPENAI_API_KEY，不落盘") {
            HStack(spacing: 14) {
                HStack { Text("Base URL").font(Theme.Typo.list); TextField("", text: $baseURL) }
                HStack { Text("模型").font(Theme.Typo.list); TextField("", text: $model).frame(width: 160) }
            }
            Label(
                ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil
                    ? "已检测到 OPENAI_API_KEY，可使用 LLM 重写"
                    : "未设置 OPENAI_API_KEY —— 提示词只能生成脚手架",
                systemImage: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil
                    ? "checkmark.circle" : "circle"
            )
            .font(Theme.Typo.hint).foregroundStyle(Theme.faint)
        }
    }

    private var diagnosticsCard: some View {
        Card(title: "诊断") {
            grid("配置文件", AppConfig.fileURL.path)
            grid("日志", state.config.logsURL.path)
            grid("提示词", state.config.promptsURL.path)
            grid("转换缓存", state.config.cacheURL.path)
            grid("iCloud 容器",
                 AppConfig.iCloudDocuments()?.path ?? "未登录 iCloud 或未启用容器")
            grid("记录总数", "\(state.items.count)")
        }
    }

    private func grid(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).font(Theme.Typo.hint).foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value).font(Theme.Typo.mono)
                .foregroundStyle(Theme.faint).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 动作

    private func load() {
        roots = state.config.roots
        reminderList = state.config.defaultReminderList
        calendarName = state.config.defaultCalendar
        baseURL = state.config.openAIBaseURL
        model = state.config.openAIModel
    }

    private func pick(index: Int) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: roots[index].path)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        roots[index].path = url.path
    }

    private func addICloudRoot() {
        let path = AppConfig.iCloudDocuments()?.path
            ?? (NSHomeDirectory() as NSString)
                .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/LifeOS")
        roots.insert(
            .init(id: "icloud", path: path,
                  folders: Array(VaultRoot.syncedFolders).sorted(),
                  needsCoordination: true, displayName: "iCloud"),
            at: 0)
    }

    private func save() async {
        var cfg = state.config
        cfg.roots = roots
        cfg.defaultReminderList = reminderList
        cfg.defaultCalendar = calendarName
        cfg.openAIBaseURL = baseURL
        cfg.openAIModel = model
        await state.apply(config: cfg)
        state.notify("设置已保存 → \(AppConfig.fileURL.lastPathComponent)")
    }
}
