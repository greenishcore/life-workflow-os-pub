import Foundation

/// 全局配置。
///
/// 落点沿用 Python 版的 `~/.config/lifeos/config.json`，两套实现共享同一份配置，
/// 避免出现「命令行改的」和「应用里看到的」不是同一个 vault。
/// iOS 沙盒里没有这个路径，会自动退回 App 容器内的同名文件。
public struct AppConfig: Sendable, Codable, Hashable {

    /// 复合 vault 的根定义（可序列化的形态）
    public struct RootConfig: Sendable, Codable, Hashable {
        public var id: String
        public var path: String
        public var folders: [String]
        public var needsCoordination: Bool
        public var displayName: String

        public init(id: String, path: String, folders: [String] = [],
                    needsCoordination: Bool = false, displayName: String = "") {
            self.id = id
            self.path = path
            self.folders = folders
            self.needsCoordination = needsCoordination
            self.displayName = displayName.isEmpty ? id : displayName
        }

        public var root: VaultRoot {
            VaultRoot(id: id, url: URL(fileURLWithPath: (path as NSString).expandingTildeInPath),
                      folders: Set(folders), needsCoordination: needsCoordination,
                      displayName: displayName)
        }
    }

    public var roots: [RootConfig]
    public var logsPath: String
    public var promptsPath: String
    public var cachePath: String
    public var theme: String
    public var defaultCalendar: String
    public var defaultReminderList: String
    public var openAIBaseURL: String
    public var openAIModel: String

    public init(
        roots: [RootConfig] = [],
        logsPath: String = "",
        promptsPath: String = "",
        cachePath: String = "",
        theme: String = "system",
        defaultCalendar: String = "个人",
        defaultReminderList: String = "提醒事项",
        openAIBaseURL: String = "https://api.openai.com/v1",
        openAIModel: String = "gpt-4o-mini"
    ) {
        self.roots = roots
        self.logsPath = logsPath
        self.promptsPath = promptsPath
        self.cachePath = cachePath
        self.theme = theme
        self.defaultCalendar = defaultCalendar
        self.defaultReminderList = defaultReminderList
        self.openAIBaseURL = openAIBaseURL
        self.openAIModel = openAIModel
    }

    // MARK: 派生

    public var vaultRoots: [VaultRoot] { roots.map(\.root) }

    public var logsURL: URL { Self.expand(logsPath, fallback: "Logs") }
    public var promptsURL: URL { Self.expand(promptsPath, fallback: "Prompts") }
    public var cacheURL: URL { Self.expand(cachePath, fallback: "Cache") }
    public var runLogJSONL: URL { logsURL.appendingPathComponent("run-log.jsonl") }
    public var runLogMarkdown: URL { logsURL.appendingPathComponent("run-log.md") }

    private static func expand(_ path: String, fallback: String) -> URL {
        guard !path.isEmpty else { return supportDirectory.appendingPathComponent(fallback) }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// App 自己的容器目录（iOS 沙盒 / macOS 均可用）
    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LifeWorkflowOS", isDirectory: true)
    }

    /// 配置文件路径：优先与 Python 版共用，拿不到时退回 App 容器
    public static var fileURL: URL {
        let shared = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/lifeos/config.json")
        let dir = shared.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: dir.path)
            || (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil {
            return shared
        }
        return supportDirectory.appendingPathComponent("config.json")
    }

    // MARK: 读写

    public static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: fileURL),
              var cfg = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return makeDefault()
        }
        if cfg.roots.isEmpty { cfg.roots = makeDefault().roots }
        return cfg
    }

    @discardableResult
    public func save() throws -> URL {
        let url = Self.fileURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url, options: .atomic)
        return url
    }

    /// 默认布局：单个本地根（用户在设置里加 iCloud 根后变成复合 vault）
    public static func makeDefault() -> AppConfig {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? supportDirectory
        return AppConfig(roots: [
            RootConfig(id: "local", path: docs.appendingPathComponent("LifeOSVault").path,
                       displayName: "本地")
        ])
    }

    /// iCloud 容器里的 Documents 目录；未登录 iCloud 时返回 nil。
    /// watchOS 上恒为 nil —— 手表没有 iCloud Drive，这是平台限制不是错误。
    public static func iCloudDocuments(containerID: String? = nil) -> URL? {
        #if os(watchOS)
        return nil
        #else
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: containerID) else {
            return nil
        }
        return container.appendingPathComponent("Documents", isDirectory: true)
        #endif
    }

    public func ensureDirectories() throws {
        let fm = FileManager.default
        for url in [logsURL, promptsURL, cacheURL] {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        for root in vaultRoots {
            let folders = root.isFallback
                ? ["Resources", "Archive", "Attachments"]
                : Array(root.folders)
            for f in folders {
                try fm.createDirectory(at: root.url.appendingPathComponent(f),
                                       withIntermediateDirectories: true)
            }
        }
    }
}
