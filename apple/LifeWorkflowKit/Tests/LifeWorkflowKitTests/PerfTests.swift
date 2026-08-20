import Foundation
import Testing
@testable import LifeWorkflowKit

@Suite("稳健性静态信号")
struct RobustnessScanTests {

    @Test("统计 try? / try! / 强制解包 / fatalError")
    func counts() {
        let file = SourceScanner.scan(text: """
        import Foundation
        func a() {
            let x = try? load()
            let y = try! load()
            let z = value!
            fatalError("boom")
        }
        func b() throws {
            do { try c() } catch { print(error) }
        }
        """, path: "a.swift")
        let r = file.robustness
        #expect(r.silencedErrors == 1)
        #expect(r.forcedTries == 1)
        #expect(r.forceUnwraps == 1)
        #expect(r.fatalSites == 1)
        #expect(r.throwingFunctions == 1)
        #expect(r.catchBlocks == 1)
        #expect(r.crashRisks == 3, "try! + 强制解包 + fatalError 都是崩溃风险")
    }

    // try! 和 try? 都以 try 开头，先判 try? 会把 try! 漏掉
    @Test("try! 不会被 try? 的匹配吃掉")
    func tryBangNotSwallowed() {
        let file = SourceScanner.scan(text: "let a = try! x()\nlet b = try? y()", path: "a.swift")
        #expect(file.robustness.forcedTries == 1)
        #expect(file.robustness.silencedErrors == 1)
    }

    @Test("!= 与前缀否定不算强制解包")
    func notOperatorIsNotForceUnwrap() {
        let file = SourceScanner.scan(text: """
        if a != b, !flag, c !== d { }
        let x = value!
        """, path: "a.swift")
        #expect(file.robustness.forceUnwraps == 1, "只有 value! 算")
    }

    @Test("注释与字符串里的写法不计入")
    func commentsAndStringsIgnored() {
        let file = SourceScanner.scan(text: """
        // 这里本来写的是 try! 后来改了
        let s = "try? 只是文案"
        let ok = 1
        """, path: "a.swift")
        #expect(file.robustness.forcedTries == 0)
        #expect(file.robustness.silencedErrors == 0)
    }

    @Test("模块级聚合与每百行密度")
    func moduleAggregation() {
        let module = Module(
            id: "m", name: "M", path: "p", layerID: "data", target: "kit",
            files: [
                SourceFile(path: "a.swift", lines: 100,
                           robustness: .init(silencedErrors: 2, forceUnwraps: 1)),
                SourceFile(path: "b.swift", lines: 100,
                           robustness: .init(silencedErrors: 4)),
            ])
        #expect(module.robustness.silencedErrors == 6)
        #expect(module.robustness.forceUnwraps == 1)
        #expect(module.silencedPer100Lines == 3.0)
    }

    @Test("真实仓库的稳健性热点与实测吻合")
    func realRepoHotspots() throws {
        let model = try ArchExtractor.extract(repoRoot: repoRoot).model
        let ranked = model.modules
            .sorted { $0.robustness.silencedErrors > $1.robustness.silencedErrors }
        let top = try #require(ranked.first)
        #expect(["Services", "Store"].contains(top.name),
                "静默吞错最多的应是 Services 或 Store，实际是 \(top.name)")
        // Frontmatter 是纯逻辑，不该有吞错
        let fm = try #require(model.modules.first { $0.name == "Frontmatter" })
        #expect(fm.robustness.silencedErrors == 0)
        #expect(fm.robustness.crashRisks == 0)
    }
}

@Suite("热路径基准")
struct BenchmarkTests {

