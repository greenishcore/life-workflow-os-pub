import Foundation
import Testing
@testable import LifeWorkflowKit

/// 仓库根目录（用于拿真实笔记做验收）
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // LifeWorkflowKitTests
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // LifeWorkflowKit
    .deletingLastPathComponent()   // apple
    .deletingLastPathComponent()   // repo root

@Suite("Frontmatter 解析与序列化")
struct FrontmatterTests {

    // 对应 Python: TestFrontmatter.test_parse_and_body
    @Test("解析 frontmatter 与正文")
    func parseAndBody() {
        let text = "---\ntype: idea\ntitle: 测试\n---\n\n正文内容\n"
        let (fm, body) = FrontmatterParser.parse(text)
        #expect(fm.string("type") == "idea")
        #expect(fm.string("title") == "测试")
        #expect(body.trimmingCharacters(in: .whitespacesAndNewlines) == "正文内容")
    }

    // 对应 Python: TestFrontmatter.test_no_frontmatter
    @Test("无 frontmatter 时全文当正文")
    func noFrontmatter() {
        let (fm, body) = FrontmatterParser.parse("# 只有正文\n")
        #expect(fm.isEmpty)
        #expect(body == "# 只有正文\n")
    }

    // 对应 Python: TestFrontmatter.test_malformed_yaml_does_not_raise
    @Test("畸形 YAML 不崩溃")
    func malformedDoesNotCrash() {
        let (fm, _) = FrontmatterParser.parse("---\n: : : bad\n\t\tnope\n---\nbody\n")
        _ = fm.count   // 只要没崩就算过
    }

    // 对应 Python: TestFrontmatter.test_field_order_is_deterministic
    @Test("字段顺序确定")
    func fieldOrderDeterministic() {
        var m = YAMLMapping()
        m["tags"] = .array([.string("b")])
        m["type"] = .string("idea")
        m["title"] = .string("x")
        m["status"] = .string("seed")
        let out = FrontmatterEmitter.emit(m)
        let keys = out.split(separator: "\n")
            .filter { !$0.hasPrefix(" ") && $0.contains(":") }
            .map { String($0.split(separator: ":")[0]) }
        #expect(keys == ["type", "title", "status", "tags"])
    }

    // 对应 Python: TestFrontmatter.test_dates_are_unquoted
    @Test("日期字段不加引号")
    func datesUnquoted() {
        var m = YAMLMapping()
        m["created"] = .date("2026-08-16")
        m["updated"] = .date("2026-08-17")
        let out = FrontmatterEmitter.emit(m)
        #expect(out.contains("created: 2026-08-16"))
        #expect(!out.contains("\"2026-08-16\""))
    }

    // 对应 Python: TestFrontmatter.test_special_chars_round_trip
    @Test("特殊字符往返安全")
    func specialCharsRoundTrip() {
        let tricky = [
            "含逗号, 和冒号: 的文本", "带\"引号\"", "[方括号]开头", "{花括号}", "#井号",
            "true", "123", "2026-01-01", "多行\n第二行",
        ]
        var m = YAMLMapping()
        m["thinking_notes"] = .array(tricky.map { note in
            var n = YAMLMapping()
            n["t"] = .date("2026-08-16")
            n["note"] = .string(note)
            return .mapping(n)
        })
        m["tags"] = .array(tricky.prefix(4).map { .string($0) })
        m["next_actions"] = .array(tricky.map { .string($0) })

        let text = FrontmatterEmitter.render(m, body: "body")
        let (back, _) = FrontmatterParser.parse(text)

        let backNotes = (back["thinking_notes"]?.arrayValue ?? [])
            .map { $0.mappingValue?.string("note") ?? "" }
        #expect(backNotes == tricky, "思路注释往返失败：\(backNotes)")
        #expect(back.list("tags") == Array(tricky.prefix(4)))
        #expect(back.list("next_actions") == tricky)
    }

    // 对应 Python: TestFrontmatter.test_unknown_fields_preserved
    @Test("未知字段原样保留")
    func unknownFieldsPreserved() {
        var m = YAMLMapping()
        m["type"] = .string("idea")
        m["自定义字段"] = .string("保留我")
        let (back, _) = FrontmatterParser.parse(FrontmatterEmitter.render(m, body: ""))
        #expect(back.string("自定义字段") == "保留我")
    }

    @Test("行内注释被正确剥离（模板 idea.md 用到）")
    func inlineComment() {
        let (fm, _) = FrontmatterParser.parse("""
        ---
        status: seed            # seed → sprout → doing → done → archived
        energy: 5               # 精力 0–10（可选）
        ---
        """)
        #expect(fm.string("status") == "seed")
        #expect(fm.int("energy") == 5)
    }

    @Test("块标量 |- 多行解析")
    func blockScalar() {
        let (fm, _) = FrontmatterParser.parse("""
        ---
        thinking_notes:
          - t: 2026-08-16
            note: |-
              第一行
              第二行: 带冒号
        ---
        """)
        let note = fm["thinking_notes"]?.arrayValue?.first?.mappingValue?.string("note")
        #expect(note == "第一行\n第二行: 带冒号")
    }
}

