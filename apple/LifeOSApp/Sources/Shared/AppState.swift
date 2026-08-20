import Foundation
import Observation
import SwiftUI
import LifeWorkflowKit

/// 全应用共享状态。
///
/// 标记 @MainActor：所有 UI 读到的属性都在主线程更新，
/// 与 VaultStore(actor) 之间靠 await 跨越隔离边界。
@MainActor
@Observable
final class AppState {
    // 配置与存储
    private(set) var config: AppConfig
    private(set) var store: VaultStore
    private(set) var runLog: RunLogService

    // 数据
    private(set) var items: [Item] = []
    private(set) var summary = Stats.Summary()
    private(set) var warnings: [VaultWarning] = []
    private(set) var isLoading = false
    /// 最近一次冲突处理的结果，用来向用户交代「东西去哪了」
    private(set) var conflictReports: [ConflictReport] = []
    private(set) var isResolvingConflicts = false

    /// 需要用户介入的告警（冲突、跨根重名）
    var attentionWarnings: [VaultWarning] { warnings.filter(\.needsAttention) }

    var conflictCount: Int {
        warnings.filter { if case .conflict = $0.kind { return true } else { return false } }.count
    }

    var pendingDownloadCount: Int {
        warnings.filter { if case .notDownloaded = $0.kind { return true } else { return false } }.count
    }

    // 导航
    var selection: Destination = .dashboard
    /// 想法库要打开的目标（看板点击跳转用）
    var pendingItemID: String?
    var pendingNewItem = false

    // 状态栏提示
    private(set) var statusMessage = ""
    private var statusClearTask: Task<Void, Never>?

    /// 传入 config 可覆盖磁盘上的配置（快照模式与测试用）
    init(config injected: AppConfig? = nil) {
        let cfg = injected ?? AppConfig.load()
        self.config = cfg
        self.store = VaultStore(roots: cfg.vaultRoots)
        self.runLog = RunLogService(config: cfg)
    }

    // MARK: 生命周期

    func bootstrap() async {
        try? config.ensureDirectories()
        await reload()
    }

    func reload() async {
        isLoading = true
        let loaded = await store.reload()
        let warns = await store.warnings
        items = loaded
        summary = Stats.summarize(loaded)
        warnings = warns
        isLoading = false
    }

    /// 把 vault 指向某个目录（iOS 解析书签后调用）。
    /// 不写配置文件——书签才是 iOS 上的事实来源，路径每次解析可能不同。
    func useVault(at url: URL, displayName: String, persist: Bool = false) async {
        var cfg = config
        // 目录在 iCloud Drive 里时必须走 NSFileCoordinator，
        // 否则会和 Mac 端、Obsidian 互相覆盖。
        let inICloud = url.path.contains("com~apple~CloudDocs")
            || url.path.contains("Mobile Documents")
        cfg.roots = [.init(id: inICloud ? "icloud" : "local", path: url.path,
                           needsCoordination: inICloud, displayName: displayName)]
        config = cfg
        store = VaultStore(roots: cfg.vaultRoots)
        runLog = RunLogService(config: cfg)
        try? cfg.ensureDirectories()
        if persist { _ = try? cfg.save() }
        await reload()
    }

    /// 换 vault 根（设置页用）
    func apply(config newConfig: AppConfig) async {
        config = newConfig
        store = VaultStore(roots: newConfig.vaultRoots)
        runLog = RunLogService(config: newConfig)
        try? newConfig.ensureDirectories()
        _ = try? newConfig.save()
        await reload()
    }

    // MARK: iCloud 冲突

    /// 解决全部冲突。落败版本保留在 .conflicts/，绝不静默丢弃。
    @discardableResult
    func resolveConflicts() async -> [ConflictReport] {
        isResolvingConflicts = true
        defer { isResolvingConflicts = false }
        let reports = await store.resolveConflicts()
        conflictReports = reports
        await reload()
        notify(reports.isEmpty ? "没有需要处理的冲突"
                               : "已处理 \(reports.count) 处冲突，落败版本保留在 .conflicts/")
        return reports
    }

    /// 为尚未下载的 iCloud 文件发起下载
    func downloadPending() async {
        let n = await store.downloadPending()
        notify(n == 0 ? "没有待下载的文件" : "已为 \(n) 个文件发起下载")
        if n > 0 { await reload() }
    }

    // MARK: 导航

    func requestNewItem() {
        pendingNewItem = true
        selection = .ideas
    }

    func open(_ item: Item) {
        pendingItemID = item.id
        selection = .ideas
    }

    // MARK: 提示

    func notify(_ message: String) {
        statusMessage = message
        statusClearTask?.cancel()
        statusClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.statusMessage = ""
        }
    }

    // MARK: 写操作（统一在这里做，保证写完就刷新）

    func capture(_ text: String) async -> Bool {
        do {
            let url = try await store.capture(text)
            notify("已捕获 → \(url.lastPathComponent)")
            await reload()
            return true
        } catch {
            notify("捕获失败：\(error.localizedDescription)")
            return false
        }
    }

    /// 把一条随手记提升为带状态机的想法
    @discardableResult
    func promoteToIdea(_ text: String) async -> Item? {
        guard var item = IdeaActions.makeIdea(from: text) else {
            notify("内容为空")
            return nil
        }
        do {
            try await store.save(&item)
            notify("已建为想法「\(item.title)」")
            await reload()
            return item
        } catch {
            notify("创建失败：\(error.localizedDescription)")
            return nil
        }
    }

    func save(_ item: inout Item) async -> Bool {
        do {
            _ = try await store.save(&item)
            notify("已保存 → \(item.url?.lastPathComponent ?? item.title)")
            await reload()
            return true
        } catch {
            notify("保存失败：\(error.localizedDescription)")
            return false
        }
    }

    func delete(_ item: Item) async {
        do {
            let target = try await store.delete(item)
            notify("已移入回收站\(target.map { "：\($0.lastPathComponent)" } ?? "")")
            await reload()
        } catch {
            notify("删除失败：\(error.localizedDescription)")
        }
    }

    func archive(_ item: inout Item) async {
        do {
            let url = try await store.archive(&item)
            notify("已归档 → \(url.lastPathComponent)")
            await reload()
        } catch {
            notify("归档失败：\(error.localizedDescription)")
        }
    }
}
