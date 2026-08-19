import Foundation

/// agent 操作日志：JSONL 为主（供程序聚合），Markdown 为辅（供人浏览）。
/// 文件格式与 Python 版 `logs/run-log.jsonl` 完全一致，两边可交替写入同一份日志。
public actor RunLogService {
    private let jsonlURL: URL
    private let markdownURL: URL

    public init(config: AppConfig) {
        self.jsonlURL = config.runLogJSONL
        self.markdownURL = config.runLogMarkdown
    }

    public init(jsonlURL: URL, markdownURL: URL) {
        self.jsonlURL = jsonlURL
        self.markdownURL = markdownURL
    }

    @discardableResult
    public func append(_ log: RunLog) throws -> RunLog {
        guard !log.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RunLogError.missingObjective
        }
        try FileManager.default.createDirectory(
            at: jsonlURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let line = String(data: try encoder.encode(log), encoding: .utf8) ?? "{}"
        try FileIO.append(line + "\n", to: jsonlURL, coordinated: false)
        try FileIO.append(Self.markdownLine(log) + "\n", to: markdownURL, coordinated: false)
        return log
    }

    /// 读取日志（按时间倒序）；`since` 为 `YYYY-MM-DD`。
    /// 单行解析失败就跳过——一条坏记录不该让整个复盘打不开。
    public func load(since: String? = nil) -> [RunLog] {
        guard let text = try? String(contentsOf: jsonlURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text.components(separatedBy: "\n")
            .compactMap { line -> RunLog? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty,
                      let log = try? decoder.decode(RunLog.self, from: Data(trimmed.utf8))
                else { return nil }
                if let since, log.date < since { return nil }
                return log
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    static func markdownLine(_ r: RunLog) -> String {
        var line = "- \(r.status.icon) `\(r.runID)` \(r.timestamp) **\(r.objective)**"
        if !r.toolsUsed.isEmpty { line += " | 工具: \(r.toolsUsed.joined(separator: ", "))" }
        if r.durationSeconds != 0 {
            let d = r.durationSeconds
            line += " | \(d == d.rounded() ? String(Int(d)) : String(d))s"
        }
        if !r.outputs.isEmpty { line += "\n  - 产出: \(r.outputs.joined(separator: ", "))" }
        if !r.errors.isEmpty { line += "\n  - 错误: \(r.errors.joined(separator: "; "))" }
        if !r.notes.isEmpty { line += "\n  - 复盘: \(r.notes)" }
        return line
    }
}

public enum RunLogError: LocalizedError, Sendable {
    case missingObjective
    public var errorDescription: String? {
        switch self {
        case .missingObjective: "「这次做了什么」是必填的"
        }
    }
}
