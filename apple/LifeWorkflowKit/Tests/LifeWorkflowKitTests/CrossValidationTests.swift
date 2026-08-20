import Foundation
import Testing
@testable import LifeWorkflowKit

/// 与 Python 实现的**交叉验证**。
///
/// 夹具由 `Tools/genfixtures.sh` 用 Python 版生成并入库：
/// · `*.model.json`   —— Python 解析出的模型字段
/// · `*.expected.md`  —— Python 写回的文件内容
///
/// 这样测试既严格（逐字段 + 逐字节比对另一套已验证实现），
/// 又不依赖运行期装了 Python，CI 上照样能跑。
@Suite("与 Python 实现交叉验证")
struct CrossValidationTests {

    struct Entry: Decodable { let source: String; let key: String }

    /// Python 解析结果的镜像结构
    struct PyModel: Decodable {
        struct Note: Decodable, Equatable { let t: String; let note: String }
        let title: String
        let type: String
        let id: String
        let created: String
        let updated: String
        let status: String
        let priority: String
        let energy: Int?
        let progress: Int?
        let tags: [String]
        let thinking_notes: [Note]
        let next_actions: [String]
        let links: [String]
        let last_activity: String
        let body: String
    }

    static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    static var entries: [Entry] {
        let url = fixturesDir.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return list
    }

    @Test("夹具存在")
    func fixturesPresent() throws {
        try #require(!Self.entries.isEmpty, "夹具缺失，先跑 Tools/genfixtures.sh")
    }

    @Test("Swift 解析结果与 Python 逐字段一致")
    func modelsMatch() throws {
        for entry in Self.entries {
            let source = repoRoot.appendingPathComponent("seed/examples").appendingPathComponent(entry.source)
            let text = try String(contentsOf: source, encoding: .utf8)
            let item = try #require(Item.from(text: text, url: source), "\(entry.source) 应能解析")

            let modelURL = Self.fixturesDir.appendingPathComponent("\(entry.key).model.json")
            let py = try JSONDecoder().decode(PyModel.self, from: Data(contentsOf: modelURL))

            #expect(item.title == py.title, "\(entry.source) title")
            #expect(item.type.rawValue == py.type, "\(entry.source) type")
            #expect(item.id == py.id, "\(entry.source) id")
            #expect(item.created == py.created, "\(entry.source) created")
            #expect(item.updated == py.updated, "\(entry.source) updated")
            #expect(item.status.rawValue == py.status, "\(entry.source) status")
            #expect(item.priority.rawValue == py.priority, "\(entry.source) priority")
            #expect(item.energy == py.energy, "\(entry.source) energy")
            #expect(item.progress == py.progress, "\(entry.source) progress")
            #expect(item.tags == py.tags, "\(entry.source) tags")
            #expect(item.nextActions == py.next_actions, "\(entry.source) next_actions")
            #expect(item.links == py.links, "\(entry.source) links")
            #expect(item.lastActivity == py.last_activity, "\(entry.source) last_activity")
            #expect(item.body.trimmingCharacters(in: .whitespacesAndNewlines) == py.body,
                    "\(entry.source) body")

            let notes = item.thinkingNotes.map { PyModel.Note(t: $0.t, note: $0.note) }
            #expect(notes == py.thinking_notes, "\(entry.source) thinking_notes")
        }
    }

    @Test("Swift 写回内容与 Python 逐字节一致")
    func outputBytesMatch() throws {
        for entry in Self.entries {
            let source = repoRoot.appendingPathComponent("seed/examples").appendingPathComponent(entry.source)
            let text = try String(contentsOf: source, encoding: .utf8)
            let item = try #require(Item.from(text: text, url: source))
            let expectedURL = Self.fixturesDir.appendingPathComponent("\(entry.key).expected.md")
            let expected = try String(contentsOf: expectedURL, encoding: .utf8)

            #expect(item.toText() == expected, """
                \(entry.source) 与 Python 输出不一致
                --- Python ---
                \(expected)
                --- Swift ---
                \(item.toText())
                """)
        }
    }

    @Test("二次保存稳定（不产生噪音 diff）")
    func saveIsStable() throws {
        for entry in Self.entries {
            let source = repoRoot.appendingPathComponent("seed/examples").appendingPathComponent(entry.source)
            let text = try String(contentsOf: source, encoding: .utf8)
            let once = try #require(Item.from(text: text, url: source)).toText()
            let twice = try #require(Item.from(text: once, url: source)).toText()
            #expect(once == twice, "\(entry.source) 二次保存不稳定")
        }
    }

    @Test("只读打开不产生 updated 字段")
    func readOnlyDoesNotTouch() throws {
        let text = "---\ntype: idea\nid: a\ntitle: t\ncreated: 2026-08-01\nstatus: seed\n---\n\n正文\n"
        let item = try #require(Item.from(text: text))
        #expect(!item.toText().contains("updated:"))
        var touched = item
        touched.touch()
        #expect(touched.toText().contains("updated:"))
    }
}
