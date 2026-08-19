import Foundation

/// iCloud 文件的三种状态。
///
/// 「未下载」是 iCloud 特有的坑：文件在目录里列得出来，读的时候却是空的
/// 或者直接失败。必须显式识别并触发下载，不能当成「文件损坏」。
public enum CloudFileState: Sendable, Equatable {
    /// 不在 iCloud 里（本地文件），随便读
    case local
    /// 已下载且是最新版
    case current
    /// 已下载但不是最新（云端有更新）
    case downloaded
    /// 正在下载
    case downloading(progress: Double?)
    /// 尚未下载 —— 直接读会拿到空内容
    case notDownloaded

    public var isReadable: Bool {
        switch self {
        case .local, .current, .downloaded: true
        case .downloading, .notDownloaded: false
        }
    }

    public var label: String {
        switch self {
        case .local: "本地"
        case .current: "已同步"
        case .downloaded: "有云端更新"
        case .downloading(let p):
            p.map { "下载中 \(Int($0))%" } ?? "下载中"
        case .notDownloaded: "未下载"
        }
    }
}

/// 一次冲突处理的结果，用于向用户交代「发生了什么、东西去哪了」。
public struct ConflictReport: Sendable, Equatable, Identifiable {
    public let path: String
    public let winnerID: String
    public let reason: String
    /// 落败版本被保留到的位置 —— 永远不为空数组，否则说明丢数据了
    public let archived: [URL]
    public var id: String { path }

    public var message: String {
        "「\(path)」有 \(archived.count + 1) 个版本冲突，已采用 \(winnerID)（\(reason)）；"
        + "其余 \(archived.count) 份保留在 .conflicts/"
    }
}

/// iCloud 同步相关操作：下载状态、冲突检测与解决。
public actor CloudSyncService {

    /// 当前本机版本的标识，供裁决结果回判是否需要覆盖主文件
    public static let currentVersionID = "本机当前版本"

    public init() {}

    // MARK: 下载状态

    public nonisolated func state(of url: URL) -> CloudFileState {
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
            // 进度百分比只能通过 NSMetadataQuery 拿，URLResourceKey 在 macOS 上不可用，
            // 这里不给进度，UI 显示「下载中」即可
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isUbiquitousItem == true else { return .local }

        if values.ubiquitousItemIsDownloading == true {
            return .downloading(progress: nil)
        }
        switch values.ubiquitousItemDownloadingStatus {
        case .current?: return .current
        case .downloaded?: return .downloaded
        case .notDownloaded?: return .notDownloaded
        default: return .current
        }
    }

    /// 请求下载一个尚未下载的 iCloud 文件。
    public nonisolated func requestDownload(_ url: URL) throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    /// 扫描目录，找出所有尚未下载的文件并统一请求下载。返回请求了几个。
    @discardableResult
    public func downloadPending(in root: URL) -> Int {
        var count = 0
        for url in VaultStore.markdownFiles(under: root) where state(of: url) == .notDownloaded {
            if (try? requestDownload(url)) != nil { count += 1 }
        }
        return count
    }

    // MARK: 冲突

    /// 目录下所有存在未解决冲突的文件
    public func conflictedFiles(in root: URL) -> [URL] {
        VaultStore.markdownFiles(under: root).filter { url in
            !(NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).isEmpty
        }
    }

    /// 解决单个文件的冲突。
    ///
    /// 步骤：收集当前版本 + 所有冲突版本 → 交给 ConflictPolicy 裁决 →
    /// **先把落败版本原样存进 `.conflicts/`** → 胜者写回主文件 → 标记冲突已解决。
    ///
    /// 归档先于覆盖，是为了万一后续步骤失败也不会丢数据。
    @discardableResult
    public func resolveConflict(at url: URL, root: URL) throws -> ConflictReport? {
        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        guard !conflicts.isEmpty else { return nil }

        var candidates: [ConflictPolicy.Candidate] = []
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            candidates.append(.init(id: Self.currentVersionID, text: text, modified: modified))
        }
        for version in conflicts {
            guard let text = try? String(contentsOf: version.url, encoding: .utf8) else { continue }
            let name = version.localizedName
                ?? version.localizedNameOfSavingComputer
                ?? version.url.lastPathComponent
            candidates.append(.init(id: name, text: text,
                                    modified: version.modificationDate ?? .distantPast))
        }

        guard let decision = ConflictPolicy.decide(candidates), !decision.losers.isEmpty else {
            // 只有一个可读版本：直接把冲突标记为已解决，不动内容
            try markResolved(conflicts, at: url)
            return nil
        }

        let report = try applyDecision(decision, to: url, root: root)
        try markResolved(conflicts, at: url)
        return report
    }

    /// 把裁决结果落盘。
    ///
    /// 单独抽出来是为了**可测**：真实的 NSFileVersion 冲突只有 iCloud 能造出来，
    /// 本地造不了；但「裁决之后做了什么」才是真正会丢数据的地方，必须被测试盯住。
    ///
    /// 顺序是刻意的：**先归档落败版本，再覆盖主文件**。
    /// 万一覆盖那一步失败，落败内容也已经安全落盘了。
    func applyDecision(
        _ decision: ConflictPolicy.Decision, to url: URL, root: URL
    ) throws -> ConflictReport {
        let relative = VaultStore.relativePath(of: url, under: root)
        let archived = try archive(decision.losers, originalPath: relative, root: root)

        if decision.winner.id != Self.currentVersionID {
            try FileIO.writeAtomically(decision.winner.text, to: url, coordinated: false)
        }
        return ConflictReport(path: relative, winnerID: decision.winner.id,
                              reason: decision.reason, archived: archived)
    }

    /// 解决目录下的全部冲突
    public func resolveAll(in root: URL) -> [ConflictReport] {
        var reports: [ConflictReport] = []
        for url in conflictedFiles(in: root) {
            if let report = try? resolveConflict(at: url, root: root) {
                reports.append(report)
            }
        }
        return reports
    }

    // MARK: 私有

    /// 把落败版本写进 `<root>/.conflicts/<日期>/`，文件名带上来源标识。
    /// 这些文件是普通 Markdown，用任何编辑器都能打开对比。
    /// internal 而非 private：归档是「保证不丢数据」的关键一步，必须能被测试直接验证
    func archive(
        _ losers: [ConflictPolicy.Candidate], originalPath: String, root: URL
    ) throws -> [URL] {
        let dir = root.appendingPathComponent(".conflicts")
            .appendingPathComponent(DateOnly.today())
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let stem = (originalPath as NSString).deletingPathExtension
            .replacingOccurrences(of: "/", with: "__")
        var out: [URL] = []
        for loser in losers {
            let tag = VaultStore.safeFilename(loser.id, fallback: "版本")
            var target = dir.appendingPathComponent("\(stem)--\(tag).md")
            var n = 2
            while FileManager.default.fileExists(atPath: target.path) {
                target = dir.appendingPathComponent("\(stem)--\(tag)-\(n).md")
                n += 1
            }
            let header = """
                <!-- iCloud 冲突落败版本，由 Life Workflow OS 自动保留
                     来源：\(loser.id)
                     原文件：\(originalPath)
                     保留时间：\(DateOnly.today())
                     确认无需要的内容后可直接删除本文件 -->

                """
            try (header + loser.text).write(to: target, atomically: true, encoding: .utf8)
            out.append(target)
        }
        return out
    }

    private func markResolved(_ versions: [NSFileVersion], at url: URL) throws {
        for version in versions {
            version.isResolved = true
        }
        try NSFileVersion.removeOtherVersionsOfItem(at: url)
    }
}
