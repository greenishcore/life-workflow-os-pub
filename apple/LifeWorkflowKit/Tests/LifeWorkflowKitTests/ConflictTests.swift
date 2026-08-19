import Foundation
import Testing
@testable import LifeWorkflowKit

@Suite("冲突裁决策略")
struct ConflictPolicyTests {

    /// 造一个带指定 updated / 思路注释的笔记
    private func note(
        updated: String? = nil,
        notes: [String] = [],
        body: String = "正文",
        created: String = "2026-08-01"
    ) -> String {
        var fm = "---\ntype: idea\nid: x\ntitle: 冲突样本\ncreated: \(created)\nstatus: doing\n"
        if let updated { fm += "updated: \(updated)\n" }
        if !notes.isEmpty {
            fm += "thinking_notes:\n"
            for n in notes { fm += "  - {t: \(n), note: 演进}\n" }
        }
        fm += "---\n\n\(body)\n"
        return fm
    }

    private func candidate(
        _ id: String, updated: String? = nil, notes: [String] = [],
        body: String = "正文", modified: TimeInterval = 0
    ) -> ConflictPolicy.Candidate {
        .init(id: id, text: note(updated: updated, notes: notes, body: body),
              modified: Date(timeIntervalSince1970: modified))
    }

    @Test("空输入返回 nil")
    func emptyInput() {
        #expect(ConflictPolicy.decide([]) == nil)
    }

    @Test("单个候选直接胜出，没有落败者")
    func singleCandidate() throws {
        let d = try #require(ConflictPolicy.decide([candidate("a", updated: "2026-08-10")]))
        #expect(d.winner.id == "a")
        #expect(d.losers.isEmpty)
    }

    // 第 1 层：updated
    @Test("updated 更新的胜出")
    func updatedWins() throws {
        let d = try #require(ConflictPolicy.decide([
            candidate("旧", updated: "2026-08-10"),
            candidate("新", updated: "2026-08-19"),
        ]))
        #expect(d.winner.id == "新")
        #expect(d.losers.map(\.id) == ["旧"])
        #expect(d.reason.contains("updated"))
    }

    @Test("有 updated 的胜过没有 updated 的")
    func updatedBeatsMissing() throws {
        let d = try #require(ConflictPolicy.decide([
            candidate("无", updated: nil),
            candidate("有", updated: "2026-08-19"),
        ]))
        #expect(d.winner.id == "有")
    }

    // 第 2 层：lastActivity（含思路注释）
    @Test("updated 相同时，思路注释更新的胜出")
    func lastActivityBreaksTie() throws {
        let d = try #require(ConflictPolicy.decide([
            candidate("少", updated: "2026-08-10", notes: ["2026-08-10"]),
            candidate("多", updated: "2026-08-10", notes: ["2026-08-10", "2026-08-18"]),
        ]))
        #expect(d.winner.id == "多")
        #expect(d.reason.contains("最近活动"))
    }

    // 第 3 层：文件修改时间
    @Test("前两层都平手时，看文件修改时间")
    func modifiedBreaksTie() throws {
        let d = try #require(ConflictPolicy.decide([
            candidate("早", updated: "2026-08-10", modified: 1000),
            candidate("晚", updated: "2026-08-10", modified: 2000),
        ]))
        #expect(d.winner.id == "晚")
        #expect(d.reason.contains("修改时间"))
    }

    // 第 4 层：内容长度
    @Test("时间全平手时，内容更完整的胜出（宁可多不可少）")
    func longerContentWins() throws {
        let d = try #require(ConflictPolicy.decide([
            candidate("短", updated: "2026-08-10", body: "短", modified: 1000),
            candidate("长", updated: "2026-08-10", body: "长很多的正文内容在这里", modified: 1000),
        ]))
        #expect(d.winner.id == "长")
        #expect(d.reason.contains("完整"))
    }

    @Test("三方冲突也能裁出唯一胜者，其余全部保留")
    func threeWayConflict() throws {
        let d = try #require(ConflictPolicy.decide([
            candidate("a", updated: "2026-08-10"),
            candidate("b", updated: "2026-08-19"),
            candidate("c", updated: "2026-08-15"),
        ]))
        #expect(d.winner.id == "b")
        #expect(Set(d.losers.map(\.id)) == ["a", "c"])
    }

    @Test("裁决与候选顺序无关")
    func orderIndependent() throws {
        let a = candidate("a", updated: "2026-08-10")
        let b = candidate("b", updated: "2026-08-19")
        let c = candidate("c", updated: "2026-08-15")
        for permutation in [[a, b, c], [c, b, a], [b, a, c], [c, a, b]] {
            let d = try #require(ConflictPolicy.decide(permutation))
            #expect(d.winner.id == "b", "顺序 \(permutation.map(\.id)) 裁出了 \(d.winner.id)")
        }
    }

    @Test("落败者永远不会为空（有冲突就必有保留项）")
    func losersNeverSilentlyDropped() throws {
        let d = try #require(ConflictPolicy.decide([
            candidate("a", updated: "2026-08-10"),
            candidate("b", updated: "2026-08-19"),
        ]))
        #expect(d.losers.count == 1, "有 2 个版本就必须保留 1 个落败版本")
        #expect(d.winner.id != d.losers[0].id)
    }

    @Test("完全相同的两份不会误判，且仍保留一份")
    func identicalContent() throws {
        let same = candidate("a", updated: "2026-08-10", modified: 1000)
        let clone = ConflictPolicy.Candidate(id: "b", text: same.text, modified: same.modified)
        let d = try #require(ConflictPolicy.decide([same, clone]))
        #expect(d.reason == "内容一致")
        #expect(d.losers.count == 1)
    }
}

