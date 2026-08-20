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

    // MARK: 版本归档（git）

    // 这一段本来长在 ArchiveView 里。挪进来的理由是**职责边界**：
    // 界面设计要交接出去，接手方改归档页的布局时不该碰到跑 git 命令的代码。
    // 视图只留表单输入（提交信息、版本号、说明），那才是视图自己的状态。
    //
    // 整段限定 macOS：GitService 内部起子进程，而 iOS 沙盒不允许 fork。

    #if os(macOS)
    /// 归档的是**代码仓库**，不是 vault 根——两者可能不是同一个目录。
    /// 从各个 vault 根向上搜索最近的 .git，找不到就没法归档。
    private(set) var gitRepo: URL?
    private(set) var gitStatus = GitService.Status()
    private(set) var gitHistory: [GitService.Commit] = []
    private(set) var gitTags: [String] = []
    /// 命令输出流水，界面上原样展示——git 出错时的真实信息比一句「失败了」有用得多
    private(set) var gitLog: [String] = []
    private(set) var isGitBusy = false

    func loadGit() async {
        gitRepo = config.roots.lazy
            .compactMap { GitService.findRepository(startingAt: URL(fileURLWithPath: $0.path)) }
            .first
        guard let repo = gitRepo else {
            gitStatus = GitService.Status()
            gitHistory = []
            gitTags = []
            return
        }
        gitStatus = await GitService.status(repo: repo)
        gitHistory = await GitService.history(repo: repo, limit: 30)
        gitTags = await GitService.tags(repo: repo)
    }

    /// 提交（可选推送）。返回是否成功，供界面决定要不要清空输入框。
    @discardableResult
    func gitSync(message: String, push: Bool) async -> Bool {
        guard let repo = gitRepo else { return false }
        isGitBusy = true
        defer { isGitBusy = false }
        gitLog.append("──── 同步 ────")
        let outcome = await GitService.sync(
            repo: repo, message: message, push: push,
            log: { [weak self] line in Task { @MainActor in self?.gitLog.append(line) } })
        gitLog.append((outcome.ok ? "✅ " : "❌ ") + outcome.message)
        notify(outcome.message)
        await logOperation(
            objective: push ? "提交并推送" : "提交（不推送）",
            status: outcome.ok ? .success : .failed,
            tools: ["git"], errors: outcome.ok ? [] : [outcome.message])
        await loadGit()
        return outcome.ok
    }

    @discardableResult
    func gitRelease(version: String, notes: String) async -> Bool {
        guard let repo = gitRepo else { return false }
        isGitBusy = true
        defer { isGitBusy = false }
        gitLog.append("──── 发布 \(version) ────")
        let outcome = await GitService.release(
            repo: repo, version: version, notes: notes,
            log: { [weak self] line in Task { @MainActor in self?.gitLog.append(line) } })
        gitLog.append((outcome.ok ? "✅ " : "❌ ") + outcome.message)
        notify(outcome.message)
        await logOperation(
            objective: "发布里程碑 \(version)",
            status: outcome.ok ? .success : .failed,
            tools: ["git", "gh"], errors: outcome.ok ? [] : [outcome.message])
        await loadGit()
        return outcome.ok
    }
    #endif

    // MARK: 复盘聚合

    private(set) var reviewStats = ReviewService.Stats()
    private(set) var reviewLogs: [RunLog] = []

    /// 按区间重算复盘统计。天数由界面给（它有那个选择器），聚合逻辑不归界面管。
    ///
    /// 顺带刷新技能库提议：两者共用同一个 `since`，分成两次调用只会让界面
    /// 去操心「先算哪个、区间对不对得上」。
    func refreshReview(days: Int) async {
        let since = ReviewService.defaultSince(days: days)
        reviewLogs = await runLog.load(since: since)
        reviewStats = ReviewService.aggregate(reviewLogs, since: since)
        await refreshSkills(since: since)
    }

    /// 手工补记一条运行日志。返回是否成功，供界面决定要不要清空表单。
    @discardableResult
    func appendRunLog(_ log: RunLog, refreshingDays days: Int) async -> Bool {
        do {
            let saved = try await runLog.append(log)
            notify("已记录 \(saved.runID)")
            await refreshReview(days: days)
            return true
        } catch {
            notify("记录失败：\(error.localizedDescription)")
            return false
        }
    }

    /// 把当前区间的复盘渲染成 Markdown，落到 vault 的每日笔记目录旁。
    func writeReviewReport() async {
        let markdown = ReviewService.renderMarkdown(reviewStats)
        let target = store.dailyNote(date: nil)
            .deletingLastPathComponent()
            .appendingPathComponent("周复盘-\(reviewStats.since).md")
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try markdown.write(to: target, atomically: true, encoding: .utf8)
            notify("周复盘已生成 → \(target.lastPathComponent)")
            await logOperation(objective: "生成周复盘 \(reviewStats.since)",
                               status: .success, tools: ["review"], outputs: [target.path])
        } catch {
            notify("生成失败：\(error.localizedDescription)")
        }
    }

    // MARK: 格式转换

    // 整段限定 macOS：ConvertService 要起子进程调 pandoc / markitdown，
    // 而 iOS 沙盒不允许 fork，那边根本没有这个类型。
    #if os(macOS)
    private(set) var convertLog: [String] = []
    private(set) var convertResult: URL?
    private(set) var isConverting = false
    private(set) var convertCache: (count: Int, bytes: Int) = (0, 0)
    /// 外部工具体检结果。视图只负责画勾和叉，装没装是服务层的事。
    private(set) var convertTools: [ConvertService.ToolStatus] = []

    func refreshConvertEnvironment() {
        convertTools = ConvertService.toolStatus()
        convertCache = ConvertService.cacheStats(config: config)
    }

    func appendConvertLog(_ line: String) { convertLog.append(line) }

    func convert(source: URL, to target: ConvertService.Target, output: String) async {
        isConverting = true
        convertResult = nil
        defer { isConverting = false }
        convertLog.append("──── \(source.lastPathComponent) ────")
        let started = Date()
        let trimmed = output.trimmingCharacters(in: .whitespaces)
        let outcome = await ConvertService.convert(
            source: source, to: target,
            output: trimmed.isEmpty ? nil : URL(fileURLWithPath: trimmed),
            config: config,
            log: { [weak self] line in Task { @MainActor in self?.convertLog.append(line) } })

        if outcome.ok {
            convertResult = outcome.output
            convertLog.append("✅ \(outcome.message)\(outcome.cached ? "（命中缓存，未重复计算）" : "")")
            notify("转换完成 → \(outcome.output?.lastPathComponent ?? "")")
        } else {
            convertLog.append("❌ \(outcome.message)")
            notify("转换失败")
        }
        // 自动留痕：这条数据正是周复盘提炼 skill 的原料
        await logOperation(
            objective: "转换 \(source.lastPathComponent) → \(target.rawValue)",
            status: outcome.ok ? .success : .failed,
            tools: [ConvertService.markdownTool(), "pandoc"].compactMap { $0 },
            outputs: outcome.output.map { [$0.path] } ?? [],
            errors: outcome.ok ? [] : [outcome.message],
            duration: Date().timeIntervalSince(started),
            notes: outcome.cached ? "命中缓存" : "")
        refreshConvertEnvironment()
    }

    func clearConvertCache() {
        let n = ConvertService.clearCache(config: config)
        convertLog.append("已清空 \(n) 条缓存")
        refreshConvertEnvironment()
    }
    #endif

    // MARK: Apple 提醒 / 日历导入

    /// 从提醒事项或日历导入到当天的 Daily。两端共用——`EventKitBridge` 按
    /// `canImport(EventKit)` 门禁，iOS 上同样可用（只有 watchOS 是只读的）。
    ///
    /// 回调式的 `log` 让界面拿到逐行进度——权限流程失败时，用户需要看到
    /// 具体卡在哪一步，一句「导入失败」没法指导他去开哪个开关。
    func importFromApple(
        kind: AppleImportKind, listName: String, days: Int, includeCompleted: Bool,
        log: @escaping @MainActor (String) -> Void
    ) async {
        let bridge = EventKitBridge()
        let section = kind == .reminders ? "提醒" : "日程"
        log("[\(section)] 请求权限…")

        let access = kind == .reminders
            ? await bridge.requestRemindersAccess()
            : await bridge.requestCalendarAccess()

        switch access {
        case .denied:
            let which = kind == .reminders ? "提醒事项" : "日历"
            #if os(macOS)
            log("❌ 权限被拒绝。去 系统设置 → 隐私与安全性 → \(which) 开启")
            #else
            log("❌ 权限被拒绝。去 设置 → 隐私与安全性 → \(which) 开启")
            #endif
            return
        case .unavailable(let why):
            log("❌ 不可用：\(why)")
            return
        case .granted:
            break
        }

        let markdown: String
        let label: String
        if kind == .reminders {
            let items = await bridge.reminders(listName: listName, includeCompleted: includeCompleted)
            guard !items.isEmpty else { log("[提醒] 该列表没有可导出的项"); return }
            markdown = EventKitBridge.markdown(for: items)
            label = "\(items.count) 条提醒"
        } else {
            let items = await bridge.events(calendarName: listName, days: days)
            guard !items.isEmpty else { log("[日程] 未来 \(days) 天没有日程"); return }
            markdown = EventKitBridge.markdown(for: items)
            label = "\(items.count) 个日程"
        }

        // 重复导入是替换那一段，不是往后追加
        let note = store.dailyNote()
        do {
            _ = try await store.upsertSection(at: note, heading: section, content: markdown)
            log("✅ \(label) → \(note.lastPathComponent) 的「## \(section)」段")
            notify("已导入 \(label)")
            await reload()
        } catch {
            log("❌ 写入失败：\(error.localizedDescription)")
        }
    }

    // MARK: 提示词

    /// 能不能用 LLM 重写。界面据此决定按钮可不可点，不必自己去问服务层。
    var isLLMAvailable: Bool { PromptService.llmAvailable }

    private(set) var promptHistory: [URL] = []

    func refreshPromptHistory() {
        promptHistory = PromptService.list(config: config)
    }

    /// 把口语需求重写成提示词文档。返回正文与落盘位置，失败时返回错误文案。
    func rewritePrompt(_ raw: String, useLLM: Bool) async -> (content: String, url: URL?) {
        let started = Date()
        let objective = "重写提示词：\(String(raw.prefix(30)))"
        do {
            let doc = try await PromptService.rewrite(raw, useLLM: useLLM, config: config)
            refreshPromptHistory()
            notify("[\(doc.mode.label)] 已生成 → \(doc.outputURL.lastPathComponent)")
            await logOperation(objective: objective, status: .success,
                               tools: [useLLM ? "llm" : "scaffold"],
                               outputs: [doc.outputURL.path],
                               duration: Date().timeIntervalSince(started))
            return (doc.content, doc.outputURL)
        } catch {
            notify("生成失败")
            await logOperation(objective: objective, status: .failed,
                               tools: [useLLM ? "llm" : "scaffold"],
                               errors: [error.localizedDescription],
                               duration: Date().timeIntervalSince(started))
            return ("生成失败：\n\(error.localizedDescription)", nil)
        }
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

/// 导入来源。提醒与日程的权限流程、取数、渲染都不同，但对界面是同一个动作。
enum AppleImportKind: Sendable {
    case reminders
    case events
}
