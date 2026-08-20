import SwiftUI
import LifeWorkflowKit

/// 版本归档页。
///
/// 这里**只有布局与表单**：仓库状态、提交历史、命令输出都从 `AppState` 读，
/// git 的编排在 `AppState.loadGit / gitSync / gitRelease`。
/// 这么切是为了让界面设计能独立交接——改这一页的排版不该碰到跑 git 的代码。
struct ArchiveView: View {
    @Environment(AppState.self) private var state
    @Environment(\.isSnapshotting) private var isSnapshotting

    // 表单输入是视图自己的状态，留在这里是对的
    @State private var message = ""
    @State private var version = ""
    @State private var notes = ""

    var body: some View {
        PageScaffold(destination: .archive) {
            Button("刷新") { Task { await state.loadGit() } }
        } content: {
            statusCard
            commitCard
            releaseCard
            historyCard
        }
        .task { await state.loadGit() }
        .onChange(of: state.config.roots.count) { _, _ in Task { await state.loadGit() } }
    }

    private var statusCard: some View {
        Card(title: "仓库状态") {
            if !state.gitStatus.isRepo {
                Label(state.gitRepo == nil
                      ? "从 vault 向上没找到 git 仓库，归档功能不可用"
                      : "该目录不是 git 仓库，归档功能不可用",
                      systemImage: "exclamationmark.triangle")
                    .font(Theme.Typo.list).foregroundStyle(.orange)
            } else {
                HStack(spacing: Theme.Space.inlineWide) {
                    Label(state.gitStatus.branch, systemImage: "arrow.triangle.branch")
                    if state.gitStatus.ahead > 0 || state.gitStatus.behind > 0 {
                        Label("领先 \(state.gitStatus.ahead) / 落后 \(state.gitStatus.behind)",
                              systemImage: "arrow.up.arrow.down")
                    }
                    Label(state.gitStatus.dirty ? "\(state.gitStatus.changed.count) 处改动" : "工作区干净",
                          systemImage: state.gitStatus.dirty ? "pencil" : "checkmark.circle")
                        .foregroundStyle(state.gitStatus.dirty ? .orange : .green)
                    Spacer()
                }
                .font(Theme.Typo.list)

                if let repo = state.gitRepo {
                    Text(repo.path).font(Theme.Typo.mono)
                        .foregroundStyle(Theme.faint).textSelection(.enabled)
                }
                if !state.gitStatus.remote.isEmpty {
                    Text(state.gitStatus.remote).font(Theme.Typo.mono)
                        .foregroundStyle(Theme.faint).textSelection(.enabled)
                }
                if !state.gitStatus.lastCommit.isEmpty {
                    Text("最近：\(state.gitStatus.lastCommit)").font(Theme.Typo.hint)
                        .foregroundStyle(.secondary)
                }
                if !state.gitStatus.changed.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Space.textLine) {
                            ForEach(Array(state.gitStatus.changed.prefix(60).enumerated()),
                                    id: \.offset) { _, line in
                                Text(line).font(Theme.Typo.mono)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(height: 110)
                    .padding(Theme.Space.base)
                    .background(Theme.pageBackground, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private var commitCard: some View {
        Card(title: "提交并推送", hint: "留空则用「auto: 日期 工作流同步」") {
            HStack(spacing: Theme.Space.base) {
                TextField("commit 说明", text: $message)
                Button("只提交") { commit(push: false) }
                    .disabled(!state.gitStatus.isRepo || state.isGitBusy)
                Button("提交并推送") { commit(push: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!state.gitStatus.isRepo || state.isGitBusy)
                if state.isGitBusy { ProgressView().controlSize(.small) }
            }
            if !state.gitLog.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.textLine) {
                        ForEach(Array(state.gitLog.enumerated()), id: \.offset) { _, line in
                            Text(line).font(Theme.Typo.mono)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(height: 110)
                .padding(Theme.Space.base)
                .background(Theme.pageBackground, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var releaseCard: some View {
        Card(title: "里程碑发布", hint: "语义化版本 vX.Y.Z，需要 gh CLI 已登录") {
            HStack(spacing: Theme.Space.base) {
                TextField("v0.2.0", text: $version).frame(width: 110)
                TextField("本阶段成果 + 下阶段计划", text: $notes)
                Button("打 tag 并发布") { publish() }
                    .disabled(!state.gitStatus.isRepo || version.isEmpty || state.isGitBusy)
            }
            Text(state.gitTags.isEmpty
                 ? "还没有里程碑"
                 : "已有里程碑：\(state.gitTags.prefix(8).joined(separator: "、"))")
                .font(Theme.Typo.hint).foregroundStyle(Theme.faint)
        }
    }

    private var historyCard: some View {
        Card(title: "提交历史") {
            if state.gitHistory.isEmpty {
                Text("暂无提交").font(Theme.Typo.list).foregroundStyle(Theme.faint)
            } else {
                VStack(spacing: 0) {
                    ForEach(isSnapshotting ? Array(state.gitHistory.prefix(8))
                                           : state.gitHistory) { commit in
                        HStack(spacing: Theme.Space.inline) {
                            Text(commit.hash)
                                .font(Theme.Typo.mono)
                                .foregroundStyle(Theme.accent)
                            Text(commit.when)
                                .font(Theme.Typo.hint).foregroundStyle(Theme.faint)
                                .frame(width: 90, alignment: .leading)
                            Text(commit.subject)
                                .font(Theme.Typo.list).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, Theme.Space.textLine)
                        Divider()
                    }
                }
            }
        }
    }

    // 只做「派发 + 成功后清空输入框」，清空是表单行为、归视图管
    private func commit(push: Bool) {
        Task { if await state.gitSync(message: message, push: push) { message = "" } }
    }

    private func publish() {
        Task {
            if await state.gitRelease(version: version, notes: notes) {
                version = ""
                notes = ""
            }
        }
    }
}
