import Foundation

/// 可复用技能：把「已验证的操作序列」固化下来，下次同类任务直接调用而非重试试错。
///
/// 字段沿用仓库既有的 `skills/_template.md`（`skill_id` / `name` / `status`），
/// 保证已有的 skill 文件不用改就能被读进来。
public struct Skill: Sendable, Identifiable, Hashable {

    public enum Status: String, CaseIterable, Sendable {
        case draft, verified, archived

        public var label: String {
            switch self {
            case .draft: "草稿"
            case .verified: "已验证"
            case .archived: "已归档"
            }
        }

        public var colorHex: String {
            switch self {
            case .draft: "#f59e0b"
            case .verified: "#10b981"
            case .archived: "#9ca3af"
            }
        }

        public static func coerce(_ raw: String?) -> Status {
            guard let raw else { return .draft }
            return Status(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased()) ?? .draft
        }
    }

    public var skillID: String
    public var name: String
    public var status: Status
    public var created: String
    public var updated: String
    public var tags: [String]
    /// 什么时候该用它（一句话，方便在复盘里快速判断有没有覆盖某个坑）
    public var trigger: String
    /// 被用过几次 —— 长期没被用过的 skill 是该归档的信号
    public var uses: Int
    public var lastUsed: String
    /// 从哪些错误提炼而来，用于判断「这个坑是否还在复发」
    public var sourceErrors: [String]
    public var body: String
    public var url: URL?

    public var id: String { skillID }

    public init(
        skillID: String, name: String, status: Status = .draft,
        created: String = DateOnly.today(), updated: String = "",
        tags: [String] = [], trigger: String = "", uses: Int = 0,
        lastUsed: String = "", sourceErrors: [String] = [],
        body: String = "", url: URL? = nil
    ) {
        self.skillID = skillID
        self.name = name
        self.status = status
        self.created = created
        self.updated = updated
        self.tags = tags
        self.trigger = trigger
        self.uses = uses
        self.lastUsed = lastUsed
        self.sourceErrors = sourceErrors
        self.body = body
        self.url = url
    }

    // MARK: 读写

    public static func from(text: String, url: URL? = nil) -> Skill? {
        let (fm, body) = FrontmatterParser.parse(text)
        // 模板文件（_template.md）不算 skill
        guard let id = fm.string("skill_id"), !id.isEmpty,
              !id.hasPrefix("{{") else { return nil }
        return Skill(
            skillID: id,
            name: fm.string("name") ?? id,
            status: Status.coerce(fm.string("status")),
            created: DateOnly.normalize(fm.string("created")),
            updated: DateOnly.normalize(fm.string("updated")),
            tags: fm.list("tags"),
            trigger: fm.string("trigger") ?? "",
            uses: fm.int("uses") ?? 0,
            lastUsed: DateOnly.normalize(fm.string("last_used")),
            sourceErrors: fm.list("source_errors"),
            body: body,
            url: url)
    }

    public func toText() -> String {
        var fm = YAMLMapping()
        fm["skill_id"] = .string(skillID)
        fm["name"] = .string(name)
        fm["status"] = .string(status.rawValue)
        fm["created"] = .date(created.isEmpty ? DateOnly.today() : created)
        if !updated.isEmpty { fm["updated"] = .date(updated) }
        fm["tags"] = .array(tags.map { .string($0) })
        if !trigger.isEmpty { fm["trigger"] = .string(trigger) }
        if uses > 0 { fm["uses"] = .int(uses) }
        if !lastUsed.isEmpty { fm["last_used"] = .date(lastUsed) }
        if !sourceErrors.isEmpty {
            fm["source_errors"] = .array(sourceErrors.map { .string($0) })
        }
        return FrontmatterEmitter.render(fm, body: body.isEmpty ? "# \(name)\n" : body,
                                         order: FrontmatterEmitter.skillFieldOrder)
    }

    public mutating func touch() { updated = DateOnly.today() }

    /// 记一次使用 —— 「效果评分」那一环的最小可行版本
    public mutating func recordUse(on date: String = DateOnly.today()) {
        uses += 1
        lastUsed = date
        touch()
    }

    /// 是否覆盖了某条错误（用于判断坑是否已有对策）
    public func covers(error: String) -> Bool {
        let needle = error.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return false }
        if sourceErrors.contains(where: { $0.lowercased() == needle }) { return true }
        let haystack = "\(name) \(trigger) \(body)".lowercased()
        return haystack.contains(needle)
    }

    /// 长期没用过的已验证 skill，是该归档还是该被想起来？
    public func isStale(today: String = DateOnly.today(), days: Int = 90) -> Bool {
        guard status == .verified else { return false }
        let reference = lastUsed.isEmpty ? created : lastUsed
        guard let gap = DateOnly.daysBetween(reference, today) else { return false }
        return gap >= days
    }
}
