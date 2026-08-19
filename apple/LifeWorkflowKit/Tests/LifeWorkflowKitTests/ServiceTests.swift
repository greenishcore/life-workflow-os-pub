import Foundation
import Testing
@testable import LifeWorkflowKit

@Suite("运行日志与复盘")
struct RunLogTests {

    private func makeService() -> (URL, RunLogService) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lifeos-log-\(UUID().uuidString)")
        return (dir, RunLogService(jsonlURL: dir.appendingPathComponent("run-log.jsonl"),
                                   markdownURL: dir.appendingPathComponent("run-log.md")))
    }

    // 对应 Python: TestRunLogAndReview.test_append_and_load
    @Test("追加与读取")
    func appendAndLoad() async throws {
        let (dir, svc) = makeService()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await svc.append(RunLog(objective: "做了事", timestamp: "2026-08-19T10:00:00Z",
                                    toolsUsed: ["bash"], durationSeconds: 2))
        try await svc.append(RunLog(objective: "失败了", timestamp: "2026-08-19T11:00:00Z",
                                    status: .failed, errors: ["boom"]))

        let logs = await svc.load()
        #expect(logs.count == 2)
        #expect(logs[0].objective == "失败了", "应按时间倒序")
        #expect(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("run-log.md").path))

        // JSONL 每行必须是合法 JSON 且含 run_id
        let raw = try String(contentsOf: dir.appendingPathComponent("run-log.jsonl"), encoding: .utf8)
        for line in raw.components(separatedBy: "\n") where !line.isEmpty {
            let obj = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            #expect(obj["run_id"] != nil)
        }
    }

    // 对应 Python: TestRunLogAndReview.test_objective_required
    @Test("objective 必填")
    func objectiveRequired() async throws {
        let (dir, svc) = makeService()
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: RunLogError.self) {
            try await svc.append(RunLog(objective: "   "))
        }
    }

    // 对应 Python: TestRunLogAndReview.test_load_skips_corrupt_lines
    @Test("跳过损坏行，不让一条坏记录毁掉整个复盘")
    func skipsCorruptLines() async throws {
        let (dir, svc) = makeService()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        {"run_id":"a","objective":"ok","timestamp":"2026-08-01T00:00:00Z","status":"success"}
        不是 json
        {"损坏
        """.write(to: dir.appendingPathComponent("run-log.jsonl"), atomically: true, encoding: .utf8)
        #expect(await svc.load().count == 1)
    }

    // 对应 Python: TestRunLogAndReview.test_review_aggregate_and_report
    @Test("周复盘聚合与报告")
    func reviewAggregate() {
        let logs = [
            RunLog(objective: "a", timestamp: "2026-08-19T10:00:00Z",
                   toolsUsed: ["pandoc"], durationSeconds: 3),
            RunLog(objective: "b", timestamp: "2026-08-19T11:00:00Z",
                   status: .failed, errors: ["缺依赖"]),
        ]
        let stats = ReviewService.aggregate(logs, since: "2000-01-01")
        #expect(stats.total == 2)
        #expect(stats.rate == 50)
        #expect(stats.success == 1)
        #expect(stats.failed == 1)
        #expect(stats.errors.first?.message == "缺依赖")
        #expect(stats.tools.first?.name == "pandoc")

        let md = ReviewService.renderMarkdown(stats, now: "2026-08-19")
        #expect(md.contains("成功率：50%"))
        #expect(md.contains("[1次] 缺依赖"))
        #expect(md.contains("## 复盘结论与待沉淀"))
    }

    @Test("Markdown 日志行格式与 Python 版一致")
    func markdownLineFormat() {
        let log = RunLog(objective: "转换 PDF", runID: "abc123def456",
                         timestamp: "2026-08-19T10:00:00Z",
                         toolsUsed: ["markitdown", "pandoc"], outputs: ["out/a.md"],
                         durationSeconds: 12, notes: "下次注意")
        let line = RunLogService.markdownLine(log)
        #expect(line.hasPrefix("- ✅ `abc123def456` 2026-08-19T10:00:00Z **转换 PDF**"))
        #expect(line.contains("| 工具: markitdown, pandoc"))
        #expect(line.contains("| 12s"))
        #expect(line.contains("\n  - 产出: out/a.md"))
        #expect(line.contains("\n  - 复盘: 下次注意"))
    }
}

@Suite("EventKit Markdown 渲染")
struct EventKitRenderTests {

    @Test("提醒渲染为待办清单")
    func remindersMarkdown() {
        let items = [
            EventKitBridge.ReminderItem(title: "买菜", isCompleted: false,
                                        dueDate: "2026-08-20", notes: nil),
            EventKitBridge.ReminderItem(title: "取快递", isCompleted: true,
                                        dueDate: nil, notes: "驿站\n六点前"),
        ]
        let md = EventKitBridge.markdown(for: items)
        #expect(md.contains("- [ ] 买菜 📅 2026-08-20"))
        #expect(md.contains("- [x] 取快递"))
        #expect(md.contains("  - 驿站 六点前"), "多行备注应折成一行")
    }

    @Test("日程按开始时间排序")
    func eventsMarkdown() {
        let base = Date(timeIntervalSince1970: 1_787_000_000)
        let items = [
            EventKitBridge.EventItem(title: "晚会", start: base.addingTimeInterval(7200),
                                     end: base.addingTimeInterval(10800), location: nil),
            EventKitBridge.EventItem(title: "晨会", start: base,
                                     end: base.addingTimeInterval(3600), location: "会议室"),
        ]
        let lines = EventKitBridge.markdown(for: items).components(separatedBy: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].contains("晨会"), "应按开始时间排序")
        #expect(lines[0].contains("@ 会议室"))
        #expect(lines[1].contains("晚会"))
    }

    @Test("空输入返回空串")
    func emptyRender() {
        #expect(EventKitBridge.markdown(for: [] as [EventKitBridge.ReminderItem]).isEmpty)
        #expect(EventKitBridge.markdown(for: [] as [EventKitBridge.EventItem]).isEmpty)
    }

    @Test("watchOS 写入能力在编译期就被关掉")
    func watchOSWriteGate() {
        // 这条断言的意义：把「EventKit 在 watchOS 只读」这个平台硬约束
        // 固化成可测的常量，UI 层据此隐藏按钮，而不是等运行时失败。
        #if os(watchOS)
        #expect(EventKitBridge.canWriteEventKit == false)
        #else
        #expect(EventKitBridge.canWriteEventKit == true)
        #endif
    }
}

@Suite("配置")
struct ConfigTests {

    // 对应 Python: TestConfig.test_derived_paths_follow_vault
    @Test("复合根配置可序列化往返")
    func rootConfigRoundTrip() throws {
        let cfg = AppConfig(roots: [
            .init(id: "icloud", path: "/tmp/icloud", folders: ["Inbox", "Daily", "Projects"],
                  needsCoordination: true, displayName: "iCloud"),
            .init(id: "local", path: "/tmp/local", displayName: "本地"),
        ])
        let data = try JSONEncoder().encode(cfg)
        let back = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(back.roots.count == 2)
        #expect(back.roots[0].needsCoordination)
        #expect(Set(back.roots[0].folders) == VaultRoot.syncedFolders)
    }

    @Test("根路由：具名根优先，兜底根接住其余")
    func rootRouting() {
        let cfg = AppConfig(roots: [
            .init(id: "icloud", path: "/tmp/icloud", folders: ["Inbox", "Daily", "Projects"]),
            .init(id: "local", path: "/tmp/local"),
        ])
        let store = VaultStore(roots: cfg.vaultRoots)
        #expect(store.root(forFolder: "Inbox").id == "icloud")
        #expect(store.root(forFolder: "Projects").id == "icloud")
        #expect(store.root(forFolder: "Resources").id == "local")
        #expect(store.root(forFolder: "随便什么").id == "local", "未知目录落兜底根")
    }

    @Test("watchOS 上 iCloud 容器恒为 nil（平台限制，不是错误）")
    func iCloudUnavailableOnWatch() {
        #if os(watchOS)
        #expect(AppConfig.iCloudDocuments() == nil)
        #endif
        // 非 watchOS 上取决于是否登录 iCloud，不做断言
    }
}

#if os(macOS)
@Suite("Git 服务")
struct GitServiceTests {

    @Test("向上搜索 .git 能找到仓库根")
    func findsRepository() throws {
        // 本仓库自己就是最好的样本
        let here = URL(fileURLWithPath: #filePath)
        let found = try #require(GitService.findRepository(startingAt: here))
        #expect(FileManager.default.fileExists(
            atPath: found.appendingPathComponent(".git").path))
        #expect(found.lastPathComponent == "life-workflow-os")
    }

    @Test("不在仓库里时返回 nil，而不是瞎猜一个路径")
    func returnsNilOutsideRepo() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lifeos-norepo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        // /var/folders/... 往上不会有 .git
        #expect(GitService.findRepository(startingAt: tmp) == nil)
    }

    @Test("语义化版本校验")
    func semverValidation() {
        #expect(GitService.isSemver("v0.2.0"))
        #expect(GitService.isSemver("v10.20.30"))
        #expect(!GitService.isSemver("0.2.0"))
        #expect(!GitService.isSemver("v0.2"))
        #expect(!GitService.isSemver("v0.2.x"))
        #expect(!GitService.isSemver(""))
    }

    @Test("读取本仓库的真实状态")
    func realRepoStatus() async throws {
        let repo = try #require(GitService.findRepository(
            startingAt: URL(fileURLWithPath: #filePath)))
        let status = await GitService.status(repo: repo)
        #expect(status.isRepo)
        #expect(!status.branch.isEmpty)
        let history = await GitService.history(repo: repo, limit: 3)
        #expect(!history.isEmpty)
        #expect(history.allSatisfy { !$0.hash.isEmpty && !$0.subject.isEmpty })
    }
}

@Suite("转换服务")
struct ConvertServiceTests {

    @Test("依赖体检覆盖全部工具且路径可信")
    func toolStatus() {
        let tools = ConvertService.toolStatus()
        #expect(tools.count >= 7)
        #expect(tools.contains { $0.name == "pandoc" })
        #expect(tools.contains { $0.name == "chrome" })
        // 已安装的必须给出真实可执行路径
        for tool in tools where tool.installed && tool.name != "chrome" {
            #expect(tool.detail.hasPrefix("/"), "\(tool.name) 应给出绝对路径")
        }
    }

    @Test("sha256 与文件内容一致（缓存键的基础）")
    func hashing() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lifeos-hash-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "hello".write(to: tmp, atomically: true, encoding: .utf8)
        // 已知值：sha256("hello")
        #expect(ConvertService.sha256(of: tmp)
                == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    @Test("markdown 输入直接透传，不进缓存")
    func markdownPassThrough() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lifeos-md-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let src = tmp.appendingPathComponent("a.md")
        try "# 标题\n".write(to: src, atomically: true, encoding: .utf8)

        let config = AppConfig(roots: [.init(id: "local", path: tmp.path)],
                               cachePath: tmp.appendingPathComponent("cache").path)
        let (url, cached, _) = await ConvertService.toMarkdown(source: src, config: config, log: nil)
        #expect(url == src)
        #expect(cached)
    }
}
#endif