    @Test("四项基准都能跑出正数")
    func allRun() async {
        let results = await Benchmarks.runAll()
        #expect(results.count == 4)
        #expect(results.allSatisfy { $0.value > 0 }, "\(results.map { "\($0.id)=\($0.value)" })")
        #expect(Set(results.map(\.id))
                == ["frontmatter.parse", "frontmatter.emit", "vault.scan", "stats.aggregate"])
    }

    @Test("序列化确实比解析快 —— 这是选择优化方向的依据")
    func emitFasterThanParse() {
        let parse = Benchmarks.parseBenchmark(iterations: 300)
        let emit = Benchmarks.emitBenchmark(iterations: 300)
        #expect(emit.value < parse.value,
                "序列化 \(emit.value) 应快于解析 \(parse.value)")
    }

    @Test("预算判定")
    func budgetFlag() {
        let ok = Benchmarks.Result(id: "x", name: "x", stage: "s",
                                   value: 0.3, unit: "ms", budget: 0.5)
        let bad = Benchmarks.Result(id: "y", name: "y", stage: "s",
                                    value: 0.9, unit: "ms", budget: 0.5)
        #expect(!ok.overBudget)
        #expect(bad.overBudget)
        #expect(abs(bad.ratio - 1.8) < 0.001)
    }

    // Debug 比 Release 慢一截，混在一条序列里趋势就没意义了
    @Test("记录会带上构建配置，读取时默认只取同配置的")
    func configurationIsolation() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bench-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = AppConfig(logsPath: dir.path)

        let sample = Benchmarks.Result(id: "x", name: "x", stage: "s",
                                       value: 1, unit: "ms", budget: 2)
        try Benchmarks.append(.init(configuration: "debug", results: [sample]), config: config)
        try Benchmarks.append(.init(configuration: "release", results: [sample]), config: config)

        let all = Benchmarks.history(config: config, matchingConfiguration: false)
        #expect(all.count == 2)
        let matched = Benchmarks.history(config: config)
        #expect(matched.count == 1)
        #expect(matched[0].configuration == Benchmarks.buildConfiguration)
    }

    @Test("历史按时间倒序，最新在前")
    func historyOrder() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bench-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = AppConfig(logsPath: dir.path)
        let r = Benchmarks.Result(id: "x", name: "x", stage: "s", value: 1, unit: "ms", budget: 2)
        for stamp in ["2026-08-01T00:00:00Z", "2026-08-02T00:00:00Z"] {
            try Benchmarks.append(
                .init(timestamp: stamp, configuration: Benchmarks.buildConfiguration, results: [r]),
                config: config)
        }
        let history = Benchmarks.history(config: config)
        #expect(history.first?.timestamp == "2026-08-02T00:00:00Z")
    }
}

@Suite("运行时指标")
struct RuntimeStatsTests {

    private func log(_ objective: String, seconds: Double,
                     status: RunLog.Status = .success,
                     tools: [String] = [], notes: String = "") -> RunLog {
        RunLog(objective: objective, toolsUsed: tools, status: status,
               durationSeconds: seconds, notes: notes)
    }

    @Test("按操作类型分组：取 objective 的首个词组")
    func grouping() {
        #expect(RuntimeStats.kind(of: "转换 论文.pdf → docx") == "转换")
        #expect(RuntimeStats.kind(of: "重写提示词：帮我做个看板") == "重写提示词")
        #expect(RuntimeStats.kind(of: "提交并推送") == "提交并推送")
    }

    @Test("分位数计算")
    func percentiles() {
        let sorted = [1.0, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        #expect(abs(RuntimeStats.percentile(sorted, 0.5) - 5.5) < 0.001)
        #expect(RuntimeStats.percentile(sorted, 1.0) == 10)
        #expect(RuntimeStats.percentile([], 0.5) == 0)
        #expect(RuntimeStats.percentile([42], 0.95) == 42, "单样本时分位数就是它自己")
    }

    @Test("聚合出耗时分布与成功率")
    func aggregation() throws {
        let logs = [
            log("转换 a.pdf", seconds: 1, tools: ["pandoc"]),
            log("转换 b.pdf", seconds: 3, tools: ["pandoc"]),
            log("转换 c.pdf", seconds: 9, status: .failed, tools: ["pandoc"]),
            log("提交并推送", seconds: 2, tools: ["git"]),
        ]
        let ops = RuntimeStats.byOperation(logs)
        let convert = try #require(ops.first { $0.kind == "转换" })
        #expect(convert.count == 3)
        #expect(convert.successCount == 2)
        #expect(abs(convert.successRate - 2.0 / 3) < 0.001)
        #expect(convert.max == 9000)
        #expect(convert.total == 13000)
        // 总耗时最多的排最前
        #expect(ops.first?.kind == "转换")
    }

    @Test("缓存命中率只对用了转换工具的操作统计")
    func cacheHitRate() throws {
        let logs = [
            log("转换 a.pdf", seconds: 1, tools: ["markitdown"], notes: "命中缓存"),
            log("转换 b.pdf", seconds: 5, tools: ["markitdown"]),
            log("提交并推送", seconds: 1, tools: ["git"]),
        ]
        let ops = RuntimeStats.byOperation(logs)
        let convert = try #require(ops.first { $0.kind == "转换" })
        #expect(convert.cacheHitRate == 0.5)
        let commit = try #require(ops.first { $0.kind == "提交并推送" })
        #expect(commit.cacheHitRate == nil, "与缓存无关的操作不该给出命中率")
    }

    @Test("空日志不崩")
    func emptyLogs() {
        #expect(RuntimeStats.byOperation([]).isEmpty)
        let overall = RuntimeStats.overall([])
        #expect(overall.count == 0 && overall.successRate == 0)
    }
}
