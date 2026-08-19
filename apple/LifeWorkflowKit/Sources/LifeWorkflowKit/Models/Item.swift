import Foundation

/// vault 中的一条记录（想法/任务/日记/笔记）。
///
/// 「想法」是一等公民，带五个维度：时间 + 状态 + 优先级 + 标签 + 思路注释（思维轨迹）。
public struct Item: Sendable, Identifiable, Hashable {
    public var title: String
    public var type: ItemType
    public var id: String
    public var created: String
    /// 只在内容真正修改时才有值——只读浏览不得产生 diff
    public var updated: String
    public var status: Status
    public var priority: Priority
    public var energy: Int?
    public var progress: Int?
    public var tags: [String]
    public var thinkingNotes: [ThinkingNote]
    public var nextActions: [String]
    public var links: [String]
    public var body: String

    /// 文件位置（新建未落盘时为 nil）
    public var url: URL?
    /// 所属的 vault 根（复合 vault：iCloud 根 / 本地根）
    public var rootID: String?
    /// 用户手写的未知 frontmatter 字段，原样保留并写回
    public var extra: YAMLMapping

    public init(
        title: String = "",
        type: ItemType = .idea,
        id: String = "",
        created: String = DateOnly.today(),
        updated: String = "",
        status: Status = .seed,
        priority: Priority = .medium,
        energy: Int? = nil,
        progress: Int? = nil,
        tags: [String] = [],
        thinkingNotes: [ThinkingNote] = [],
        nextActions: [String] = [],
        links: [String] = [],
        body: String = "",
        url: URL? = nil,
        rootID: String? = nil,
        extra: YAMLMapping = YAMLMapping()
    ) {
        self.title = title
        self.type = type
        self.id = id
        self.created = created
        self.updated = updated
        self.status = status
        self.priority = priority
        self.energy = energy
        self.progress = progress
        self.tags = tags
        self.thinkingNotes = thinkingNotes
        self.nextActions = nextActions
        self.links = links
        self.body = body
        self.url = url
        self.rootID = rootID
        self.extra = extra
    }

    // MARK: 读

    /// 从 Markdown 文本构造。
    ///
    /// 收录条件与 Python 版一致：`type` 为 idea/task，或带 `status` 的任意记录。
    /// 不满足则返回 nil（普通笔记不进看板）。
    public static func from(text: String, url: URL? = nil, rootID: String? = nil) -> Item? {
        let (fm, body) = FrontmatterParser.parse(text)
        guard !fm.isEmpty else { return nil }

        let typeRaw = fm.string("type")?.lowercased()
        guard typeRaw == "idea" || typeRaw == "task" || fm.contains("status") else { return nil }

        var created = DateOnly.normalize(fm.string("created") ?? fm.string("date"))
        if created.isEmpty, let url {
            created = firstDate(in: url.deletingPathExtension().lastPathComponent)
        }
        if created.isEmpty { created = DateOnly.today() }

        let notes = (fm["thinking_notes"]?.arrayValue ?? []).map { raw -> ThinkingNote in
            if let m = raw.mappingValue {
                let t = DateOnly.normalize(m.string("t") ?? m.string("date"))
                return ThinkingNote(t: t.isEmpty ? created : t, note: (m.string("note") ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return ThinkingNote(t: created, note: (raw.stringValue ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let known = Set(FrontmatterEmitter.fieldOrder)
        return Item(
            title: fm.string("title") ?? fm.string("id")
                ?? url?.deletingPathExtension().lastPathComponent ?? "",
            type: ItemType.coerce(typeRaw),
            id: fm.string("id") ?? "",
            created: created,
            updated: DateOnly.normalize(fm.string("updated")),
            status: Status.coerce(fm.string("status")),
            priority: Priority.coerce(fm.string("priority")),
            energy: clamp(fm["energy"], 0, 10),
            progress: clamp(fm["progress"], 0, 100),
            tags: fm.list("tags"),
            thinkingNotes: notes,
            nextActions: fm.list("next_actions"),
            links: fm.list("links"),
            body: body,
            url: url,
            rootID: rootID,
            extra: fm.excluding(known)
        )
    }

    // MARK: 写

    public func toFrontmatter() -> YAMLMapping {
        var fm = YAMLMapping()
        fm["type"] = .string(type.rawValue)
        fm["id"] = .string(id.isEmpty ? Item.newID() : id)
        fm["title"] = .string(title)
        fm["created"] = .date(created.isEmpty ? DateOnly.today() : created)
        // updated 只在有值时写出：由 touch()/仓库层在内容变更时设置，
        // 避免「只读打开也产生 diff」。
        if !updated.isEmpty { fm["updated"] = .date(updated) }
        fm["status"] = .string(status.rawValue)
        fm["priority"] = .string(priority.rawValue)
        if let energy { fm["energy"] = .int(energy) }
        if let progress { fm["progress"] = .int(progress) }
        fm["tags"] = .array(tags.map { .string($0) })
        fm["thinking_notes"] = .array(thinkingNotes.map { n in
            var m = YAMLMapping()
            m["t"] = .date(n.t)
            m["note"] = .string(n.note)
            return .mapping(m)
        })
        fm["next_actions"] = .array(nextActions.map { .string($0) })
        fm["links"] = .array(links.map { .string($0) })
        for (k, v) in extra.pairs { fm[k] = v }
        return fm
    }

    public func toText() -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return FrontmatterEmitter.render(
            toFrontmatter(),
            body: trimmed.isEmpty ? "# \(title)\n" : body
        )
    }

    // MARK: 辅助

    public static func newID(_ date: Date = Date()) -> String {
        let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(4)).lowercased()
        return "\(DateOnly.string(from: date))-\(suffix)"
    }

    public mutating func touch(_ date: Date = Date()) {
        updated = DateOnly.string(from: date)
    }

    @discardableResult
    public mutating func addThinkingNote(_ note: String, when: String? = nil) -> ThinkingNote {
        let tn = ThinkingNote(t: when ?? DateOnly.today(),
                              note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        thinkingNotes.append(tn)
        touch()
        return tn
    }

    /// 最近一次「有动静」的日期：思路注释 > updated > created
    public var lastActivity: String {
        var dates = [created, updated]
        dates.append(contentsOf: thinkingNotes.map(\.t))
        return dates.filter { !$0.isEmpty }.max() ?? created
    }

    /// 全文匹配：标题、id、标签、正文、思路注释、下一步
    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        var haystack = [title, id, tags.joined(separator: " "), body]
        haystack.append(contentsOf: thinkingNotes.map(\.note))
        haystack.append(contentsOf: nextActions)
        return haystack.joined(separator: " ").lowercased().contains(q)
    }

    // MARK: 私有

    private static func clamp(_ value: YAMLValue?, _ lo: Int, _ hi: Int) -> Int? {
        guard let value, case .null = value else {
            guard let i = value?.intValue else { return nil }
            return max(lo, min(hi, i))
        }
        return nil
    }

    private static func firstDate(in name: String) -> String {
        let chars = Array(name)
        guard chars.count >= 10 else { return "" }
        for start in 0...(chars.count - 10) {
            let candidate = String(chars[start..<(start + 10)])
            if ScalarParser.isDateShaped(candidate) { return candidate }
        }
        return ""
    }
}
