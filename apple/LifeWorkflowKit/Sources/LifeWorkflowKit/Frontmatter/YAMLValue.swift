import Foundation

/// frontmatter 的值模型。
///
/// 只覆盖本项目 frontmatter 实际用到的 YAML 子集——这是有意的：
/// 通用 YAML 库无法保证「输出与手写笔记逐字节同风格」，而那正是本项目的硬要求
/// （字段定序、日期不加引号、tags 内联、thinking_notes 流式）。
///
/// `.date` 与 `.string` 分开，是为了区分「裸写的 2026-08-16」和「加了引号的 "2026-08-16"」，
/// 保证未知字段原样写回时不会给日期平白加上引号。
public indirect enum YAMLValue: Sendable, Hashable {
    case string(String)
    case date(String)        // 裸 YYYY-MM-DD
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([YAMLValue])
    case mapping(YAMLMapping)

    /// 尽力转成字符串（用于读取那些「写成什么都算数」的字段）
    public var stringValue: String? {
        switch self {
        case .string(let s), .date(let s): s
        case .int(let i): String(i)
        case .double(let d): d == d.rounded() ? String(Int(d)) : String(d)
        case .bool(let b): b ? "true" : "false"
        case .null: nil
        case .array, .mapping: nil
        }
    }

    public var intValue: Int? {
        switch self {
        case .int(let i): i
        case .double(let d): Int(d)
        case .string(let s), .date(let s): Int(s.trimmingCharacters(in: .whitespaces)) ?? Int(Double(s) ?? .nan)
        default: nil
        }
    }

    public var arrayValue: [YAMLValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var mappingValue: YAMLMapping? {
        if case .mapping(let m) = self { return m }
        return nil
    }

    /// 字符串列表（跳过空项），对应 Python 版对 tags/next_actions/links 的处理
    public var stringList: [String] {
        guard let items = arrayValue else { return [] }
        return items.compactMap { $0.stringValue }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

/// 保序字典：未知字段必须**按原顺序**写回，不能被重排。
public struct YAMLMapping: Sendable, Hashable, ExpressibleByDictionaryLiteral {
    public private(set) var keys: [String] = []
    private var storage: [String: YAMLValue] = [:]

    public init() {}

    public init(dictionaryLiteral elements: (String, YAMLValue)...) {
        for (k, v) in elements { self[k] = v }
    }

    public subscript(key: String) -> YAMLValue? {
        get { storage[key] }
        set {
            if let newValue {
                if storage[key] == nil { keys.append(key) }
                storage[key] = newValue
            } else {
                keys.removeAll { $0 == key }
                storage[key] = nil
            }
        }
    }

    public var isEmpty: Bool { keys.isEmpty }
    public var count: Int { keys.count }

    public func contains(_ key: String) -> Bool { storage[key] != nil }

    /// 按插入顺序遍历
    public var pairs: [(key: String, value: YAMLValue)] {
        keys.compactMap { k in storage[k].map { (key: k, value: $0) } }
    }

    /// 取出不在给定集合里的字段（用于保留用户手写的未知字段）
    public func excluding(_ known: Set<String>) -> YAMLMapping {
        var out = YAMLMapping()
        for (k, v) in pairs where !known.contains(k) { out[k] = v }
        return out
    }

    public func string(_ key: String) -> String? { self[key]?.stringValue }
    public func int(_ key: String) -> Int? { self[key]?.intValue }
    public func list(_ key: String) -> [String] { self[key]?.stringList ?? [] }
}
