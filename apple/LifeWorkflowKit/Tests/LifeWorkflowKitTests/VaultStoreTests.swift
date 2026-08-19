import Foundation
import Testing
@testable import LifeWorkflowKit

/// 每个用例用一个独立临时目录，互不干扰
private func makeTempVault() throws -> (URL, VaultStore) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("lifeos-test-\(UUID().uuidString)")
    for sub in ["Inbox", "Daily", "Projects", "Resources", "Archive"] {
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent(sub), withIntermediateDirectories: true)
    }
    return (dir, VaultStore(url: dir))
}

@Suite("vault 读写")
struct VaultStoreTests {

    // 对应 Python: TestRepository.test_create_read_update
    @Test("新建 → 修改 → 重新加载无损")
    func createReadUpdate() async throws {
        let (dir, store) = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: dir) }

        var item = try await store.create(title: "我的想法", body: "# 我的想法\n\n内容\n")
        #expect(FileManager.default.fileExists(atPath: try #require(item.url).path))

        item.status = .doing
        item.addThinkingNote("有进展了")
        try await store.save(&item)

        let fresh = await VaultStore(url: dir).load()
        #expect(fresh.count == 1)
        #expect(fresh[0].status == .doing)
        #expect(fresh[0].thinkingNotes.last?.note == "有进展了")
    }

    // 对应 Python: TestRepository.test_filename_sanitised_and_deduped
    @Test("文件名清洗与去重")
    func filenameSanitising() async throws {
        #expect(VaultStore.safeFilename("a/b:c*d") == "a-b-c-d")
        #expect(VaultStore.safeFilename("") == "未命名")
        #expect(VaultStore.safeFilename("  . 前后空白 .  ") == "前后空白")

        let (dir, store) = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try await store.create(title: "同名")
        let b = try await store.create(title: "同名")
        #expect(a.url != b.url)
    }

    // 对应 Python: TestRepository.test_query_filters
    @Test("查询过滤")
    func queryFilters() async throws {
        let (dir, store) = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await store.create(title: "甲", status: .doing)
        _ = try await store.create(title: "乙", status: .done)

        #expect(await store.query(statuses: [.doing]).count == 1)
        #expect(await store.query(text: "甲").count == 1)
        #expect(await store.query(types: [.idea]).count == 2)
        #expect(await store.query(text: "不存在").isEmpty)
    }

    // 对应 Python: TestRepository.test_capture_appends_and_toggles
    @Test("捕获追加与勾选")
    func captureAndToggle() async throws {
        let (dir, store) = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = try await store.capture("第一条")
        _ = try await store.capture("第二条")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.components(separatedBy: "- [ ]").count - 1 == 2)
        #expect(text.hasPrefix("# 收件箱"))

        let log = await store.captureLog()
        let first = try #require(log.first)
        #expect(first.lines.count == 2)
        #expect(try await store.toggleCaptureLine(date: first.date, rawLine: first.lines[0]))
        #expect(try String(contentsOf: url, encoding: .utf8).contains("- [x]"))
    }

    // 对应 Python: TestRepository.test_capture_rejects_empty
    @Test("空捕获被拒")
    func captureRejectsEmpty() async throws {
        let (dir, store) = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: VaultError.self) { try await store.capture("   ") }
    }

    // 对应 Python: TestRepository.test_upsert_section_replaces_not_duplicates
    @Test("段落写入是替换而非追加")
    func upsertSection() async throws {
        let (dir, store) = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: dir) }

        let note = await store.dailyNote()
        try await store.upsertSection(at: note, heading: "提醒", content: "- [ ] 甲")
        try await store.upsertSection(at: note, heading: "日程", content: "- 会议")
        try await store.upsertSection(at: note, heading: "提醒", content: "- [ ] 乙")

        let text = try String(contentsOf: note, encoding: .utf8)
        #expect(text.components(separatedBy: "## 提醒").count - 1 == 1, "提醒段不能重复")
        #expect(text.contains("- [ ] 乙"))
        #expect(!text.contains("- [ ] 甲"))
        #expect(text.contains("## 日程"), "别的段落不能被冲掉")
        #expect(text.contains("- 会议"))
    }

    // 对应 Python: TestRepository.test_archive_moves_and_sets_status
    @Test("归档移动文件并置状态")
    func archive() async throws {
        let (dir, store) = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: dir) }
        var item = try await store.create(title: "待归档")
        let url = try await store.archive(&item)
        #expect(url.deletingLastPathComponent().lastPathComponent == "Archive")
        #expect(item.status == .archived)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    // 对应 Python: TestRepository.test_delete_goes_to_trash
    @Test("删除进回收站而非真删")
    func deleteToTrash() async throws {
        let (dir, store) = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: dir) }
        let item = try await store.create(title: "待删")
        let old = try #require(item.url)
        let target = try #require(try await store.delete(item))
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(target.path.contains(".trash"))
    }

    // 对应 Python: TestRepository.test_skips_templates_and_hidden
    @Test("跳过模板与隐藏目录")
    func skipsTemplates() async throws {
        let (dir, store) = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tpl = dir.appendingPathComponent("Templates")
        try FileManager.default.createDirectory(at: tpl, withIntermediateDirectories: true)
        try "---\ntype: idea\nstatus: seed\n---\n".write(
            to: tpl.appendingPathComponent("t.md"), atomically: true, encoding: .utf8)
        _ = try await store.create(title: "正常")
        #expect(await store.reload().count == 1)
    }

    // 对应 Python: TestRepository.test_atomic_write_leaves_no_tmp
    @Test("原子写不留临时文件")
    func atomicWriteNoTemp() async throws {
        let (dir, store) = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await store.create(title: "原子写")
        let leftovers = VaultStore.markdownFiles(under: dir)
            .filter { $0.lastPathComponent.contains(".tmp") }
        #expect(leftovers.isEmpty)
        let all = try FileManager.default.subpathsOfDirectory(atPath: dir.path)
        #expect(!all.contains { $0.contains("tmp-") })
    }

    @Test("并发写入 100 条不损坏、无残留")
    func concurrentWrites() async throws {
        let (dir, store) = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: dir) }

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    _ = try? await store.create(title: "并发-\(i)", body: "# 并发-\(i)\n\n内容\n")
                }
            }
        }
        let items = await VaultStore(url: dir).load()
        #expect(items.count == 100, "实际 \(items.count) 条")
        #expect(Set(items.map(\.title)).count == 100, "标题应无重复覆盖")
        let all = try FileManager.default.subpathsOfDirectory(atPath: dir.path)
        #expect(!all.contains { $0.contains("tmp-") }, "不应残留临时文件")
    }
}

