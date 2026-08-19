import Foundation

/// 用书签持久化「用户选中的文件夹」的访问权限。
///
/// 为什么需要它：iOS 应用只能读写自己的沙盒，想访问用户在文件 App 里
/// 选的目录（包括 iCloud Drive 中的目录），必须
/// 「文档选择器拿到 URL → 存书签 → 每次用之前 startAccessingSecurityScopedResource()」。
///
/// 这条路径**不需要 iCloud 权益**，因此免费 Apple ID 也能用——
/// 这正是当前账号条件下 iOS 端接入 vault 的可行方案。
public actor BookmarkStore {

    private let defaultsKey: String
    private var accessing: [String: URL] = [:]

    public init(defaultsKey: String = "com.lifeos.vaultBookmarks") {
        self.defaultsKey = defaultsKey
    }

    // MARK: 保存 / 读取

    /// 记住一个用户选中的目录。传入的 URL 必须来自文档选择器。
    public func save(_ url: URL, forKey key: String) throws {
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        // iOS 没有 withSecurityScope 选项；普通书签即可保留访问权
        let options: URL.BookmarkCreationOptions = []
        #endif

        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        let data = try url.bookmarkData(options: options,
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        var all = stored()
        all[key] = data
        UserDefaults.standard.set(all, forKey: defaultsKey)
    }

    /// 解析书签并**开始**访问；用完要调用 `release(key:)`。
    /// 书签失效（目录被删/移动）时返回 nil，不抛错——调用方应降级到本地目录。
    public func resolve(key: String) -> URL? {
        guard let data = stored()[key] else { return nil }
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif

        guard let url = try? URL(resolvingBookmarkData: data, options: options,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        // 陈旧书签：重新生成一份，否则下次可能解析失败
        if stale { try? save(url, forKey: key) }
        if url.startAccessingSecurityScopedResource() {
            accessing[key] = url
        }
        return url
    }

    public func release(key: String) {
        accessing.removeValue(forKey: key)?.stopAccessingSecurityScopedResource()
    }

    public func releaseAll() {
        for (_, url) in accessing { url.stopAccessingSecurityScopedResource() }
        accessing.removeAll()
    }

    public func remove(key: String) {
        release(key: key)
        var all = stored()
        all.removeValue(forKey: key)
        UserDefaults.standard.set(all, forKey: defaultsKey)
    }

    public func keys() -> [String] { Array(stored().keys).sorted() }

    private func stored() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
    }
}
