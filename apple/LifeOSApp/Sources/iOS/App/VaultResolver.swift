import Foundation
import LifeWorkflowKit

/// vault 定位：解析书签，拿不到就退回 App 内置目录。
///
/// 抽出来是因为 **App Intent 与界面都要用**：
/// 快捷指令触发时没有界面，不能依赖 VaultAccess 这个 @MainActor 的观察对象。
enum VaultResolver {
    static let bookmarkKey = "vault"

    /// App 沙盒内的默认 vault（通过 UIFileSharingEnabled 在「文件」App 里可见）
    static var localFallback: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("LifeOSVault", isDirectory: true)
    }

    /// 返回 (目录, 是否是用户选定的外部目录)
    static func resolve(using bookmarks: BookmarkStore = BookmarkStore()) async -> (url: URL, external: Bool) {
        if let url = await bookmarks.resolve(key: bookmarkKey) {
            return (url, true)
        }
        let local = localFallback
        try? FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        return (local, false)
    }

    /// 给 Intent 用的一次性 store
    static func makeStore() async -> VaultStore {
        let (url, _) = await resolve()
        let inICloud = url.path.contains("com~apple~CloudDocs") || url.path.contains("Mobile Documents")
        return VaultStore(roots: [
            VaultRoot(id: inICloud ? "icloud" : "local", url: url,
                      needsCoordination: inICloud,
                      displayName: url.lastPathComponent)
        ])
    }
}