@Suite("冲突归档与 iCloud 状态")
struct CloudSyncTests {

    private func makeRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lifeos-conflict-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Inbox"), withIntermediateDirectories: true)
        return dir
    }

    @Test("落败版本被完整保留，带来源说明，且内容可读回")
    func archivePreservesLosers() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let losers = [
            ConflictPolicy.Candidate(id: "yiyang 的 iPhone",
                                     text: "---\ntype: idea\nid: a\ntitle: 甲\ncreated: 2026-08-01\nstatus: doing\n---\n\n手机上写的内容\n",
                                     modified: Date()),
            ConflictPolicy.Candidate(id: "MacBook Air",
                                     text: "---\ntype: idea\nid: a\ntitle: 甲\ncreated: 2026-08-01\nstatus: doing\n---\n\nMac 上写的内容\n",
                                     modified: Date()),
        ]
        let sync = CloudSyncService()
        let archived = try await sync.archive(losers, originalPath: "Inbox/甲.md", root: root)

        #expect(archived.count == 2, "两个落败版本都要保留")
        for url in archived {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("iCloud 冲突落败版本"), "要有来源说明")
            #expect(text.contains("Inbox/甲.md"), "要标明原文件")
            #expect(text.contains("写的内容"), "原内容必须完整保留")
        }
        // 两份来源不同的版本不能互相覆盖
        #expect(Set(archived.map(\.lastPathComponent)).count == 2)
        #expect(archived.allSatisfy { $0.path.contains(".conflicts") })
    }

    @Test("同名来源重复归档不会互相覆盖")
    func archiveDeduplicates() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sync = CloudSyncService()
        let loser = ConflictPolicy.Candidate(id: "iPhone", text: "内容", modified: Date())

        let first = try await sync.archive([loser], originalPath: "Inbox/甲.md", root: root)
        let second = try await sync.archive([loser], originalPath: "Inbox/甲.md", root: root)
        #expect(first[0] != second[0], "第二次归档不能覆盖第一次")
        #expect(FileManager.default.fileExists(atPath: first[0].path))
        #expect(FileManager.default.fileExists(atPath: second[0].path))
    }

    @Test(".conflicts/ 里的文件不会被当成笔记扫回来")
    func archivedFilesAreNotScanned() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = VaultStore(url: root)
        _ = try await store.create(title: "正常想法")

        let sync = CloudSyncService()
        _ = try await sync.archive(
            [.init(id: "iPhone",
                   text: "---\ntype: idea\nid: dup\ntitle: 落败版本\ncreated: 2026-08-01\nstatus: doing\n---\n\n正文\n",
                   modified: Date())],
            originalPath: "Inbox/正常想法.md", root: root)

        let items = await store.reload()
        #expect(items.count == 1, "只应扫到 1 条，实际 \(items.count)")
        #expect(items.first?.title == "正常想法")
        #expect(!items.contains { $0.title == "落败版本" })
    }

    @Test("非 iCloud 文件的状态是 local 且可读")
    func localFileState() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Inbox/a.md")
        try "内容".write(to: file, atomically: true, encoding: .utf8)

        let sync = CloudSyncService()
        let state = sync.state(of: file)
        #expect(state == .local)
        #expect(state.isReadable)
        #expect(state.label == "本地")
    }

    @Test("纯本地 vault 不会报冲突")
    func noConflictsInLocalVault() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VaultStore(url: root)
        _ = try await store.create(title: "甲")
        _ = await store.reload()
        #expect(await store.hasConflicts == false)
        #expect(await store.warnings.isEmpty)
    }

    @Test("状态标签覆盖全部分支，未下载与下载中不可读")
    func stateLabels() {
        #expect(CloudFileState.notDownloaded.isReadable == false)
        #expect(CloudFileState.downloading(progress: nil).isReadable == false)
        #expect(CloudFileState.current.isReadable)
        #expect(CloudFileState.downloaded.isReadable)
        #expect(CloudFileState.notDownloaded.label == "未下载")
        #expect(CloudFileState.downloading(progress: 42).label.contains("42"))
    }

    @Test("冲突告警需要用户介入，未下载告警不需要")
    func warningPriority() {
        #expect(VaultWarning(kind: .conflict(path: "a.md", versions: 2)).needsAttention)
        #expect(VaultWarning(kind: .duplicateAcrossRoots(path: "a", winner: "x", loser: "y")).needsAttention)
        #expect(!VaultWarning(kind: .notDownloaded(path: "a.md")).needsAttention)
        #expect(VaultWarning(kind: .conflict(path: "a.md", versions: 3)).message.contains("3 个冲突版本"))
    }
}

