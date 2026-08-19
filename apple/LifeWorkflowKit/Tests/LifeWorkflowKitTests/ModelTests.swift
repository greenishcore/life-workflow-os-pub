import Foundation
import Testing
@testable import LifeWorkflowKit

@Suite("领域模型")
struct ModelTests {

    // 对应 Python: TestModels.test_status_coercion_and_machine
    @Test("状态解析与状态机")
    func statusCoercionAndMachine() {
        #expect(Status.coerce("DOING") == .doing)
        #expect(Status.coerce(" Doing ") == .doing)
        #expect(Status.coerce("不存在") == .seed)
        #expect(Status.coerce(nil) == .seed)
        #expect(Status.seed.next() == .sprout)
        #expect(Status.archived.next() == .archived)
        #expect(Status.doing.label == "推进中")
    }

    // 对应 Python: TestModels.test_priority_weight_ordering
    @Test("优先级权重排序")
    func priorityWeights() {
        #expect(Priority.high.weight > Priority.low.weight)
        #expect(Priority.coerce(nil) == .medium)
        #expect(Priority.coerce("HIGH") == .high)
    }

    // 对应 Python: TestModels.test_norm_date
    @Test("日期归一化")
    func normDate() {
        #expect(DateOnly.normalize("2026-8-6 12:00") == "2026-08-06")
        #expect(DateOnly.normalize("2026-08-06") == "2026-08-06")
        #expect(DateOnly.normalize("不是日期") == "")
        #expect(DateOnly.normalize(nil) == "")
    }

    // 对应 Python: TestModels.test_energy_and_progress_clamped
    @Test("精力与进度越界钳制")
    func clamping() throws {
        let item = try #require(Item.from(
            text: "---\ntype: idea\nstatus: seed\nenergy: 99\nprogress: -5\n---\n"))
        #expect(item.energy == 10)
        #expect(item.progress == 0)
    }

    // 对应 Python: TestModels.test_from_text_requires_type_or_status
    @Test("普通笔记不进看板")
    func requiresTypeOrStatus() {
        #expect(Item.from(text: "---\ntitle: 普通笔记\n---\n正文\n") == nil)
        #expect(Item.from(text: "---\ntype: idea\n---\n正文\n") != nil)
        #expect(Item.from(text: "---\nstatus: doing\n---\n正文\n") != nil)
        #expect(Item.from(text: "# 无 frontmatter\n") == nil)
    }

    // 对应 Python: TestModels.test_save_is_idempotent
    @Test("写回幂等")
    func saveIdempotent() throws {
        let item = Item(title: "幂等", type: .idea, id: "x-1", created: "2026-08-16",
                        updated: "2026-08-16", status: .doing, energy: 5, progress: 50,
                        tags: ["a"], thinkingNotes: [.init(t: "2026-08-16", note: "note")],
                        body: "# 幂等\n")
        let once = item.toText()
        #expect(try #require(Item.from(text: once)).toText() == once)
    }

    // 对应 Python: TestModels.test_last_activity_uses_notes
    @Test("最近活动取思路注释的最新日期")
    func lastActivity() {
        let item = Item(created: "2026-08-01",
                        thinkingNotes: [.init(t: "2026-08-20", note: "later")])
        #expect(item.lastActivity == "2026-08-20")
    }

    // 对应 Python: TestModels.test_matches_searches_notes_and_body
    @Test("搜索覆盖正文与思路注释")
    func matches() {
        let item = Item(title: "标题", thinkingNotes: [.init(t: "2026-08-01", note: "注释关键词")],
                        body: "正文关键词")
        #expect(item.matches("正文关键"))
        #expect(item.matches("注释关键"))
        #expect(item.matches(""))
        #expect(!item.matches("不存在"))
    }

    @Test("RunLog 与 Python 的 JSONL 键名互通")
    func runLogCoding() throws {
        let json = """
        {"run_id":"abc123","timestamp":"2026-08-19T10:00:00Z","objective":"做了事",
         "tools_used":["bash","pandoc"],"outputs":["a.md"],"status":"failed",
         "errors":["boom"],"duration_seconds":12.5,"model":"opus","notes":"下次注意",
         "agent":"agent","input_prompt_ref":"","process_summary":""}
        """
        let log = try JSONDecoder().decode(RunLog.self, from: Data(json.utf8))
        #expect(log.runID == "abc123")
        #expect(log.toolsUsed == ["bash", "pandoc"])
        #expect(log.status == .failed)
        #expect(log.durationSeconds == 12.5)
        #expect(log.date == "2026-08-19")
        #expect(log.status.icon == "❌")

        // 再编码回去，键名必须还是 snake_case
        let encoded = String(data: try JSONEncoder().encode(log), encoding: .utf8) ?? ""
        #expect(encoded.contains("\"run_id\""))
        #expect(encoded.contains("\"duration_seconds\""))
        #expect(encoded.contains("\"tools_used\""))
    }
}

