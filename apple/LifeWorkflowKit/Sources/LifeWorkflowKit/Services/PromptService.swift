import Foundation

/// 交互前把口语需求重写为结构化提示词文档。
///
/// 两种模式：脚手架（离线，生成五段式骨架）与 LLM 重写（OpenAI 兼容接口）。
/// 原始需求归档到 prompts/00_inbox/，重写结果落 prompts/01_rewritten/，都纳入版本控制。
public enum PromptService {

    public struct Document: Sendable {
        public let id: String
        public let rawURL: URL
        public let outputURL: URL
        public let content: String
        public let mode: Mode
    }

    public enum Mode: String, Sendable {
        case scaffold, llm
        public var label: String {
            switch self {
            case .scaffold: "脚手架"
            case .llm: "LLM 重写"
            }
        }
    }

    public static let metaInstruction = """
    你是一名提示词工程专家。请把用户的口语化需求改写为结构化的任务提示词文档。
    要求：
    1) 输出为 Markdown，按「角色 / 背景 / 目标 / 约束 / 输出格式 / 验收标准」组织；
    2) 目标与验收标准必须可客观验证（含具体数值或示例）；
    3) 若原话有歧义，单独列「待确认问题」段，不要擅自假设；
    4) 保持原文语义，只做结构化与显式化，不添加原文没有的新需求；
    5) 语言与用户原话保持一致。
    """

    /// API Key 只从环境变量读，绝不落盘
    public static var llmAvailable: Bool {
        !(ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "").isEmpty
    }

    public static func rewrite(
        _ raw: String, useLLM: Bool = false, config: AppConfig
    ) async throws -> Document {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw PromptError.emptyRequest }

        let inbox = config.promptsURL.appendingPathComponent("00_inbox")
        let rewritten = config.promptsURL.appendingPathComponent("01_rewritten")
        for dir in [inbox, rewritten] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let id = "\(stamp())-\(String(UUID().uuidString.prefix(6)).lowercased())"
        let rawURL = inbox.appendingPathComponent("\(id).md")
        try """
        ---
        type: raw-request
        id: \(id)
        created: \(DateOnly.today())
        ---

        \(text)
        """.write(to: rawURL, atomically: true, encoding: .utf8)

        let content: String
        let mode: Mode
        if useLLM {
            content = try await llmRewrite(text, config: config)
            mode = .llm
        } else {
            content = scaffold(text, id: id)
            mode = .scaffold
        }

        let outputURL = rewritten.appendingPathComponent("\(id).md")
        try content.write(to: outputURL, atomically: true, encoding: .utf8)
        return Document(id: id, rawURL: rawURL, outputURL: outputURL, content: content, mode: mode)
    }

    public static func list(config: AppConfig) -> [URL] {
        let dir = config.promptsURL.appendingPathComponent("01_rewritten")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    // MARK: 私有

    static func scaffold(_ raw: String, id: String) -> String {
        """
        ---
        type: prompt
        id: \(id)
        created: \(DateOnly.today())
        target: agent
        tags: [prompt]
        ---

        # 任务标题（一句话概括）

        ## 1. 角色（Role）
        > 你是一名…

        ## 2. 背景（Context）
        - 原始需求（口语化）：
          > \(raw.replacingOccurrences(of: "\n", with: "\n  > "))

        ## 3. 目标（Objective）
        - 需要交付的明确结果

        ## 4. 约束（Constraints）
        - 语言/格式/范围/禁止事项

        ## 5. 输出格式（Output Format）
        - 指定结构、语言、长度

        ## 6. 验收标准（Acceptance Criteria）
        - [ ] 可客观验证的完成条件

        ## 7. 待确认问题（如有歧义）
        - 
        """
    }

    static func llmRewrite(_ raw: String, config: AppConfig) async throws -> String {
        guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty else {
            throw PromptError.missingAPIKey
        }
        guard let url = URL(string: config.openAIBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                            + "/chat/completions") else {
            throw PromptError.badEndpoint(config.openAIBaseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": config.openAIModel,
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": metaInstruction],
                ["role": "user", "content": raw],
            ],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PromptError.httpError(http.statusCode, String(body.prefix(300)))
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw PromptError.badResponse }
        return content
    }

    static func stamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }
}

public enum PromptError: LocalizedError, Sendable {
    case emptyRequest
    case missingAPIKey
    case badEndpoint(String)
    case httpError(Int, String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .emptyRequest: "需求为空"
        case .missingAPIKey: "未设置 OPENAI_API_KEY 环境变量，无法使用 LLM 重写"
        case .badEndpoint(let s): "接口地址无效：\(s)"
        case .httpError(let code, let body): "LLM 接口返回 \(code)：\(body)"
        case .badResponse: "LLM 返回内容无法解析"
        }
    }
}