@Suite("复合 vault（只同步子集）")
struct CompositeVaultTests {

    private func makeComposite() throws -> (icloud: URL, local: URL, store: VaultStore) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("lifeos-composite-\(UUID().uuidString)")
        let icloud = base.appendingPathComponent("iCloud")
        let local = base.appendingPathComponent("Local")
        for sub in ["Inbox", "Daily", "Projects"] {
            try FileManager.default.createDirectory(
                at: icloud.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        for sub in ["Resources", "Archive"] {
            try FileManager.default.createDirectory(
                at: local.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        // needsCoordination 关掉：临时目录不是真 iCloud 容器，协调会拖慢测试
        let store = VaultStore(roots: [
            VaultRoot(id: "icloud", url: icloud, folders: VaultRoot.syncedFolders,
                      needsCoordination: false, displayName: "iCloud"),
            .local(local),
        ])
        return (icloud, local, store)
    }

    @Test("想法落 iCloud 根，资料落本地根")
    func routing() async throws {
        let (icloud, local, store) = try makeComposite()
        defer { try? FileManager.default.removeItem(at: icloud.deletingLastPathComponent()) }

        let idea = try await store.create(title: "想法上云", type: .idea)
        let note = try await store.create(title: "资料留本地", type: .note)

        #expect(try #require(idea.url).path.hasPrefix(icloud.path), "想法应落 iCloud 根")
        #expect(try #require(note.url).path.hasPrefix(local.path), "笔记应落本地根")
        #expect(idea.rootID == "icloud")
        #expect(note.rootID == "local")
    }

    @Test("两个根的内容合并为单一视图")
    func mergedView() async throws {
        let (icloud, _, store) = try makeComposite()
        defer { try? FileManager.default.removeItem(at: icloud.deletingLastPathComponent()) }
        _ = try await store.create(title: "甲", type: .idea)
        _ = try await store.create(title: "乙", type: .note)
        let all = await store.reload()
        #expect(all.count == 2)
        #expect(Set(all.compactMap(\.rootID)) == ["icloud", "local"])
    }

    @Test("同路径重复时 iCloud 优先并告警，不静默")
    func duplicateWarns() async throws {
        let (icloud, local, store) = try makeComposite()
        defer { try? FileManager.default.removeItem(at: icloud.deletingLastPathComponent()) }

        let content = "---\ntype: idea\nid: dup\ntitle: 重复\ncreated: 2026-08-01\nstatus: seed\n---\n\n正文\n"
        for root in [icloud, local] {
            let dir = root.appendingPathComponent("Inbox")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try content.write(to: dir.appendingPathComponent("重复.md"),
                              atomically: true, encoding: .utf8)
        }

        let items = await store.reload()
        #expect(items.filter { $0.title == "重复" }.count == 1, "重复路径只应保留一份")
        #expect(items.first { $0.title == "重复" }?.rootID == "icloud", "应采用 iCloud 版本")
        let warnings = await store.warnings
        #expect(warnings.contains { $0.message.contains("重复") }, "必须告警：\(warnings)")
    }

    @Test("捕获写到 iCloud 根（手机才看得到）")
    func captureGoesToICloud() async throws {
        let (icloud, _, store) = try makeComposite()
        defer { try? FileManager.default.removeItem(at: icloud.deletingLastPathComponent()) }
        let url = try await store.capture("随身记一条")
        #expect(url.path.hasPrefix(icloud.path))
    }
}
