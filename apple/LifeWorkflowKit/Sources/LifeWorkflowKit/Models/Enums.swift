import Foundation

/// 想法状态机：seed → sprout → doing → done → archived
///
/// 与 Python 版 `lifeos.models.Status` 行为等价：非法值一律归一为 `.seed`。
public enum Status: String, CaseIterable, Sendable, Codable, Hashable {
    case seed, sprout, doing, done, archived

    public var label: String {
        switch self {
        case .seed: "种子"
        case .sprout: "发芽"
        case .doing: "推进中"
        case .done: "完成"
        case .archived: "归档"
        }
    }

    /// 状态色（与 Python 版、HTML 看板保持一致，换主题也不改）
    public var colorHex: String {
        switch self {
        case .seed: "#f59e0b"
        case .sprout: "#84cc16"
        case .doing: "#3b82f6"
        case .done: "#10b981"
        case .archived: "#9ca3af"
        }
    }

    /// 宽松解析：大小写与空白无关；识别不了就当 seed，绝不抛错。
    public static func coerce(_ raw: String?) -> Status {
        guard let raw else { return .seed }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Status(rawValue: key) ?? .seed
    }

    /// 推进到下一状态；已在末态则停留。
    public func next() -> Status {
        let all = Status.allCases
        guard let i = all.firstIndex(of: self) else { return self }
        return all[min(i + 1, all.count - 1)]
    }
}

public enum Priority: String, CaseIterable, Sendable, Codable, Hashable {
    case high, medium, low

    public var label: String {
        switch self {
        case .high: "高"
        case .medium: "中"
        case .low: "低"
        }
    }

    /// 融合时间轴上的点径权重
    public var weight: Int {
        switch self {
        case .high: 22
        case .medium: 15
        case .low: 10
        }
    }

    public var colorHex: String {
        switch self {
        case .high: "#ef4444"
        case .medium: "#f59e0b"
        case .low: "#94a3b8"
        }
    }

    public static func coerce(_ raw: String?) -> Priority {
        guard let raw else { return .medium }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Priority(rawValue: key) ?? .medium
    }
}

public enum ItemType: String, CaseIterable, Sendable, Codable, Hashable {
    case idea, task, daily, note

    public var label: String {
        switch self {
        case .idea: "想法"
        case .task: "任务"
        case .daily: "日记"
        case .note: "笔记"
        }
    }

    public static func coerce(_ raw: String?) -> ItemType {
        guard let raw else { return .note }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ItemType(rawValue: key) ?? .note
    }
}