@Suite("统计聚合")
struct StatsTests {
    let items = [
        Item(title: "A", id: "a", created: "2026-08-01", status: .doing, priority: .high,
             energy: 8, progress: 60, tags: ["x"],
             thinkingNotes: [.init(t: "2026-08-01", note: "起"), .init(t: "2026-08-03", note: "转")]),
        Item(title: "B", id: "b", created: "2026-08-02", status: .done, priority: .medium,
             energy: 4, progress: 100, tags: ["x", "y"]),
    ]

    // 对应 Python: TestStats.test_heat_counts_creation_and_notes
    @Test("热力图同时计入创建与思路注释")
    func heat() {
        let heat = Stats.activityHeat(items)
        #expect(heat["2026-08-01"] == 1)   // 创建当天的注释不重复计数
        #expect(heat["2026-08-02"] == 1)
        #expect(heat["2026-08-03"] == 1)
    }

    // 对应 Python: TestStats.test_summary
    @Test("摘要统计")
    func summary() {
        let s = Stats.summarize(items, today: "2026-08-03")
        #expect(s.total == 2)
        #expect(s.active == 1)
        #expect(s.done == 1)
        #expect(s.totalNotes == 2)
        #expect(s.averageProgress == 80)
        #expect(s.spanDays == 3)
    }

    // 对应 Python: TestStats.test_tag_and_status_counts
    @Test("标签与状态计数")
    func counts() {
        #expect(Stats.tagCounts(items).first?.tag == "x")
        #expect(Stats.tagCounts(items).first?.count == 2)
        #expect(Stats.statusCounts(items)[.doing] == 1)
        #expect(Stats.statusCounts(items)[.seed] == 0)
    }

    // 对应 Python: TestStats.test_trajectory_is_newest_first
    @Test("思维轨迹按时间倒序")
    func trajectory() {
        #expect(Stats.trajectory(items).map(\.date) == ["2026-08-03", "2026-08-01"])
    }

    // 对应 Python: TestStats.test_empty_input_is_safe
    @Test("空输入安全")
    func emptySafe() {
        let s = Stats.summarize([])
        #expect(s.total == 0)
        #expect(Stats.activityHeat([]).isEmpty)
        #expect(Stats.streak([]) == 0)
        #expect(Stats.lifelines([]).isEmpty)
    }

    @Test("生命线：补记的早期注释也计入跨度")
    func lifelineBackdated() throws {
        let item = Item(title: "补记", id: "c", created: "2026-08-19", status: .doing, energy: 8,
                        thinkingNotes: [.init(t: "2026-08-17", note: "早"),
                                        .init(t: "2026-08-19", note: "今")])
        let line = try #require(Stats.lifelines([item]).first)
        #expect(line.begin == "2026-08-17")
        #expect(line.end == "2026-08-19")
        #expect(line.hasSpan)
        #expect(line.ticks == ["2026-08-17"])
    }

    @Test("连续活跃天数")
    func streak() {
        let today = "2026-08-19"
        let items = ["2026-08-19", "2026-08-18", "2026-08-17"].map {
            Item(title: $0, id: $0, created: $0, status: .seed)
        }
        #expect(Stats.streak(items, today: today) == 3)
        // 断了一天
        let gapped = ["2026-08-19", "2026-08-17"].map {
            Item(title: $0, id: $0, created: $0, status: .seed)
        }
        #expect(Stats.streak(gapped, today: today) == 1)
    }
}
