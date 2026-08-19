import Foundation

/// 冲突裁决策略 —— **纯函数，不碰文件系统**，因此可以被完整测试。
///
/// iCloud 两端同时改同一个文件时会产生多个版本。这里决定「谁赢」，
/// 但**永远不丢弃输的那一份**：调用方负责把落败版本存进 `.conflicts/`。
///
/// 裁决顺序（每一层平手才看下一层）：
/// 1. frontmatter 的 `updated` 更新者胜 —— 这是用户显式表达的「我改过」；
/// 2. `lastActivity` 更新者胜 —— 含思路注释日期，能反映实际演进；
/// 3. 文件修改时间更晚者胜；
/// 4. 内容更长者胜 —— 同一时刻的两份里，信息多的那份更可能是「加了东西」；
/// 5. 全平手 —— 取第一个（此时两份实质等价）。
public enum ConflictPolicy {

    public struct Candidate: Sendable, Equatable {
        /// 用于回溯来源（"current" 或 iCloud 版本的 localizedName）
        public let id: String
        public let text: String
        public let modified: Date

        public init(id: String, text: String, modified: Date) {
            self.id = id
            self.text = text
            self.modified = modified
        }

        /// frontmatter 里的 updated（没有则空串）
        public var updated: String {
            let (fm, _) = FrontmatterParser.parse(text)
            return DateOnly.normalize(fm.string("updated"))
        }

        /// 含思路注释在内的最近活动日期
        public var lastActivity: String {
            guard let item = Item.from(text: text) else { return updated }
            return item.lastActivity
        }
    }

    public struct Decision: Sendable, Equatable {
        public let winner: Candidate
        public let losers: [Candidate]
        /// 人话解释「为什么它赢」，直接展示给用户，避免黑箱
        public let reason: String
    }

    /// 从若干候选里裁决。空数组返回 nil；单个候选直接胜出。
    public static func decide(_ candidates: [Candidate]) -> Decision? {
        guard let first = candidates.first else { return nil }
        guard candidates.count > 1 else {
            return Decision(winner: first, losers: [], reason: "只有一个版本")
        }

        var best = first
        var reason = "内容一致"
        for candidate in candidates.dropFirst() {
            let (winner, why) = better(best, candidate)
            if winner != best { reason = why }
            else if best == first && reason == "内容一致" { reason = why }
            best = winner
        }
        // 重新算一遍胜因，保证解释对应最终胜者
        reason = explain(winner: best, others: candidates.filter { $0 != best })
        return Decision(winner: best,
                        losers: candidates.filter { $0.id != best.id },
                        reason: reason)
    }

    /// 两两比较，返回胜者与胜因
    static func better(_ a: Candidate, _ b: Candidate) -> (Candidate, String) {
        if a.updated != b.updated {
            return a.updated > b.updated
                ? (a, "updated 更新（\(a.updated) > \(b.updated)）")
                : (b, "updated 更新（\(b.updated) > \(a.updated)）")
        }
        if a.lastActivity != b.lastActivity {
            return a.lastActivity > b.lastActivity
                ? (a, "最近活动更新（\(a.lastActivity)）")
                : (b, "最近活动更新（\(b.lastActivity)）")
        }
        if a.modified != b.modified {
            return a.modified > b.modified ? (a, "文件修改时间更晚") : (b, "文件修改时间更晚")
        }
        if a.text.count != b.text.count {
            return a.text.count > b.text.count ? (a, "内容更完整") : (b, "内容更完整")
        }
        return (a, "内容一致")
    }

    static func explain(winner: Candidate, others: [Candidate]) -> String {
        guard let other = others.first else { return "只有一个版本" }
        return better(winner, other).1
    }
}
