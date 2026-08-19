import SwiftUI
import LifeWorkflowKit

struct ArchiveView: View {
    @Environment(AppState.self) private var state
    @Environment(\.isSnapshotting) private var isSnapshotting

    @State private var status = GitService.Status()
    @State private var history: [GitService.Commit] = []
    @State private var tags: [String] = []
    @State private var message = ""
    @State private var version = ""
    @State private var notes = ""
    @State private var log: [String] = []
    @State private var busy = false

    /// 归档的是「代码仓库」，不是 vault 根——两者可能不是同一个目录。
    /// 从各个 vault 根向上搜索最近的 .git，找不到就禁用归档功能。
    @State private var repoURL: URL?

    var body: some View {
        PageScaffold(destination: .archive) {
            Button("刷新") { Task { await load() } }
        } content: {
            statusCard
            commitCard
            releaseCard
            historyCard
        }
        .task { await load() }
        .onChange(of: state.config.roots.count) { _, _ in Task { await load() } }
    }

    private var statusCard: some View {
        Card(title: "仓库状态") {
            if !status.isRepo {
                Label(repoURL == nil
                      ? "从 vault 向上没找到 git 仓库，归档功能不可用"
                      : "该目录不是 git 仓库，归档功能不可用",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            } else {
                HStack(spacing: 14) {
                    Label(status.branch, systemImage: "arrow.triangle.branch")
                    if status.ahead > 0 || status.behind > 0 {
                        Label("领先 \(status.ahead) / 落后 \(status.behind)", systemImage: "arrow.up.arrow.down")
                    }
                    Label(status.dirty ? "\(status.changed.count) 处改动" : "工作区干净",
                          systemImage: status.dirty ? "pencil" : "checkmark.circle")
                        .foregroundStyle(status.dirty ? .orange : .green)
                    Spacer()
                }
                .font(.system(size: 12))

                if let repoURL {
                    Text(repoURL.path).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.faint).textSelection(.enabled)
                }
                if !status.remote.isEmpty {
                    Text(status.remote).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.faint).textSelection(.enabled)
                }
                if !status.lastCommit.isEmpty {
                    Text("最近：\(status.lastCommit)").font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if !status.changed.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(status.changed.prefix(60).enumerated()), id: \.offset) { _, line in
                                Text(line).font(.system(size: 11, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(height: 110)
                    .padding(8)
                    .background(Theme.pageBackground, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private var commitCard: some View {
        Card(title: "提交并推送", hint: "留空则用「auto: 日期 工作流同步」") {
            HStack(spacing: 8) {
                TextField("commit 说明", text: $message)
                Button("只提交") { Task { await sync(push: false) } }
                    .disabled(!status.isRepo || busy)
                Button("提交并推送") { Task { await sync(push: true) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!status.isRepo || busy)
                if busy { ProgressView().controlSize(.small) }
            }
            if !log.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(height: 110)
                .padding(8)
                .background(Theme.pageBackground, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var releaseCard: some View {
        Card(title: "里程碑发布", hint: "语义化版本 vX.Y.Z，需要 gh CLI 已登录") {
            HStack(spacing: 8) {
                TextField("v0.2.0", text: $version).frame(width: 110)
                TextField("本阶段成果 + 下阶段计划", text: $notes)
                Button("打 tag 并发布") { Task { await release() } }
                    .disabled(!status.isRepo || version.isEmpty || busy)
            }
            Text(tags.isEmpty ? "还没有里程碑" : "已有里程碑：\(tags.prefix(8).joined(separator: "、"))")
                .font(.system(size: 11)).foregroundStyle(Theme.faint)
        }
    }

    private var historyCard: some View {
        Card(title: "提交历史") {
            if history.isEmpty {
                Text("暂无提交").font(.system(size: 12)).foregroundStyle(Theme.faint)
            } else {
                VStack(spacing: 0) {
                    ForEach(isSnapshotting ? Array(history.prefix(8)) : history) { commit in
                        HStack(spacing: 10) {
                            Text(commit.hash)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.accent)
                            Text(commit.when)
                                .font(.system(size: 11)).foregroundStyle(Theme.faint)
                                .frame(width: 90, alignment: .leading)
                            Text(commit.subject)
                                .font(.system(size: 12)).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 3)
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: 动作

    private func load() async {
        repoURL = state.config.roots.lazy
            .compactMap { GitService.findRepository(startingAt: URL(fileURLWithPath: $0.path)) }
            .first
        guard let repoURL else {
            status = GitService.Status()
            history = []
            tags = []
            return
        }
        status = await GitService.status(repo: repoURL)
        history = await GitService.history(repo: repoURL, limit: 30)
        tags = await GitService.tags(repo: repoURL)
    }

    private func sync(push: Bool) async {
        busy = true
        defer { busy = false }
        guard let repoURL else { return }
        log.append("──── 同步 ────")
        let outcome = await GitService.sync(
            repo: repoURL, message: message, push: push,
            log: { line in Task { @MainActor in log.append(line) } })
        log.append((outcome.ok ? "✅ " : "❌ ") + outcome.message)
        state.notify(outcome.message)
        if outcome.ok { message = "" }
        await load()
    }

    private func release() async {
        busy = true
        defer { busy = false }
        guard let repoURL else { return }
        log.append("──── 发布 \(version) ────")
        let outcome = await GitService.release(
            repo: repoURL, version: version, notes: notes,
            log: { line in Task { @MainActor in log.append(line) } })
        log.append((outcome.ok ? "✅ " : "❌ ") + outcome.message)
        state.notify(outcome.message)
        if outcome.ok { version = ""; notes = "" }
        await load()
    }
}
