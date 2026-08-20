import Foundation

/// 从运行日志算真实世界的效率与稳健性。
///
/// 不新建遥测系统：`run-log.jsonl` 里已经有每次操作的耗时、成败、工具、备注，
/// 应用自己的转换/git/提示词操作也都会自动留痕。缺的只是聚合。
public enum RuntimeStats {

    public struct Operation: Sendable, Identifiable, Equatable {
        public var kind: String
        public var count: Int
        public var successCount: Int
        /// 毫秒
        public var p50: Double
        public var p95: Double
        public var max: Double
        public var total: Double
        /// 转换类操作才有意义；nil 表示不适用
        public var cacheHitRate: Double?

        public var id: String { kind }
        public var successRate: Double { count == 0 ? 0 : Double(successCount) / Double(count) }
        public var failureCount: Int { count - successCount }
    }

    /// 按操作类型聚合。
    ///
    /// 类型从 objective 的**首个词组**推出（空格、冒号之前的部分）：
    /// 「转换 论文.pdf → docx」→ 转换，「重写提示词：xxx」→ 重写提示词。
    /// 粗但够用——目的是分组看耗时分布，不是做精确的语义分类。
    public static func byOperation(_ logs: [RunLog]) -> [Operation] {
        var groups: [String: [RunLog]] = [:]
        for log in logs where !log.objective.isEmpty {
            groups[kind(of: log.objective), default: []].append(log)
        }
        return groups.map { kind, entries in
            let durations = entries.map(\.durationSeconds).map { $0 * 1000 }.sorted()
            let cacheable = entries.filter { $0.toolsUsed.contains { $0.contains("markitdown") || $0 == "pandoc" } }
            let hits = cacheable.filter { $0.notes.contains("命中缓存") }.count
            return Operation(
                kind: kind,
                count: entries.count,
                successCount: entries.filter { $0.status == .success }.count,
                p50: percentile(durations, 0.5),
                p95: percentile(durations, 0.95),
                max: durations.last ?? 0,
                total: durations.reduce(0, +),
                cacheHitRate: cacheable.isEmpty ? nil : Double(hits) / Double(cacheable.count))
        }
        .sorted { ($1.total, $0.kind) < ($0.total, $1.kind) }
    }

    /// 整体健康度：成功率与总耗时
    public static func overall(_ logs: [RunLog]) -> (successRate: Double, totalSeconds: Double, count: Int) {
        guard !logs.isEmpty else { return (0, 0, 0) }
        let ok = logs.filter { $0.status == .success }.count
        return (Double(ok) / Double(logs.count),
                logs.reduce(0) { $0 + $1.durationSeconds },
                logs.count)
    }

    static func kind(of objective: String) -> String {
        let separators = CharacterSet(charactersIn: " ：:")
        let head = objective.components(separatedBy: separators).first?
            .trimmingCharacters(in: .whitespaces) ?? objective
        return head.isEmpty ? objective : head
    }

    /// 线性插值分位数。样本少时（个位数）分位数意义有限，调用方应一并显示样本量。
    static func percentile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        guard sorted.count > 1 else { return sorted[0] }
        let position = q * Double(sorted.count - 1)
        let lower = Int(position)
        let upper = Swift.min(lower + 1, sorted.count - 1)
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }
}
