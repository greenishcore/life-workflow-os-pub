import SwiftUI
import UniformTypeIdentifiers
import LifeWorkflowKit

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(VaultAccess.self) private var vault

    @State private var showPicker = false
    @State private var reminderList = ""
    @State private var calendarName = ""

    var body: some View {
        NavigationStack {
            Form {
                if state.conflictCount > 0 || state.pendingDownloadCount > 0
                    || !state.conflictReports.isEmpty {
                    syncSection
                }
                vaultSection
                appleSection
                diagnosticsSection
                aboutSection
            }
            .navigationTitle("设置")
            .task {
                reminderList = state.config.defaultReminderList
                calendarName = state.config.defaultCalendar
            }
            .fileImporter(isPresented: $showPicker,
                          allowedContentTypes: [.folder],
                          allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                Task { await vault.adopt(url, into: state) }
            }
        }
    }

    // MARK: iCloud 同步

    private var syncSection: some View {
        Section {
            if state.conflictCount > 0 {
                ForEach(Array(state.attentionWarnings.enumerated()), id: \.offset) { _, w in
                    Label(w.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                Button {
                    Task { await state.resolveConflicts() }
                } label: {
                    HStack {
                        Label("处理全部冲突", systemImage: "arrow.triangle.merge")
                        if state.isResolvingConflicts {
                            Spacer(); ProgressView()
                        }
                    }
                }
                .disabled(state.isResolvingConflicts)
            }

            if state.pendingDownloadCount > 0 {
                Button {
                    Task { await state.downloadPending() }
                } label: {
                    Label("下载 \(state.pendingDownloadCount) 个未下载的文件",
                          systemImage: "icloud.and.arrow.down")
                }
            }

            ForEach(state.conflictReports) { report in
                VStack(alignment: .leading, spacing: Theme.Space.textLine) {
                    Text(report.message).font(.caption)
                    ForEach(report.archived, id: \.self) { url in
                        Text(url.lastPathComponent)
                            .font(.caption2.monospaced()).foregroundStyle(Theme.faint)
                    }
                }
            }
        } header: {
            Text("iCloud 同步")
        } footer: {
            Text("冲突处理规则：frontmatter 的 updated 更新者胜出；落败版本一律保留到 vault 的 .conflicts/ 目录，用任何编辑器都能打开对比，确认无用后再自行删除。")
        }
    }

    // MARK: vault

    private var vaultSection: some View {
        Section {
            LabeledContent("当前位置") {
                Text(vault.isExternal ? (vault.currentURL?.lastPathComponent ?? "—") : "App 内置")
                    .foregroundStyle(.secondary)
            }
            if vault.isInICloud {
                Label("在 iCloud Drive 中，可与 Mac 同步", systemImage: "icloud.fill")
                    .font(.caption).foregroundStyle(Theme.accent)
            }
            Button {
                showPicker = true
            } label: {
                Label("选择 vault 文件夹…", systemImage: "folder.badge.gearshape")
            }
            if vault.isExternal {
                Button(role: .destructive) {
                    Task { await vault.reset(into: state) }
                } label: {
                    Label("改回 App 内置目录", systemImage: "arrow.uturn.backward")
                }
            }
        } header: {
            Text("知识库位置")
        } footer: {
            Text("""
            \(vault.message)

            想和 Mac 共用同一份数据：先在 Mac 上把 vault（或其中的 Inbox / Daily / \
            Projects）放进 iCloud Drive，再在这里选中那个文件夹。

            当前使用免费开发者账号，拿不到 iCloud 容器权益，所以走「你来选目录 + \
            书签记住授权」这条路——效果一样，且不需要任何权益。
            """)
        }
    }

    private var appleSection: some View {
        Section {
            LabeledContent("提醒事项列表") {
                TextField("提醒事项", text: $reminderList)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("日历名") {
                TextField("个人", text: $calendarName)
                    .multilineTextAlignment(.trailing)
            }
            Button("保存") { Task { await saveApple() } }
        } header: {
            Text("Apple 默认值")
        } footer: {
            Text("Apple 便签没有公开 API，iOS 上无法读取。请用系统「分享」把便签内容发到本应用。")
        }
    }

    private var diagnosticsSection: some View {
        Section("诊断") {
            LabeledContent("记录总数", value: "\(state.items.count)")
            LabeledContent("思路注释", value: "\(state.summary.totalNotes)")
            if let url = vault.currentURL {
                VStack(alignment: .leading, spacing: Theme.Space.textLine) {
                    Text("vault 路径").font(.caption).foregroundStyle(.secondary)
                    Text(url.path).font(.caption2.monospaced())
                        .foregroundStyle(Theme.faint).textSelection(.enabled)
                }
            }
            if !state.warnings.isEmpty {
                ForEach(Array(state.warnings.enumerated()), id: \.offset) { _, w in
                    Label(w.message, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Button("重新扫描") { Task { await state.reload() } }
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("版本", value: "1.0.0（M3）")
        } footer: {
            Text("""
            iOS 端定位是随身捕捉与查阅。格式转换、git 归档、Apple 便签读取这三件在 \
            iOS 上不可行或做不好，集中在 Mac 端完成。
            """)
        }
    }

    private func saveApple() async {
        var cfg = state.config
        cfg.defaultReminderList = reminderList.isEmpty ? "提醒事项" : reminderList
        cfg.defaultCalendar = calendarName.isEmpty ? "个人" : calendarName
        await state.apply(config: cfg)
        state.notify("已保存")
    }
}
