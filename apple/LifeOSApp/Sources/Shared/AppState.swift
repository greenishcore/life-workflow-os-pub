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

    // 主线 4：技能库与本期可沉淀
    private(set) var skills: [Skill] = []
    private(set) var proposals: [SkillsService.Proposal] = []

    // 架构地图
    private(set) var archModel: ArchModel?
    private(set) var archRisks: [ArchMetrics.ModuleRisk] = []
    private(set) var archRepo: URL?
    private(set) var archError: String?
    private(set) var isLoadingArch = false

    // 效率与稳健性
    private(set) var benchmarks: [Benchmarks.Result] = []
    private(set) var benchHistory: [Benchmarks.Record] = []
    private(set) var runtimeOps: [RuntimeStats.Operation] = []
    private(set) var isBenchmarking = false

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

    // MARK: 架构地图

    /// 加载架构地图：结构读 archmap.json，指标现算。
    ///
    /// 优先读入库的 JSON（与 CI 生成的一致）；读不到就直接从源码提取，
    /// 这样刚 clone 下来还没跑过 CI 也能看。
    func loadArchMap(recomputeFromSource: Bool = false) async {
        #if !os(macOS)
        // 架构地图是 Mac 端功能：定位仓库要用 GitService（内部起子进程），
        // 而 iOS 沙盒不允许 fork 子进程 —— 这正是「子进程调用限定 macOS」那条约束
        archError = "架构地图仅在 macOS 端提供"
        #else
        isLoadingArch = true
        archError = nil
        defer { isLoadingArch = false }

        let start = config.roots.first.map { URL(fileURLWithPath: $0.path) }
            ?? URL(fileURLWithPath: NSHomeDirectory())
        guard let repo = GitService.findRepository(startingAt: start) else {
            archError = "从 vault 向上没找到 git 仓库，无法定位源码"
            archModel = nil
            return
        }
        archRepo = repo

        let jsonURL = repo.appendingPathComponent("docs/02-architecture/archmap.json")
        var model: ArchModel?
        if !recomputeFromSource, let data = try? Data(contentsOf: jsonURL) {
            model = try? ArchModel.decode(from: data)
        }
        if model == nil {
            model = try? ArchExtractor.extract(repoRoot: repo).model
        }
        guard let model else {
            archError = "既读不到 archmap.json，也无法从源码提取"
            archModel = nil
            return
        }
        archModel = model

        let churn = await ArchMetrics.churn(repo: repo, modules: model.modules)
        archRisks = ArchMetrics.risks(model: model, churn: churn,
                                      testedModuleIDs: ArchMetrics.testedModuleIDs(model: model))
        #endif
    }

    // MARK: 效率与稳健性

    /// 读上次的基准结果与运行时指标。
    ///
    /// 基准不自动跑——它要造 200 条临时笔记，跑一次几百毫秒，
    /// 每次打开页面都跑既没必要也会拖慢体验。
    func loadPerformance() async {
        benchHistory = Benchmarks.history(config: config)
        benchmarks = benchHistory.first?.results ?? []
        let logs = await runLog.load(since: ReviewService.defaultSince(days: 30))
        runtimeOps = RuntimeStats.byOperation(logs)
    }

    /// 手动跑一次基准并记入时间序列
    func runBenchmarks() async {
        isBenchmarking = true
        defer { isBenchmarking = false }
        let results = await Benchmarks.runAll()
        benchmarks = results
        do {
            _ = try Benchmarks.append(.init(results: results), config: config)
            benchHistory = Benchmarks.history(config: config)
            let over = results.filter(\.overBudget)
            notify(over.isEmpty
                   ? "基准已跑完并记入 logs/bench.jsonl"
                   : "\(over.count) 项超出预算：\(over.map(\.name).joined(separator: "、"))")
        } catch {
            notify("基准结果写入失败：\(error.localizedDescription)")
        }
    }

    // MARK: 技能库（主线 4）

    /// 加载技能库，并根据区间内的运行日志算出「本期可沉淀什么」
    func refreshSkills(since: String) async {
        skills = SkillsService.load(from: config.skillsURL)
        let logs = await runLog.load(since: since)
        proposals = SkillsService.propose(logs: logs, existing: skills)
    }

    /// 采纳一条提议：把草稿写进技能库
    func adopt(_ proposal: SkillsService.Proposal) async {
        guard let draft = proposal.draft else { return }
        do {
            let url = try SkillsService.save(draft, to: config.skillsURL)
            notify("已沉淀为 skill → \(url.lastPathComponent)，去补全解法")
            await logOperation(objective: "沉淀 skill：\(draft.name)",
                               status: .success, tools: ["skills"], outputs: [url.path])
            skills = SkillsService.load(from: config.skillsURL)
            proposals.removeAll { $0.id == proposal.id }
        } catch {
            notify("沉淀失败：\(error.localizedDescription)")
        }
    }

    /// 记一次 skill 使用（效果评分那一环的最小版本）
    func recordSkillUse(_ skill: Skill) async {
        var updated = skill
        updated.recordUse()
        do {
            _ = try SkillsService.save(updated, to: config.skillsURL)
            skills = SkillsService.load(from: config.skillsURL)
            notify("「\(skill.name)」已记 \(updated.uses) 次使用")
        } catch {
            notify("记录失败：\(error.localizedDescription)")
        }
    }

    // MARK: 运行留痕

    /// 记录一次操作。
    ///
    /// 主线 4（信息流 → skills 演进）此前是空转的：run-log.jsonl 从没被写过，
    /// 因为记录靠手动敲命令。应用自己的转换 / git 同步 / 提示词重写本来就是
    /// 「agent 操作」，让它们自动留痕，这条链才有真实数据可聚合。
    func logOperation(
        objective: String,
        status: RunLog.Status,
        tools: [String] = [],
        outputs: [String] = [],
        errors: [String] = [],
        duration: TimeInterval = 0,
        notes: String = ""
    ) async {
        let log = RunLog(objective: objective, agent: "app",
                         toolsUsed: tools, outputs: outputs, status: status,
                         errors: errors, durationSeconds: duration, notes: notes)
        _ = try? await runLog.append(log)
    }

    /// 计时执行并自动留痕
    func tracked<T>(
        _ objective: String, tools: [String] = [],
        operation: () async -> (result: T, ok: Bool, outputs: [String], errors: [String])
    ) async -> T {
        let start = Date()
        let outcome = await operation()
        await logOperation(objective: objective,
                           status: outcome.ok ? .success : .failed,
                           tools: tools, outputs: outcome.outputs, errors: outcome.errors,
                           duration: Date().timeIntervalSince(start))
        return outcome.result
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
