import Foundation

/// 技能库：读写 `skills/*.md`，并从运行日志里**提炼**出该沉淀什么。
///
/// 「提炼」这一步原先只是周复盘报告里的一个复选框，从没真的产生过 skill。
/// 这里把它变成可计算、可测试的规则：什么样的证据该产生什么样的提议。
public enum SkillsService {

    // MARK: 提议

    public struct Proposal: Sendable, Identifiable, Hashable {
        public enum Kind: Sendable, Hashable {
            /// 高频错误且无对策 → 该沉淀一个避坑 skill
            case avoidPitfall
            /// 固定的工具组合反复出现 → 该固化成流程 skill
            case solidifyFlow
            /// 已有 skill 覆盖该错误，但坑仍在复发 → skill 没生效，要改
            case ineffective(existing: String)
            /// 已验证的 skill 长期没被用过 → 该归档或该被想起来
            case stale(existing: String)

            public var label: String {
                switch self {
                case .avoidPitfall: "沉淀避坑"
                case .solidifyFlow: "固化流程"
                case .ineffective: "对策未生效"
                case .stale: "长期闲置"
                }
            }

            /// 前两类可以直接「采纳」生成 skill；后两类是提醒，没有草稿
            public var isActionable: Bool {
                switch self {
                case .avoidPitfall, .solidifyFlow: true
                case .ineffective, .stale: false
                }
            }
        }

        public let kind: Kind
        public let title: String
        /// 为什么提这个 —— 直接展示给用户，不做黑箱
        public let rationale: String
        public let evidence: [String]
        /// 可直接落盘的草稿（提醒类为 nil）
        public let draft: Skill?

        public var id: String { "\(kind.label)-\(title)" }
    }

    /// 从日志与既有 skills 提炼提议。
    ///
    /// 纯函数：不碰文件系统，因此规则可以被完整测试。
    /// - Parameters:
    ///   - logs: 复盘区间内的运行日志
    ///   - existing: 现有 skills
    ///   - errorThreshold: 错误重复几次才值得沉淀（默认 2 —— 出现一次可能是偶然）
    ///   - flowThreshold: 同一工具组合重复几次才值得固化（默认 3）
    public static func propose(
        logs: [RunLog],
        existing: [Skill],
        errorThreshold: Int = 2,
        flowThreshold: Int = 3,
        today: String = DateOnly.today()
    ) -> [Proposal] {
        var proposals: [Proposal] = []

        // ---- 1. 高频错误 ----
        var errorCounts: [String: Int] = [:]
        for log in logs { for e in log.errors { errorCounts[e, default: 0] += 1 } }

        for (message, count) in errorCounts.sorted(by: { ($1.value, $0.key) < ($0.value, $1.key) })
        where count >= errorThreshold {
            if let covering = existing.first(where: { $0.covers(error: message) }) {
                // 已经有对策了，坑还在复发 —— 这是比"再建一个 skill"更有价值的信号
                proposals.append(Proposal(
                    kind: .ineffective(existing: covering.skillID),
                    title: covering.name,
                    rationale: "已有 skill「\(covering.name)」应对这个坑，但它仍出现了 \(count) 次，说明对策没生效或没被想起来用",
                    evidence: ["错误：\(message)（\(count) 次）"],
                    draft: nil))
            } else {
                proposals.append(Proposal(
                    kind: .avoidPitfall,
                    title: shortTitle(from: message),
                    rationale: "这个错误重复出现 \(count) 次且没有对应 skill，说明是稳定复发的坑，值得把解法固定下来",
                    evidence: ["错误：\(message)（\(count) 次）"],
                    draft: pitfallDraft(error: message, count: count, today: today)))
            }
        }

        // ---- 2. 固定工具组合 ----
        var flowCounts: [String: Int] = [:]
        for log in logs where log.status == .success && log.toolsUsed.count >= 2 {
            let key = log.toolsUsed.sorted().joined(separator: " + ")
            flowCounts[key, default: 0] += 1
        }
        for (combo, count) in flowCounts.sorted(by: { ($1.value, $0.key) < ($0.value, $1.key) })
        where count >= flowThreshold {
            let already = existing.contains { skill in
                combo.split(separator: "+").allSatisfy {
                    skill.covers(error: $0.trimmingCharacters(in: .whitespaces))
                }
            }
            guard !already else { continue }
            proposals.append(Proposal(
                kind: .solidifyFlow,
                title: "\(combo) 流程",
                rationale: "这组工具连续成功配合了 \(count) 次，步骤已经稳定，值得固化成可复用流程",
                evidence: ["工具组合：\(combo)（成功 \(count) 次）"],
                draft: flowDraft(combo: combo, count: count, logs: logs, today: today)))
        }

        // ---- 3. 长期闲置的已验证 skill ----
        for skill in existing where skill.isStale(today: today) {
            let reference = skill.lastUsed.isEmpty ? skill.created : skill.lastUsed
            proposals.append(Proposal(
                kind: .stale(existing: skill.skillID),
                title: skill.name,
                rationale: "自 \(reference) 起没有被用过，要么该归档，要么是你忘了它的存在",
                evidence: ["最近使用：\(skill.lastUsed.isEmpty ? "从未" : skill.lastUsed)"],
                draft: nil))
        }

        return proposals
    }

