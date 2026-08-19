import Foundation

/// 看板所需的统计聚合（纯函数，无 UI 依赖）。
///
/// 「融合时间」的含义：同一份数据同时按 时间 / 状态 / 优先级 / 精力 / 思维轨迹
/// 多个维度聚合，让看板能回答「这个想法何时产生、如何演进、现在到哪一步」。
public enum Stats {

    /// 融合时间轴上的一条**生命线**：起点=产生日，沿线刻度=每次思路演进。
    public struct Lifeline: Sendable, Identifiable, Hashable {
        public let id: String
        public let title: String
        public let begin: String
        public let end: String
        /// 思路注释的日期刻度（已去重排序，不含起点）
        public let ticks: [String]
        public let energy: Int
        public let status: Status
        public let priority: Priority
        public var hasSpan: Bool { begin != end }

        public init(id: String, title: String, begin: String, end: String, ticks: [String],
                    energy: Int, status: Status, priority: Priority) {
            self.id = id
            self.title = title
            self.begin = begin
            self.end = end
            self.ticks = ticks
            self.energy = energy
            self.status = status
            self.priority = priority
        }
    }

    public struct Summary: Sendable, Hashable {
        public var total = 0
        public var byStatus: [Status: Int] = [:]
        public var byPriority: [Priority: Int] = [:]
        public var active = 0
        public var done = 0
        public var averageProgress = 0.0
        public var totalNotes = 0
        public var streak = 0
        public var spanDays = 0

        public init() {}
    }

    /// 每日活跃度 = 当天新建的记录数 + 当天写下的思路注释数。
    /// 比「只数创建」更能反映真实投入：一个想法持续演进也算活跃。
    public static func activityHeat(_ items: [Item]) -> [String: Int] {
        var heat: [String: Int] = [:]
        for item in items {
            if !item.created.isEmpty { heat[item.created, default: 0] += 1 }
            for note in item.thinkingNotes where !note.t.isEmpty && note.t != item.created {
                heat[note.t, default: 0] += 1
            }
        }
        return heat
    }

    public static func statusCounts(_ items: [Item]) -> [Status: Int] {
        var counts: [Status: Int] = [:]
        for s in Status.allCases { counts[s] = 0 }
        for item in items { counts[item.status, default: 0] += 1 }
        return counts
    }

    public static func priorityCounts(_ items: [Item]) -> [Priority: Int] {
        var counts: [Priority: Int] = [:]
        for p in Priority.allCases { counts[p] = 0 }
        for item in items { counts[item.priority, default: 0] += 1 }
        return counts
    }

    public static func tagCounts(_ items: [Item], top: Int = 12) -> [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in items { for t in item.tags { counts[t, default: 0] += 1 } }
        return counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
            .prefix(top).map { (tag: $0.key, count: $0.value) }
    }

    /// 生命线：跨度取「创建日 ∪ 所有注释日」，注释日期早于创建日（补记）时也画得出来。
    public static func lifelines(_ items: [Item]) -> [Lifeline] {
        items.compactMap { item in
            guard !item.created.isEmpty else { return nil }
            let noteDays = Set(item.thinkingNotes.map(\.t).filter { !$0.isEmpty })
            let all = noteDays.union([item.created]).sorted()
            return Lifeline(
                id: item.id.isEmpty ? item.title : item.id,
                title: item.title,
                begin: all.first ?? item.created,
                end: all.last ?? item.created,
                ticks: noteDays.filter { $0 != item.created }.sorted(),
                energy: item.energy ?? 0,
                status: item.status,
                priority: item.priority
            )
        }
    }

    /// 全库思维轨迹：所有思路注释按时间倒序铺平
    public static func trajectory(_ items: [Item]) -> [(date: String, note: String, item: Item)] {
        items.flatMap { item in
            item.thinkingNotes.filter { !$0.note.isEmpty }.map { (date: $0.t, note: $0.note, item: item) }
        }.sorted { $0.date > $1.date }
    }

    public static func dateRange(_ items: [Item]) -> (lo: String, hi: String) {
        var dates: [String] = []
        for item in items {
            if !item.created.isEmpty { dates.append(item.created) }
            dates.append(contentsOf: item.thinkingNotes.map(\.t).filter { !$0.isEmpty })
        }
        guard let lo = dates.min(), let hi = dates.max() else {
            let t = DateOnly.today()
            return (t, t)
        }
        return (lo, hi)
    }

    /// 从今天往回数，连续有活跃记录的天数。今天还没记录也不算断，从昨天起算。
    public static func streak(_ items: [Item], today: String = DateOnly.today()) -> Int {
        let heat = activityHeat(items)
        guard !heat.isEmpty else { return 0 }
        var cursor = today
        if heat[cursor] == nil {
            guard let yesterday = DateOnly.adding(days: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var n = 0
        while heat[cursor] != nil {
            n += 1
            guard let prev = DateOnly.adding(days: -1, to: cursor) else { break }
            cursor = prev
        }
        return n
    }

    public static func summarize(_ items: [Item], today: String = DateOnly.today()) -> Summary {
        var s = Summary()
        s.total = items.count
        s.byStatus = statusCounts(items)
        s.byPriority = priorityCounts(items)
        s.active = s.byStatus[.doing] ?? 0
        s.done = s.byStatus[.done] ?? 0
        let progresses = items.compactMap(\.progress)
        s.averageProgress = progresses.isEmpty
            ? 0 : Double(progresses.reduce(0, +)) / Double(progresses.count)
        s.totalNotes = items.reduce(0) { $0 + $1.thinkingNotes.count }
        s.streak = streak(items, today: today)
        let (lo, hi) = dateRange(items)
        s.spanDays = items.isEmpty ? 0 : ((DateOnly.daysBetween(lo, hi) ?? 0) + 1)
        return s
    }

    /// 进度分布（柱状图用）
    public static func progressBuckets(_ items: [Item], buckets: Int = 5) -> [(label: String, count: Int)] {
        var counts = [Int](repeating: 0, count: buckets)
        for item in items {
            guard let p = item.progress else { continue }
            counts[min(p * buckets / 100, buckets - 1)] += 1
        }
        return (0..<buckets).map { i in
            (label: "\(i * 100 / buckets)-\((i + 1) * 100 / buckets)%", count: counts[i])
        }
    }
}
