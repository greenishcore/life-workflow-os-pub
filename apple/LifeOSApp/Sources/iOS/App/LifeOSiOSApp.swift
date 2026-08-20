import SwiftUI
import LifeWorkflowKit

@main
struct LifeOSiOSApp: App {
    @State private var state = AppState()
    @State private var vault = VaultAccess()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .environment(vault)
                .task { await vault.bootstrap(into: state) }
        }
    }
}

/// iOS 的 vault 接入。
///
/// 免费 Apple ID 拿不到 iCloud 权益，所以不能直接用 iCloud 容器。
/// 可行路径是：用文档选择器让用户挑一个目录（**可以是 iCloud Drive 里的**），
/// 用书签持久化访问权限。不需要任何权益。
///
/// 用户没挑目录时，退回 App 自己的 Documents —— 它通过
/// UIFileSharingEnabled 在「文件」App 里可见，用户可以自己搬进 iCloud Drive。
@MainActor
@Observable
final class VaultAccess {
    private let bookmarks = BookmarkStore()
    private(set) var currentURL: URL?
    private(set) var isExternal = false
    private(set) var message = ""

    func bootstrap(into state: AppState) async {
        // 与 App Intent 走同一套解析逻辑（VaultResolver），保证快捷指令写到的
        // 和界面看到的是同一个 vault
        let (url, external) = await VaultResolver.resolve(using: bookmarks)
        currentURL = url
        isExternal = external
        message = external ? "已连接到你选定的目录" : "使用 App 内置目录（可在「文件」App 里看到）"
        await state.useVault(at: url, displayName: external ? url.lastPathComponent : "本机")
    }

    /// 文档选择器选中目录后调用
    func adopt(_ url: URL, into state: AppState) async {
        do {
            try await bookmarks.save(url, forKey: VaultResolver.bookmarkKey)
        } catch {
            message = "无法记住该目录：\(error.localizedDescription)"
            return
        }
        guard let resolved = await bookmarks.resolve(key: VaultResolver.bookmarkKey) else {
            message = "该目录暂时无法访问"
            return
        }
        currentURL = resolved
        isExternal = true
        message = "已连接到 \(resolved.lastPathComponent)"
        await state.useVault(at: resolved, displayName: resolved.lastPathComponent)
    }

    func reset(into state: AppState) async {
        await bookmarks.remove(key: VaultResolver.bookmarkKey)
        await bootstrap(into: state)
    }

    /// 路径是否落在 iCloud Drive 里（给用户一个明确反馈）
    var isInICloud: Bool {
        currentURL?.path.contains("com~apple~CloudDocs") ?? false
    }
}
