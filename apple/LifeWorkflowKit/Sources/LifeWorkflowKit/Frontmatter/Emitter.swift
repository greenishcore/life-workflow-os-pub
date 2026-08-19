import Foundation

/// frontmatter 序列化器 —— **确定性**是它唯一的设计目标。
///
/// 三条不变量（都有测试守护，破坏即回退）：
/// 1. 字段顺序固定，否则每次保存都产生噪音 diff，污染 git 历史；
/// 2. 与手写笔记逐字节同风格（`tags: [a, b]`、`- {t: 2026-08-16, note: …}`、日期不加引号），
///    保证 Obsidian、Dataview 与人眼三方都认；
/// 3. 未知字段原样保留，不丢用户手写的东西。
///
/// 与 Python 版 `lifeos/frontmatter.py` 的规则**逐条对齐**，两边可互读互写。
public enum FrontmatterEmitter {

    /// 字段规范顺序（与 docs/02-architecture/data-model.md 一致）
    public static let fieldOrder = [
        "type", "id", "title", "created", "updated", "status", "priority",
        "energy", "progress", "tags", "thinking_notes", "next_actions",
        "links", "source",
    ]
    /// 用内联数组书写的字段
    public static let inlineListFields: Set<String> = ["tags"]
    /// 以裸 `YYYY-MM-DD` 输出的字段（加引号反而与手写惯例不符）
    public static let dateFields: Set<String> = ["created", "updated"]

    private static let plainUnsafeStart = Set("-?:,[]{}#&*!|>'\"%@`")
    private static let yamlKeywords: Set<String> = [
        "true", "false", "null", "yes", "no", "on", "off", "~", "y", "n",
        "True", "False", "Null", "None",
    ]

    // MARK: 对外

