import Foundation

/// 思路注释：带时间戳的思维轨迹增量。
///
/// 这是本系统区别于普通笔记的关键——记录「想法为什么产生、如何演进」，
/// 复盘时看到的是过程而非只有结论；看板据此把每条想法画成一条生命线。
public struct ThinkingNote: Sendable, Codable, Hashable, Identifiable {
    public var id: UUID
    /// 日期，`YYYY-MM-DD`
    public var t: String
    public var note: String

    public init(t: String = DateOnly.today(), note: String = "", id: UUID = UUID()) {
        self.t = t
        self.note = note
        self.id = id
    }

    /// id 不参与相等判断与持久化：它只是 SwiftUI 列表的稳定标识
    public static func == (lhs: ThinkingNote, rhs: ThinkingNote) -> Bool {
        lhs.t == rhs.t && lhs.note == rhs.note
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(t)
        hasher.combine(note)
    }

    private enum CodingKeys: String, CodingKey { case t, note }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.t = try c.decodeIfPresent(String.self, forKey: .t) ?? DateOnly.today()
        self.note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        self.id = UUID()
    }
}
