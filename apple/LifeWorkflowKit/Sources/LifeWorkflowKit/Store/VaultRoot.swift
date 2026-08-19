import Foundation

/// vault 的一个根。
///
/// 复合 vault 的由来：用户要求「只把想法/日记同步到 iCloud，隐私与大体积内容留本地」，
/// 而 iCloud Drive **没有**按目录排除的机制，所以只能分根存放、在应用层合并成单一视图。
public struct VaultRoot: Sendable, Identifiable, Hashable {
    public let id: String
    public let url: URL
    /// 归属本根的顶层目录名；为空表示这是**兜底根**（其余目录都落这里）
    public let folders: Set<String>
    /// iCloud 根必须走 NSFileCoordinator，本地根不需要
    public let needsCoordination: Bool
    public let displayName: String

    public init(
        id: String,
        url: URL,
        folders: Set<String> = [],
        needsCoordination: Bool = false,
        displayName: String = ""
    ) {
        self.id = id
        self.url = url
        self.folders = folders
        self.needsCoordination = needsCoordination
        self.displayName = displayName.isEmpty ? id : displayName
    }

    public var isFallback: Bool { folders.isEmpty }

    /// 默认布局：想法/日记/项目上 iCloud，其余留本地
    public static let syncedFolders: Set<String> = ["Inbox", "Daily", "Projects"]

    public static func local(_ url: URL) -> VaultRoot {
        VaultRoot(id: "local", url: url, folders: [], needsCoordination: false, displayName: "本地")
    }

    public static func iCloud(_ url: URL, folders: Set<String> = syncedFolders) -> VaultRoot {
        VaultRoot(id: "icloud", url: url, folders: folders,
                  needsCoordination: true, displayName: "iCloud")
    }
}

/// 扫描过程中发现的问题（不中断加载，但要让用户看见）
public struct VaultWarning: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// 同一相对路径在多个根里都存在
        case duplicateAcrossRoots(path: String, winner: String, loser: String)
        case unreadable(path: String, reason: String)
    }
    public let kind: Kind
    public var message: String {
        switch kind {
        case .duplicateAcrossRoots(let path, let winner, let loser):
            "「\(path)」在 \(winner) 与 \(loser) 两个根里都存在，已采用 \(winner) 的版本"
        case .unreadable(let path, let reason):
            "无法读取「\(path)」：\(reason)"
        }
    }
}
