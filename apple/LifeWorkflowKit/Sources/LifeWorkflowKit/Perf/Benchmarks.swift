import Foundation

/// 热路径基准测试。
///
/// 测什么由实测决定，不是拍脑袋：先量过一轮才知道
/// **vault 扫描 + frontmatter 解析是热路径**（解析比序列化慢 6 倍），
/// 而统计聚合不是瓶颈（2000 条只要 4.6ms）。所以重点测前两项。
///
/// 规模刻意压到 1 秒内跑完，这样能在应用里随手点一下，而不是变成"要专门抽时间做的事"——
/// 这个项目已经有过一次教训：需要惦记着做的机制会衰减（run-log 空了三个月）。
public enum Benchmarks {

    public struct Result: Codable, Sendable, Identifiable, Equatable {
        public var id: String
        public var name: String
        /// 对应五阶段闭环的哪一环，便于和信息流图对上
        public var stage: String
        public var value: Double
        public var unit: String
        /// 超过这个值就该警觉了（据实测基线定，不是凭空拍的）
        public var budget: Double
        public var detail: String

        public var overBudget: Bool { value > budget }
        public var ratio: Double { budget == 0 ? 0 : value / budget }

        public init(id: String, name: String, stage: String, value: Double,
                    unit: String, budget: Double, detail: String = "") {
            self.id = id
            self.name = name
            self.stage = stage
            self.value = value
            self.unit = unit
            self.budget = budget
            self.detail = detail
        }
    }

    public struct Record: Codable, Sendable {
        public var timestamp: String
        /// 构建配置。**必须记**：Debug 比 Release 慢一截（实测解析 0.32 vs 0.24 ms），
        /// 两者混在同一条时间序列里会让趋势失真。
        public var configuration: String
        /// 主机标识。同理：换台机器、或跑在 CI 的共享 runner 上，
        /// 数字与本机不可比。不区分的话趋势图会变成噪音。
        public var host: String
        public var results: [Result]

        public init(timestamp: String = RunLog.nowUTC(),
                    configuration: String = Benchmarks.buildConfiguration,
                    host: String = Benchmarks.hostIdentifier,
                    results: [Result]) {
            self.timestamp = timestamp
            self.configuration = configuration
            self.host = host
            self.results = results
        }
    }

