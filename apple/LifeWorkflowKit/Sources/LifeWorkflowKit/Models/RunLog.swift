import Foundation

/// 一次 agent 操作的留痕：输入、工具、过程、产出、错误、耗时、模型、复盘备注。
public struct RunLog: Sendable, Codable, Hashable, Identifiable {
    public enum Status: String, Sendable, Codable, CaseIterable {
        case success, partial, failed

        public var icon: String {
            switch self {
            case .success: "✅"
            case .partial: "🟡"
            case .failed: "❌"
            }
        }

        public var label: String {
            switch self {
            case .success: "成功"
            case .partial: "部分"
            case .failed: "失败"
            }
        }

        public var colorHex: String {
            switch self {
            case .success: "#10b981"
            case .partial: "#f59e0b"
            case .failed: "#ef4444"
            }
        }

        public static func coerce(_ raw: String?) -> Status {
            guard let raw else { return .success }
            return Status(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased()) ?? .success
        }
    }

    public var runID: String
    /// ISO8601 UTC，形如 2026-08-19T13:05:00Z
    public var timestamp: String
    public var agent: String
    public var objective: String
    public var inputPromptRef: String
    public var toolsUsed: [String]
    public var processSummary: String
    public var outputs: [String]
    public var status: Status
    public var errors: [String]
    public var durationSeconds: Double
    public var model: String
    public var notes: String

    public var id: String { runID }
    /// 日期部分，用于按天聚合
    public var date: String { String(timestamp.prefix(10)) }

    public init(
        objective: String,
        runID: String = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased(),
        timestamp: String = RunLog.nowUTC(),
        agent: String = "agent",
        inputPromptRef: String = "",
        toolsUsed: [String] = [],
        processSummary: String = "",
        outputs: [String] = [],
        status: Status = .success,
        errors: [String] = [],
        durationSeconds: Double = 0,
        model: String = "",
        notes: String = ""
    ) {
        self.objective = objective
        self.runID = runID
        self.timestamp = timestamp
        self.agent = agent
        self.inputPromptRef = inputPromptRef
        self.toolsUsed = toolsUsed
        self.processSummary = processSummary
        self.outputs = outputs
        self.status = status
        self.errors = errors
        self.durationSeconds = durationSeconds
        self.model = model
        self.notes = notes
    }

    public static func nowUTC(_ date: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // JSONL 里用的是 Python 版的 snake_case 键名，必须逐字对齐才能互读
    private enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case timestamp, agent, objective
        case inputPromptRef = "input_prompt_ref"
        case toolsUsed = "tools_used"
        case processSummary = "process_summary"
        case outputs, status, errors
        case durationSeconds = "duration_seconds"
        case model, notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.objective = try c.decodeIfPresent(String.self, forKey: .objective) ?? ""
        self.runID = try c.decodeIfPresent(String.self, forKey: .runID) ?? ""
        self.timestamp = try c.decodeIfPresent(String.self, forKey: .timestamp) ?? ""
        self.agent = try c.decodeIfPresent(String.self, forKey: .agent) ?? "agent"
        self.inputPromptRef = try c.decodeIfPresent(String.self, forKey: .inputPromptRef) ?? ""
        self.toolsUsed = try c.decodeIfPresent([String].self, forKey: .toolsUsed) ?? []
        self.processSummary = try c.decodeIfPresent(String.self, forKey: .processSummary) ?? ""
        self.outputs = try c.decodeIfPresent([String].self, forKey: .outputs) ?? []
        self.status = Status.coerce(try c.decodeIfPresent(String.self, forKey: .status))
        self.errors = try c.decodeIfPresent([String].self, forKey: .errors) ?? []
        self.durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        self.model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(runID, forKey: .runID)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(agent, forKey: .agent)
        try c.encode(objective, forKey: .objective)
        try c.encode(inputPromptRef, forKey: .inputPromptRef)
        try c.encode(toolsUsed, forKey: .toolsUsed)
        try c.encode(processSummary, forKey: .processSummary)
        try c.encode(outputs, forKey: .outputs)
        try c.encode(status.rawValue, forKey: .status)
        try c.encode(errors, forKey: .errors)
        try c.encode(durationSeconds, forKey: .durationSeconds)
        try c.encode(model, forKey: .model)
        try c.encode(notes, forKey: .notes)
    }
}