@Suite("裁决结果落盘")
struct ApplyDecisionTests {

    private func makeVault() throws -> (root: URL, file: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lifeos-apply-\(UUID().uuidString)")
        let inbox = root.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let file = inbox.appendingPathComponent("甲.md")
        try current.write(to: file, atomically: true, encoding: .utf8)
        return (root, file)
    }

    private let current = "---\ntype: idea\nid: a\ntitle: 甲\ncreated: 2026-08-01\nupdated: 2026-08-10\nstatus: doing\n---\n\n本机内容\n"
    private let remote = "---\ntype: idea\nid: a\ntitle: 甲\ncreated: 2026-08-01\nupdated: 2026-08-19\nstatus: doing\n---\n\n手机上的内容\n"

    @Test("远端版本胜出时，主文件被更新，本机版本被保留")
    func remoteWins() async throws {
        let (root, file) = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }

        let decision = try #require(ConflictPolicy.decide([
            .init(id: CloudSyncService.currentVersionID, text: current, modified: Date()),
            .init(id: "iPhone", text: remote, modified: Date()),
        ]))
        #expect(decision.winner.id == "iPhone")

        let report = try await CloudSyncService().applyDecision(decision, to: file, root: root)

        // 主文件已更新为胜者
        let after = try String(contentsOf: file, encoding: .utf8)
        #expect(after.contains("手机上的内容"))
        #expect(after.contains("updated: 2026-08-19"))

        // 本机版本没丢
        #expect(report.archived.count == 1)
        let archived = try String(contentsOf: report.archived[0], encoding: .utf8)
        #expect(archived.contains("本机内容"), "落败的本机版本必须完整保留")
        #expect(report.path == "Inbox/甲.md")
        #expect(report.reason.contains("updated"))
    }

    @Test("本机版本胜出时，主文件保持不动，远端版本被保留")
    func localWinsLeavesFileUntouched() async throws {
        let (root, file) = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }

        let before = try String(contentsOf: file, encoding: .utf8)
        let older = "---\ntype: idea\nid: a\ntitle: 甲\ncreated: 2026-08-01\nupdated: 2026-08-05\nstatus: doing\n---\n\n旧的手机内容\n"
        let decision = try #require(ConflictPolicy.decide([
            .init(id: CloudSyncService.currentVersionID, text: current, modified: Date()),
            .init(id: "iPhone", text: older, modified: Date()),
        ]))
        #expect(decision.winner.id == CloudSyncService.currentVersionID)

        let report = try await CloudSyncService().applyDecision(decision, to: file, root: root)

        #expect(try String(contentsOf: file, encoding: .utf8) == before, "胜者是本机时不该重写主文件")
        #expect(report.archived.count == 1)
        #expect(try String(contentsOf: report.archived[0], encoding: .utf8).contains("旧的手机内容"))
    }

    @Test("三方冲突：一胜两保留，一份都不能少")
    func threeWayKeepsAll() async throws {
        let (root, file) = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }

        func note(_ updated: String, _ body: String) -> String {
            "---\ntype: idea\nid: a\ntitle: 甲\ncreated: 2026-08-01\nupdated: \(updated)\nstatus: doing\n---\n\n\(body)\n"
        }
        let decision = try #require(ConflictPolicy.decide([
            .init(id: CloudSyncService.currentVersionID, text: note("2026-08-10", "本机"), modified: Date()),
            .init(id: "iPhone", text: note("2026-08-19", "手机"), modified: Date()),
            .init(id: "iPad", text: note("2026-08-15", "平板"), modified: Date()),
        ]))
        let report = try await CloudSyncService().applyDecision(decision, to: file, root: root)

        #expect(report.winnerID == "iPhone")
        #expect(report.archived.count == 2, "两份落败版本都要保留")
        let texts = try report.archived.map { try String(contentsOf: $0, encoding: .utf8) }
        #expect(texts.contains { $0.contains("本机") })
        #expect(texts.contains { $0.contains("平板") })
        #expect(try String(contentsOf: file, encoding: .utf8).contains("手机"))
    }

    @Test("处理完的文件仍能被正常解析，没被写坏")
    func fileRemainsParseable() async throws {
        let (root, file) = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }

        let decision = try #require(ConflictPolicy.decide([
            .init(id: CloudSyncService.currentVersionID, text: current, modified: Date()),
            .init(id: "iPhone", text: remote, modified: Date()),
        ]))
        _ = try await CloudSyncService().applyDecision(decision, to: file, root: root)

        let item = try #require(Item.from(text: String(contentsOf: file, encoding: .utf8), url: file))
        #expect(item.title == "甲")
        #expect(item.updated == "2026-08-19")
        #expect(item.status == .doing)

        // 整个 vault 扫描仍只看到 1 条（归档的不算）
        let items = await VaultStore(url: root).load()
        #expect(items.count == 1)
    }
}