    /// 渲染 frontmatter 文本块（不含 `---` 分隔线）。
    public static func emit(_ mapping: YAMLMapping) -> String {
        var lines: [String] = []
        var seen = Set<String>()

        for key in fieldOrder {
            guard let value = mapping[key] else { continue }
            seen.insert(key)
            if case .null = value { continue }

            switch key {
            case "thinking_notes":
                lines += emitThinkingNotes(value)
            default:
                if let items = value.arrayValue {
                    lines += emitList(key: key, items: items)
                } else if dateFields.contains(key) {
                    lines.append("\(key): \(dateScalar(value))")
                } else {
                    lines.append("\(key): \(scalar(value))")
                }
            }
        }

        // 未知字段：保留下来（键名排序，对齐 Python 的 yaml.safe_dump(sort_keys=True)）
        let extras = mapping.excluding(Set(fieldOrder))
        if !extras.isEmpty {
            for key in extras.keys.sorted() {
                guard let value = extras[key] else { continue }
                lines += emitGeneric(key: key, value: value, indent: 0)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 渲染完整文件内容（frontmatter + 正文）。
    public static func render(_ mapping: YAMLMapping, body: String) -> String {
        let head = emit(mapping)
        var trimmed = body
        while trimmed.hasPrefix("\n") { trimmed.removeFirst() }
        while let last = trimmed.last, last.isWhitespace { trimmed.removeLast() }
        return "---\n\(head)\n---\n\n\(trimmed)\n"
    }

    // MARK: 各类型渲染

    private static func emitList(key: String, items: [YAMLValue]) -> [String] {
        let values = items.filter { value in
            if case .null = value { return false }
            if let s = value.stringValue, s.trimmingCharacters(in: .whitespaces).isEmpty { return false }
            return true
        }
        guard !values.isEmpty else { return ["\(key): []"] }
        if inlineListFields.contains(key) {
            return ["\(key): [\(values.map { scalar($0, flow: true) }.joined(separator: ", "))]"]
        }
        return ["\(key):"] + values.map { "  - \(scalar($0))" }
    }

    private static func emitThinkingNotes(_ value: YAMLValue) -> [String] {
        guard let items = value.arrayValue, !items.isEmpty else { return ["thinking_notes: []"] }
        var lines = ["thinking_notes:"]
        for item in items {
            let t: String
            let note: String
            if let m = item.mappingValue {
                t = m.string("t") ?? m.string("date") ?? ""
                note = m.string("note") ?? ""
            } else {
                t = ""
                note = item.stringValue ?? ""
            }
            if note.contains("\n") {
                // 含换行时退化为块式，避免流式映射被换行截断
                lines.append("  - t: \(dateScalar(.string(t)))")
                lines.append("    note: |-")
                lines += note.components(separatedBy: "\n").map { "      \($0)" }
            } else {
                lines.append("  - {t: \(dateScalar(.string(t))), note: \(scalar(.string(note), flow: true))}")
            }
        }
        return lines
    }

    /// 未知字段的通用块式渲染
    private static func emitGeneric(key: String, value: YAMLValue, indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        switch value {
        case .array(let items):
            guard !items.isEmpty else { return ["\(pad)\(key): []"] }
            var out = ["\(pad)\(key):"]
            for item in items {
                if let m = item.mappingValue {
                    var first = true
                    for (k, v) in m.pairs {
                        let prefix = first ? "\(pad)  - " : "\(pad)    "
                        out.append("\(prefix)\(k): \(scalar(v))")
                        first = false
                    }
                } else {
                    out.append("\(pad)  - \(scalar(item))")
                }
            }
            return out
        case .mapping(let m):
            guard !m.isEmpty else { return ["\(pad)\(key): {}"] }
            var out = ["\(pad)\(key):"]
            for k in m.keys.sorted() {
                guard let v = m[k] else { continue }
                out += emitGeneric(key: k, value: v, indent: indent + 2)
            }
            return out
        default:
            return ["\(pad)\(key): \(scalar(value))"]
        }
    }

    // MARK: 标量

    /// 日期字段专用：裸 `YYYY-MM-DD`，识别不出来时退回普通标量。
    static func dateScalar(_ value: YAMLValue) -> String {
        if case .date(let s) = value { return s }
        guard let s = value.stringValue else { return scalar(value) }
        return ScalarParser.isDateShaped(s) ? s : scalar(value)
    }

    /// 把一个标量渲染成 YAML 片段。
    static func scalar(_ value: YAMLValue, flow: Bool = false) -> String {
        switch value {
        case .null: return ""
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return d == d.rounded() ? String(Int(d)) : String(d)
        case .date(let s): return s
        case .array(let items):
            return "[\(items.map { scalar($0, flow: true) }.joined(separator: ", "))]"
        case .mapping(let m):
            let inner = m.pairs.map { "\($0.key): \(scalar($0.value, flow: true))" }
            return "{\(inner.joined(separator: ", "))}"
        case .string(let s):
            return needsQuote(s, flow: flow) ? quoted(s) : s
        }
    }

    /// 是否必须加引号。规则与 Python 版 `_needs_quote` 逐条一致。
    static func needsQuote(_ s: String, flow: Bool) -> Bool {
        if s.isEmpty { return true }
        if s.trimmingCharacters(in: .whitespacesAndNewlines) != s { return true }
        if let first = s.first, plainUnsafeStart.contains(first) { return true }
        if yamlKeywords.contains(s) { return true }
        if s.contains(": ") || s.hasSuffix(":") || s.contains(" #") { return true }
        if s.contains("\n") { return true }
        // 纯数字或日期形态的字符串必须加引号，否则读回来会变成 int/date
        if looksNumeric(s) || ScalarParser.isDateShaped(s) { return true }
        // 流式上下文里，逗号与括号会提前终止标量，必须加引号
        if flow, s.contains(where: { ",[]{}".contains($0) }) { return true }
        return false
    }

    private static func looksNumeric(_ s: String) -> Bool {
        var body = Substring(s)
        if body.hasPrefix("-") || body.hasPrefix("+") { body = body.dropFirst() }
        guard !body.isEmpty else { return false }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    private static func quoted(_ s: String) -> String {
        var out = ""
        for c in s {
            switch c {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            default: out.append(c)
            }
        }
        return "\"\(out)\""
    }
}
