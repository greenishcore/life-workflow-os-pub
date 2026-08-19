import Foundation

/// vault 的读写入口 —— 所有对笔记文件的访问都必须经由这里。
///
/// 用 `actor` 而不是加锁的 class：索引是可变状态，Swift 6 严格并发下
/// actor 是唯一能在编译期证明「不会数据竞争」的方式。
public actor VaultStore {

    /// 扫描时跳过的目录（与 Python 版一致）
    public static let skipDirs: Set<String> = [
        ".obsidian", ".trash", ".git", "Templates", "Attachments",
        "Dashboard", "node_modules", "__pycache__", ".cache", ".conflicts",
    ]

    /// 新建记录按类型决定默认落点
    public static let folderForType: [ItemType: String] = [
        .idea: "Inbox", .task: "Projects", .daily: "Daily", .note: "Resources",
    ]

    public let roots: [VaultRoot]
    private var items: [Item] = []
    private var loaded = false
    private(set) public var warnings: [VaultWarning] = []

    public init(roots: [VaultRoot]) {
        precondition(!roots.isEmpty, "至少要有一个 vault 根")
        // 兜底根排最后，保证具名根优先匹配
        self.roots = roots.sorted { !$0.isFallback && $1.isFallback }
    }

    /// 单根便利构造（等价于旧版行为）
    public init(url: URL) {
        self.init(roots: [.local(url)])
    }

    // MARK: 根解析

    /// 某个顶层目录该落到哪个根
    public nonisolated func root(forFolder folder: String) -> VaultRoot {
        roots.first { $0.folders.contains(folder) } ?? roots.last!
    }

    public nonisolated func root(withID id: String) -> VaultRoot? {
        roots.first { $0.id == id }
    }

    /// 相对路径 → 绝对 URL
    public nonisolated func url(forRelativePath path: String) -> URL {
        let folder = path.split(separator: "/").first.map(String.init) ?? ""
        return root(forFolder: folder).url.appendingPathComponent(path)
    }

    // MARK: 读

    @discardableResult
    public func load(force: Bool = false) -> [Item] {
        if loaded && !force { return items }
        var collected: [String: Item] = [:]     // 相对路径 → Item
        var owner: [String: VaultRoot] = [:]
        var newWarnings: [VaultWarning] = []

        for root in roots {
            for url in Self.markdownFiles(under: root.url) {
                let rel = Self.relativePath(of: url, under: root.url)
                let text: String
                do {
                    text = try FileIO.read(url, coordinated: root.needsCoordination)
                } catch {
                    newWarnings.append(.init(kind: .unreadable(path: rel, reason: error.localizedDescription)))
                    continue
                }
                guard let item = Item.from(text: text, url: url, rootID: root.id) else { continue }

                if let previous = owner[rel] {
                    // 同一路径出现在两个根：具名根（如 iCloud）优先，且必须告警而非静默
                    newWarnings.append(.init(kind: .duplicateAcrossRoots(
                        path: rel, winner: previous.displayName, loser: root.displayName)))
                    continue
                }
                owner[rel] = root
                collected[rel] = item
            }
        }

        items = collected.values.sorted { ($0.created, $0.title) < ($1.created, $1.title) }
        warnings = newWarnings
        loaded = true
        return items
    }

    public func reload() -> [Item] { load(force: true) }

    public var allItems: [Item] {
        loaded ? items : load()
    }

    public func item(id: String) -> Item? {
        allItems.first { $0.id == id }
    }

    public func query(
        text: String = "",
        statuses: Set<Status>? = nil,
        types: Set<ItemType>? = nil,
        tags: Set<String>? = nil
    ) -> [Item] {
        allItems.filter { item in
            if let statuses, !statuses.contains(item.status) { return false }
            if let types, !types.contains(item.type) { return false }
            if let tags, tags.isDisjoint(with: Set(item.tags)) { return false }
            return item.matches(text)
        }
    }

    public func allTags() -> [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in allItems { for t in item.tags { counts[t, default: 0] += 1 } }
        return counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
            .map { (tag: $0.key, count: $0.value) }
    }

    // MARK: 写

    /// 决定一条新记录的落点（已有 url 则沿用）
    public func destination(for item: Item) -> URL {
        if let url = item.url { return url }
        let folder = Self.folderForType[item.type] ?? "Inbox"
        let root = root(forFolder: folder)
        let dir = root.url.appendingPathComponent(folder)
        let base = Self.safeFilename(item.title.isEmpty ? item.id : item.title)
        var candidate = dir.appendingPathComponent("\(base).md")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base)-\(n).md")
            n += 1
        }
        return candidate
    }

    @discardableResult
    public func save(_ item: inout Item, touch: Bool = true) throws -> URL {
        if touch { item.touch() }
        if item.id.isEmpty { item.id = Item.newID() }
        let url = destination(for: item)
        let rootID = item.rootID ?? rootID(containing: url)
        let coordinated = root(withID: rootID ?? "")?.needsCoordination ?? false
        try FileIO.writeAtomically(item.toText(), to: url, coordinated: coordinated)
        item.url = url
        item.rootID = rootID
        upsertIndex(item)
        return url
    }

    @discardableResult
    public func create(
        title: String,
        type: ItemType = .idea,
        status: Status = .seed,
        body: String = ""
    ) throws -> Item {
        var item = Item(title: title, type: type, id: Item.newID(),
                        created: DateOnly.today(), status: status,
                        body: body.isEmpty ? "# \(title)\n\n" : body)
        try save(&item)
        return item
    }

    /// 删除：默认移入 `.trash/日期/`（可恢复），而不是真删。
    @discardableResult
    public func delete(_ item: Item, toTrash: Bool = true) throws -> URL? {
        items.removeAll { $0.id == item.id && $0.url == item.url }
        guard let url = item.url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard toTrash else {
            try FileManager.default.removeItem(at: url)
            return nil
        }
        let root = root(withID: item.rootID ?? "") ?? roots.last!
        let dir = root.url.appendingPathComponent(".trash").appendingPathComponent(DateOnly.today())
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var target = dir.appendingPathComponent(url.lastPathComponent)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = dir.appendingPathComponent(
                "\(url.deletingPathExtension().lastPathComponent)-\(n).\(url.pathExtension)")
            n += 1
        }
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    /// 归档：状态置 archived 并移入 Archive/
    @discardableResult
    public func archive(_ item: inout Item) throws -> URL {
        item.status = .archived
        item.touch()
        let root = root(forFolder: "Archive")
        let dir = root.url.appendingPathComponent("Archive")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = item.url?.lastPathComponent ?? "\(Self.safeFilename(item.title)).md"
        var target = dir.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path), target != item.url {
            target = dir.appendingPathComponent(
                "\(target.deletingPathExtension().lastPathComponent)-\(n).md")
            n += 1
        }
        try FileIO.writeAtomically(item.toText(), to: target, coordinated: root.needsCoordination)
        if let old = item.url, old != target, FileManager.default.fileExists(atPath: old.path) {
            try FileManager.default.removeItem(at: old)
        }
        item.url = target
        item.rootID = root.id
        upsertIndex(item)
        return target
    }

    // MARK: 捕捉

    /// 快速捕获：追加一条待办到 Inbox/当日.md
    @discardableResult
    public func capture(_ text: String, at date: Date = Date()) throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VaultError.emptyCapture }

        let root = root(forFolder: "Inbox")
        let day = DateOnly.string(from: date)
        let url = root.url.appendingPathComponent("Inbox").appendingPathComponent("\(day).md")

        let time = Self.timeFormatter.string(from: date)
        let existing = (try? FileIO.read(url, coordinated: root.needsCoordination)) ?? ""
        let header = existing.isEmpty ? "# 收件箱 \(day)\n\n" : ""
        try FileIO.writeAtomically(existing + header + "- [ ] \(time) \(trimmed)\n",
                                   to: url, coordinated: root.needsCoordination)
        return url
    }

    /// 读取最近 N 天的 Inbox 捕获记录
    public func captureLog(days: Int = 14) -> [(date: String, lines: [String])] {
        let root = root(forFolder: "Inbox")
        let dir = root.url.appendingPathComponent("Inbox")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }

        let dated = contents
            .filter { $0.pathExtension == "md" }
            .filter { ScalarParser.isDateShaped($0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(days)

        return dated.compactMap { url in
            guard let text = try? FileIO.read(url, coordinated: root.needsCoordination) else { return nil }
            let lines = text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("- ") }
            guard !lines.isEmpty else { return nil }
            return (date: url.deletingPathExtension().lastPathComponent, lines: lines)
        }
    }

    /// 勾选 / 取消勾选某一条捕获
    @discardableResult
    public func toggleCaptureLine(date: String, rawLine: String) throws -> Bool {
        let root = root(forFolder: "Inbox")
        let url = root.url.appendingPathComponent("Inbox").appendingPathComponent("\(date).md")
        guard let text = try? FileIO.read(url, coordinated: root.needsCoordination) else { return false }

        var lines = text.components(separatedBy: "\n")
        let target = rawLine.trimmingCharacters(in: .whitespaces)
        for (i, line) in lines.enumerated() where line.trimmingCharacters(in: .whitespaces) == target {
            if line.contains("- [ ]") {
                lines[i] = line.replacingOccurrences(of: "- [ ]", with: "- [x]", options: [], range: line.range(of: "- [ ]"))
            } else if line.contains("- [x]") {
                lines[i] = line.replacingOccurrences(of: "- [x]", with: "- [ ]", options: [], range: line.range(of: "- [x]"))
            } else {
                return false
            }
            try FileIO.writeAtomically(lines.joined(separator: "\n"), to: url,
                                       coordinated: root.needsCoordination)
            return true
        }
        return false
    }

    // MARK: Daily 段落

    public nonisolated func dailyNote(date: String? = nil) -> URL {
        let day = date ?? DateOnly.today()
        return root(forFolder: "Daily").url
            .appendingPathComponent("Daily").appendingPathComponent("\(day).md")
    }

    /// 把内容写入某个 `## 标题` 段（有则替换，无则追加）。
    /// 提醒/日程重复导入时必须是**替换**而不是不断追加。
    @discardableResult
    public func upsertSection(at url: URL, heading: String, content: String) throws -> URL {
        let coordinated = root(withID: rootID(containing: url) ?? "")?.needsCoordination ?? false
        let existing = (try? FileIO.read(url, coordinated: coordinated)) ?? ""
        let block = "## \(heading)\n\n\(content.trimmingCharacters(in: .whitespacesAndNewlines))\n"

        let lines = existing.components(separatedBy: "\n")
        var out: [String] = []
        var i = 0
        var replaced = false
        while i < lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "## \(heading)" {
                out.append(contentsOf: block.components(separatedBy: "\n"))
                out.append("")
                i += 1
                // 吃掉旧段落直到下一个二级标题
                while i < lines.count, !lines[i].hasPrefix("## ") { i += 1 }
                replaced = true
                continue
            }
            out.append(lines[i])
            i += 1
        }
        if !replaced {
            if !out.isEmpty, out.last?.isEmpty == false { out.append("") }
            out.append(contentsOf: block.components(separatedBy: "\n"))
        }
        var text = out.joined(separator: "\n")
        while text.hasSuffix("\n\n\n") { text.removeLast() }
        if !text.hasSuffix("\n") { text += "\n" }
        try FileIO.writeAtomically(text, to: url, coordinated: coordinated)
        return url
    }

    // MARK: 私有

    private func upsertIndex(_ item: Item) {
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            items[i] = item
        } else {
            items.append(item)
        }
        items.sort { ($0.created, $0.title) < ($1.created, $1.title) }
    }

    private nonisolated func rootID(containing url: URL) -> String? {
        roots.first { url.path.hasPrefix($0.url.path) }?.id
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// 文件名清洗（规则与 Python 版一致）
    public static func safeFilename(_ raw: String, fallback: String = "未命名") -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        var name = raw.components(separatedBy: unsafe).joined(separator: "-")
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        while name.contains("--") { name = name.replacingOccurrences(of: "--", with: "-") }
        if name.isEmpty { name = fallback }
        return String(name.prefix(80))
    }

    static func markdownFiles(under root: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return [] }

        var out: [URL] = []
        for case let url as URL in e {
            let name = url.lastPathComponent
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                if skipDirs.contains(name) || name.hasPrefix(".") { e.skipDescendants() }
                continue
            }
            if url.pathExtension == "md" { out.append(url) }
        }
        return out.sorted { $0.path < $1.path }
    }

    static func relativePath(of url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let p = url.standardizedFileURL.path
        guard p.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(p.dropFirst(rootPath.count).drop { $0 == "/" })
    }
}