    // MARK: 草稿生成

    static func pitfallDraft(error: String, count: Int, today: String) -> Skill {
        Skill(
            skillID: slug(from: error),
            name: shortTitle(from: error),
            status: .draft,
            created: today,
            tags: ["pitfall"],
            trigger: "遇到「\(error)」时",
            sourceErrors: [error],
            body: """
            # \(shortTitle(from: error))

            ## 触发条件（何时用）
            - 遇到错误：`\(error)`（复盘区间内出现 \(count) 次）

            ## 目标
            - 一句话：不再被这个坑绊住

            ## 步骤
            1. <!-- 复现条件是什么？ -->
            2. <!-- 稳定解法是什么？ -->
            3. <!-- 怎么提前避免？ -->

            ## 验收标准
            - [ ] 下个复盘区间内该错误不再出现

            ## 注意 / 踩过的坑
            - 由周复盘自动提议（\(today)），解法待你补全

            ## 效果评分（每次使用后更新）
            - 日期 | 效果(1-5) | 备注
            """)
    }

    static func flowDraft(combo: String, count: Int, logs: [RunLog], today: String) -> Skill {
        let tools = combo.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        let samples = logs
            .filter { $0.status == .success && Set($0.toolsUsed) == Set(tools) }
            .prefix(3)
            .map { "- \($0.objective)" }
            .joined(separator: "\n")
        return Skill(
            skillID: slug(from: combo),
            name: "\(combo) 流程",
            status: .draft,
            created: today,
            tags: ["flow"] + tools,
            trigger: "需要用到 \(combo) 这组工具时",
            body: """
            # \(combo) 流程

            ## 触发条件（何时用）
            - 需要 \(combo) 配合完成的任务

            ## 依赖
            - 工具：\(tools.joined(separator: " / "))

            ## 目标
            - 一句话：把这组已经稳定的步骤固定下来，不用每次重新试

            ## 已成功的场景（来自运行日志）
            \(samples.isEmpty ? "- （无）" : samples)

            ## 步骤
            1. <!-- 把实际执行顺序写下来 -->

            ## 验收标准
            - [ ] 照步骤走一遍即可完成，无需临场调整

            ## 效果评分（每次使用后更新）
            - 日期 | 效果(1-5) | 备注
            """)
    }

    // MARK: 读写

    public static func load(from directory: URL) -> [Skill] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == "md" && !$0.lastPathComponent.hasPrefix("_") }
            .compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return Skill.from(text: text, url: url)
            }
            .sorted { $0.name < $1.name }
    }

    @discardableResult
    public static func save(_ skill: Skill, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = skill.url ?? directory.appendingPathComponent("\(skill.skillID).md")
        try FileIO.writeAtomically(skill.toText(), to: url, coordinated: false)
        return url
    }

    // MARK: 文本工具

    /// 从错误信息里取一个短标题（去掉路径、截断）
    static func shortTitle(from text: String) -> String {
        let cleaned = text
            .components(separatedBy: CharacterSet(charactersIn: "\n\r"))
            .first?.trimmingCharacters(in: .whitespaces) ?? text
        return String(cleaned.prefix(40))
    }

    /// 生成文件名安全的 id
    static func slug(from text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        var out = ""
        for ch in Self.shortTitle(from: text).lowercased() {
            if String(ch).rangeOfCharacter(from: allowed) != nil {
                out.append(ch)
            } else if !out.hasSuffix("-") {
                out.append("-")
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "skill-\(abs(text.hashValue) % 10000)" : String(trimmed.prefix(50))
    }
}
