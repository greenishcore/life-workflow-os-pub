import Foundation

/// 想法上的高层动作。
///
/// 抽到核心包而不是写在 App Intent 里，是为了**可测**：
/// Intent 跑在快捷指令/Siri 的调用链里，很难自动化验证；
/// 而这些动作会真的改用户的笔记，是必须被测试盯住的部分。
/// Intent 与界面都只做适配，不重复实现逻辑。
public enum IdeaActions {

    public struct AdvanceResult: Sendable, Equatable {
        public let item: Item
        public let from: Status
        public let to: Status
        /// 已经在末态，什么都没改
        public var didAdvance: Bool { from != to }

        public var message: String {
            didAdvance
                ? "「\(item.title)」已从\(from.label)推进到\(to.label)"
                : "「\(item.title)」已经是最后一个状态了"
        }
    }

    /// 推进到状态机的下一步，并自动留下一条思路注释。
    ///
    /// 自动记注释是有意的：状态变化本身就是想法演进的一部分，
    /// 不记下来的话复盘时只看得到结论，看不到「什么时候动的」。
    @discardableResult
    public static func advance(_ item: inout Item) -> AdvanceResult {
        let from = item.status
        let to = from.next()
        guard to != from else {
            return AdvanceResult(item: item, from: from, to: to)
        }
        item.status = to
        item.addThinkingNote("推进：\(from.label) → \(to.label)")
        return AdvanceResult(item: item, from: from, to: to)
    }

    /// 今天该推进什么：推进中 + 发芽，按最近活动倒序。
    ///
    /// 不含 seed —— 种子是「还没开始想」的，塞进今日清单只会制造噪音。
    public static func todayFocus(_ items: [Item], limit: Int = 3) -> [Item] {
        items
            .filter { $0.status == .doing || $0.status == .sprout }
            .sorted { $0.lastActivity > $1.lastActivity }
            .prefix(max(0, limit))
            .map { $0 }
    }

    /// 把一段随手记提升为想法（标题取首行，并落一条初始思路注释）
    public static func makeIdea(from text: String, firstNote: String = "") -> Item? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let firstLine = trimmed.components(separatedBy: "\n").first ?? trimmed
        let title = String(firstLine.trimmingCharacters(in: .whitespaces).prefix(60))

        let rest = trimmed.dropFirst(firstLine.count).trimmingCharacters(in: .whitespacesAndNewlines)
        var item = Item(title: title.isEmpty ? "未命名想法" : title,
                        type: .idea, id: Item.newID(), created: DateOnly.today(),
                        status: .seed,
                        body: rest.isEmpty ? "# \(title)\n\n" : "# \(title)\n\n\(rest)\n")
        let note = firstNote.trimmingCharacters(in: .whitespacesAndNewlines)
        item.addThinkingNote(note.isEmpty ? "初始想法：\(title)" : note)
        return item
    }
}