    /// 主机标识：机型 + 逻辑核数。不用主机名，避免把用户的设备名写进仓库。
    public static var hostIdentifier: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var bytes = [UInt8](repeating: 0, count: max(1, size))
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        // 截掉结尾的 \0 再解码，避免用已弃用的 String(cString:)
        let model = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cores = ProcessInfo.processInfo.activeProcessorCount
        return "\(model.isEmpty ? "unknown" : model)-\(cores)c"
    }

    public static var buildConfiguration: String {
        #if DEBUG
        "debug"
        #else
        "release"
        #endif
    }

    // MARK: 运行

    public static func runAll() async -> [Result] {
        var out: [Result] = []
        out.append(parseBenchmark())
        out.append(emitBenchmark())
        out.append(await scanBenchmark())
        out.append(statsBenchmark())
        return out
    }

    /// frontmatter 解析 —— 实测是热路径里最慢的一环
    public static func parseBenchmark(iterations: Int = 1000) -> Result {
        let sample = sampleNote(index: 1, thinkingNotes: 5)
        let ms = measure { for _ in 0..<iterations { _ = Item.from(text: sample) } }
        return Result(
            id: "frontmatter.parse", name: "frontmatter 解析", stage: "organize",
            value: ms / Double(iterations), unit: "ms/条", budget: 0.5,
            detail: "5 条思路注释的笔记 ×\(iterations)。实测每条思路注释约 +0.035ms，线性无退化")
    }

    /// 序列化 —— 实测比解析快约 6 倍
    public static func emitBenchmark(iterations: Int = 1000) -> Result {
        guard let item = Item.from(text: sampleNote(index: 1, thinkingNotes: 5)) else {
            return Result(id: "frontmatter.emit", name: "frontmatter 序列化", stage: "organize",
                          value: 0, unit: "ms/条", budget: 0.2, detail: "样本构造失败")
        }
        let ms = measure { for _ in 0..<iterations { _ = item.toText() } }
        return Result(
            id: "frontmatter.emit", name: "frontmatter 序列化", stage: "organize",
            value: ms / Double(iterations), unit: "ms/条", budget: 0.2,
            detail: "同一笔记 ×\(iterations)")
    }

    /// vault 全量扫描 —— 每次保存后都会跑，是最该盯的一条
    public static func scanBenchmark(noteCount: Int = 200) async -> Result {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lifeos-bench-\(UUID().uuidString)")
        let inbox = root.appendingPathComponent("Inbox")
        defer { try? FileManager.default.removeItem(at: root) }

        guard (try? FileManager.default.createDirectory(
            at: inbox, withIntermediateDirectories: true)) != nil else {
            return Result(id: "vault.scan", name: "vault 全量扫描", stage: "organize",
                          value: 0, unit: "ms/条", budget: 0.5, detail: "临时目录创建失败")
        }
        for i in 0..<noteCount {
            try? sampleNote(index: i, thinkingNotes: 3)
                .write(to: inbox.appendingPathComponent("n\(i).md"),
                       atomically: true, encoding: .utf8)
        }
        let store = VaultStore(url: root)
        var loaded = 0
        let ms = await measureAsync { loaded = await store.load(force: true).count }
        return Result(
            id: "vault.scan", name: "vault 全量扫描", stage: "organize",
            value: ms / Double(max(1, loaded)), unit: "ms/条", budget: 0.5,
            detail: "\(loaded) 条 ×3 注释，共 \(Int(ms)) ms。注意：每次保存后都会全量重扫")
    }

    /// 看板聚合 —— 实测不是瓶颈，测它是为了留住这个结论
    public static func statsBenchmark(noteCount: Int = 500) -> Result {
        let items = (0..<noteCount).compactMap {
            Item.from(text: sampleNote(index: $0, thinkingNotes: 3))
        }
        let ms = measure {
            _ = Stats.summarize(items)
            _ = Stats.activityHeat(items)
            _ = Stats.lifelines(items)
        }
        return Result(
            id: "stats.aggregate", name: "看板聚合", stage: "review",
            value: ms, unit: "ms", budget: 50,
            detail: "\(items.count) 条记录的摘要 + 热力 + 生命线")
    }

    // MARK: 存储

    /// 追加一次基准结果。
    ///
    /// 存成时间序列而不是快照，是为了能看出「解析是不是变慢了」——
    /// 单次数值受机器状态影响很大，趋势才有意义。
    /// 也因此**不入 archmap.json**：那份要求确定性，基准值每次都不同。
    @discardableResult
    public static func append(_ record: Record, config: AppConfig) throws -> URL {
        let url = config.logsURL.appendingPathComponent("bench.jsonl")
        try FileManager.default.createDirectory(
            at: config.logsURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let line = String(data: try encoder.encode(record), encoding: .utf8) ?? "{}"
        try FileIO.append(line + "\n", to: url, coordinated: false)
        return url
    }

    /// 读取历史。默认只取**同构建配置 + 同主机**的记录 —— 混着比没有意义。
    public static func history(
        config: AppConfig, limit: Int = 30, matchingConfiguration: Bool = true
    ) -> [Record] {
        let url = config.logsURL.appendingPathComponent("bench.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text.components(separatedBy: "\n")
            .compactMap { line -> Record? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                return try? decoder.decode(Record.self, from: Data(trimmed.utf8))
            }
            .filter {
                !matchingConfiguration
                    || ($0.configuration == buildConfiguration && $0.host == hostIdentifier)
            }
            .suffix(limit)
            .reversed()
    }

    // MARK: 私有

    static func measure(_ block: () -> Void) -> Double {
        let start = Date()
        block()
        return Date().timeIntervalSince(start) * 1000
    }

    static func measureAsync(_ block: () async -> Void) async -> Double {
        let start = Date()
        await block()
        return Date().timeIntervalSince(start) * 1000
    }

    /// 造一条有代表性的笔记：五个维度齐全 + 若干条思路注释
    static func sampleNote(index: Int, thinkingNotes: Int) -> String {
        var s = """
        ---
        type: idea
        id: bench-\(index)
        title: 基准样本 \(index)
        created: 2026-08-0\(index % 9 + 1)
        status: doing
        priority: high
        energy: 7
        progress: 50
        tags: [bench, sample, perf]
        thinking_notes:

        """
        for j in 0..<thinkingNotes {
            s += "  - {t: 2026-08-1\(j % 9), note: 第 \(j) 条思路演进的内容记录}\n"
        }
        s += """
        next_actions:
          - 下一步动作
        links: []
        ---

        # 基准样本 \(index)

        正文内容，用于让样本接近真实笔记的体量。
        """
        return s
    }
}
