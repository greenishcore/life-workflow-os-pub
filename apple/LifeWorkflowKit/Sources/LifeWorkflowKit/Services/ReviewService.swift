import Foundation

/// 从运行日志聚合周复盘：成功率、工具 TopN、错误 TopN、耗时、近期产出。
/// 高频错误就是「该沉淀成 skill」的信号。
public enum ReviewService {

    public struct Stats: Sendable {
        public var since: String = ""
        public var total = 0
        public var byStatus: [RunLog.Status: Int] = [:]
        public var tools: [(name: String, count: Int)] = []
        public var errors: [(message: String, count: Int)] = []
        public var outputs: [String] = []
        public var duration: Double = 0
        public var byDay: [String: Int] = [:]

        public var success: Int { byStatus[.success] ?? 0 }
        public var failed: Int { (byStatus[.failed] ?? 0) + (byStatus[.partial] ?? 0) }
        public var rate: Double { total == 0 ? 0 : Double(success) / Double(total) * 100 }
    }

    public static func defaultSince(days: Int = 7, from today: String = DateOnly.today()) -> String {
        DateOnly.adding(days: -days, to: today) ?? today
    }

    public static func aggregate(_ logs: [RunLog], since: String) -> Stats {
        var s = Stats(since: since)
        var tools: [String: Int] = [:]
        var errors: [String: Int] = [:]
        var days: [String: Int] = [:]

        for log in logs {
            s.total += 1
            s.byStatus[log.status, default: 0] += 1
            for t in log.toolsUsed { tools[t, default: 0] += 1 }
            for e in log.errors { errors[e, default: 0] += 1 }
            s.outputs.append(contentsOf: log.outputs)
            s.duration += log.durationSeconds
            if !log.date.isEmpty { days[log.date, default: 0] += 1 }
        }
        s.tools = tools.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
            .prefix(10).map { (name: $0.key, count: $0.value) }
        s.errors = errors.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
            .prefix(10).map { (message: $0.key, count: $0.value) }
        s.byDay = days
        return s
    }

    /// 渲染为 Markdown 报告（与 Python 版同格式）
    public static func renderMarkdown(_ s: Stats, now: String = DateOnly.today()) -> String {
        var lines = [
            "# 周复盘 \(s.since) 起", "",
            "> 自动生成于 \(now)，数据源 `logs/run-log.jsonl`", "",
            "## 总览",
            "- 运行次数：\(s.total)",
            "- 成功率：\(String(format: "%.0f", s.rate))%（成功 \(s.success) / 失败 \(s.failed)）",
            "- 总耗时：\(String(format: "%.0f", s.duration)) 秒", "",
            "## 工具使用 TopN",
        ]
        lines += s.tools.isEmpty ? ["- （无）"] : s.tools.map { "- \($0.name): \($0.count)" }
        lines += ["", "## 错误 TopN（可沉淀为 checklist / skill）"]
        lines += s.errors.isEmpty ? ["- （无）"] : s.errors.map { "- [\($0.count)次] \($0.message)" }
        lines += ["", "## 近期产出"]
        var seen = Set<String>()
        let recent = s.outputs.suffix(30).filter { seen.insert($0).inserted }
        lines += recent.isEmpty ? ["- （无）"] : recent.map { "- `\($0)`" }
        lines += [
            "", "## 复盘结论与待沉淀",
            "- [ ] 把高频错误写成 checklist / 修正脚本",
            "- [ ] 把可复用的成功操作沉淀为 `skills/` 下的 skill",
            "- [ ] 更新提示词库 `prompts/` 的模板", "",
        ]
        return lines.joined(separator: "\n")
    }
}
