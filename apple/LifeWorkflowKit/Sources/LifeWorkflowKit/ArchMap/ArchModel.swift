import Foundation

/// 架构地图的数据模型。
///
/// 设计要点：**只装结构，不装指标**。
/// 结构（模块、依赖、约束校验结果）变化才值得留在版本历史里，可以 git diff 出
/// 「这次改动让依赖图变成了什么样」；而变更频率这类指标每次提交都在变，
/// 写进来只会制造噪音提交，改由应用打开时现算。
public struct ArchModel: Codable, Sendable, Equatable {
    public var layers: [Layer]
    public var modules: [Module]
    public var edges: [Edge]
    public var artifacts: [Artifact]
    public var stages: [Stage]
    public var invariants: [Invariant]

    public init(
        layers: [Layer] = [], modules: [Module] = [], edges: [Edge] = [],
        artifacts: [Artifact] = [], stages: [Stage] = [], invariants: [Invariant] = []
    ) {
        self.layers = layers
        self.modules = modules
        self.edges = edges
        self.artifacts = artifacts
        self.stages = stages
        self.invariants = invariants
    }

    public var hasViolations: Bool { invariants.contains { !$0.violations.isEmpty } }
    public var violationCount: Int { invariants.reduce(0) { $0 + $1.violations.count } }

    public func module(id: String) -> Module? { modules.first { $0.id == id } }

    /// 扇入：有多少模块依赖我。高扇入 + 高变更频率 = 改它风险大
    public func fanIn(_ id: String) -> Int {
        Set(edges.filter { $0.to == id }.map(\.from)).count
    }

    public func fanOut(_ id: String) -> Int {
        Set(edges.filter { $0.from == id }.map(\.to)).count
    }

    // MARK: 序列化（确定性）

    public static func decode(from data: Data) throws -> ArchModel {
        try JSONDecoder().decode(ArchModel.self, from: data)
    }

    /// 排序 + sortedKeys + 无时间戳 ⇒ 同一份源码永远产出同一份字节
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(normalized())
    }

    /// 所有集合排序，消除遍历顺序带来的不确定性
    public func normalized() -> ArchModel {
        ArchModel(
            layers: layers.sorted { $0.rank < $1.rank },
            modules: modules.map(\.normalized).sorted { $0.id < $1.id },
            edges: edges.sorted { ($0.from, $0.to) < ($1.from, $1.to) },
            artifacts: artifacts.map(\.normalized).sorted { $0.id < $1.id },
            stages: stages.map(\.normalized).sorted { $0.order < $1.order },
            invariants: invariants.map(\.normalized).sorted { $0.id < $1.id })
    }
}

// MARK: - 分层

/// 架构分层。`rank` 越小越靠底层；依赖只能从高 rank 指向低 rank。
public struct Layer: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var rank: Int
    public var summary: String

    public init(id: String, name: String, rank: Int, summary: String = "") {
        self.id = id
        self.name = name
        self.rank = rank
        self.summary = summary
    }
}

// MARK: - 模块

/// 一个目录组。图上的节点粒度是目录而非文件——54 个文件画成图没法看，
/// 10 来个目录组才读得懂；文件级细节留给点击下钻。
public struct Module: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var path: String
    public var layerID: String
    /// 所属产物：kit（共享核心包）/ macOS / iOS / shared
    public var target: String
    public var files: [SourceFile]
    public var publicTypes: [String]

    public var lineCount: Int { files.reduce(0) { $0 + $1.lines } }
    public var fileCount: Int { files.count }
    /// 只在某个平台编译的模块
    public var platforms: [String] {
        Array(Set(files.flatMap(\.platformGates))).sorted()
    }

    public init(
        id: String, name: String, path: String, layerID: String, target: String,
        files: [SourceFile] = [], publicTypes: [String] = []
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.layerID = layerID
        self.target = target
        self.files = files
        self.publicTypes = publicTypes
    }

    var normalized: Module {
        var copy = self
        copy.files = files.sorted { $0.path < $1.path }
        copy.publicTypes = Array(Set(publicTypes)).sorted()
        return copy
    }
}

public struct SourceFile: Codable, Sendable, Equatable, Identifiable {
    public var path: String
    public var lines: Int
    public var imports: [String]
    /// 文件里出现过的 `#if os(...)` 平台名
    public var platformGates: [String]
    public var publicTypes: [String]
    /// 引用到的、被约束关注的符号及其是否位于条件编译区内
    public var guardedSymbols: [GuardedSymbol]

    public var id: String { path }

    public init(
        path: String, lines: Int, imports: [String] = [],
        platformGates: [String] = [], publicTypes: [String] = [],
        guardedSymbols: [GuardedSymbol] = []
    ) {
        self.path = path
        self.lines = lines
        self.imports = imports
        self.platformGates = platformGates
        self.publicTypes = publicTypes
        self.guardedSymbols = guardedSymbols
    }
}

/// 某个敏感符号（如 `Process`）出现的位置，以及它是否被 `#if os(...)` 包住
public struct GuardedSymbol: Codable, Sendable, Equatable {
    public var symbol: String
    public var line: Int
    public var insideGate: String?

    public init(symbol: String, line: Int, insideGate: String?) {
        self.symbol = symbol
        self.line = line
        self.insideGate = insideGate
    }
}

// MARK: - 依赖边

public struct Edge: Codable, Sendable, Equatable {
    public var from: String
    public var to: String
    /// 造成这条边的文件（下钻时告诉用户"为什么有这条依赖"）
    public var viaFiles: [String]

    public init(from: String, to: String, viaFiles: [String] = []) {
        self.from = from
        self.to = to
        self.viaFiles = viaFiles.sorted()
    }
}

// MARK: - 信息流

/// 数据产物：vault 的 Markdown、run-log、skills、prompts、缓存…
/// 生产者/消费者由扫描「标志符号」得出，不是手写死的。
public struct Artifact: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var path: String
    public var summary: String
    /// 判定「谁碰了它」用的符号
    public var markers: [String]
    /// 声明这个产物路径的模块（只定义位置，不读写内容）
    public var declaredBy: [String]
    public var producers: [String]
    public var consumers: [String]

    public init(
        id: String, name: String, path: String, summary: String = "",
        markers: [String] = [], declaredBy: [String] = [],
        producers: [String] = [], consumers: [String] = []
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.summary = summary
        self.markers = markers
        self.declaredBy = declaredBy
        self.producers = producers
        self.consumers = consumers
    }

    var normalized: Artifact {
        var copy = self
        copy.markers = markers.sorted()
        copy.declaredBy = Array(Set(declaredBy)).sorted()
        copy.producers = Array(Set(producers)).sorted()
        copy.consumers = Array(Set(consumers)).sorted()
        return copy
    }
}

/// 五阶段闭环里的一环
public struct Stage: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var order: Int
    public var summary: String
    public var moduleIDs: [String]
    public var artifactIDs: [String]

    public init(
        id: String, name: String, order: Int, summary: String = "",
        moduleIDs: [String] = [], artifactIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.summary = summary
        self.moduleIDs = moduleIDs
        self.artifactIDs = artifactIDs
    }

    var normalized: Stage {
        var copy = self
        copy.moduleIDs = Array(Set(moduleIDs)).sorted()
        copy.artifactIDs = Array(Set(artifactIDs)).sorted()
        return copy
    }
}

// MARK: - 约束

/// 一条架构约束及其校验结果。
///
/// 这是整张地图最有价值的部分：图会过时，被强制的约束不会。
public struct Invariant: Codable, Sendable, Equatable, Identifiable {
    public enum Severity: String, Codable, Sendable {
        /// 违反即 CI 失败
        case blocking
        /// 只提示，供决策参考
        case advisory

        public var label: String {
            switch self {
            case .blocking: "硬约束"
            case .advisory: "参考"
            }
        }
    }

    public var id: String
    public var title: String
    /// 为什么有这条规则 —— 不写清楚，后人只会觉得它碍事
    public var rationale: String
    public var severity: Severity
    public var violations: [Violation]

    public var passed: Bool { violations.isEmpty }

    public init(
        id: String, title: String, rationale: String,
        severity: Severity = .blocking, violations: [Violation] = []
    ) {
        self.id = id
        self.title = title
        self.rationale = rationale
        self.severity = severity
        self.violations = violations
    }

    var normalized: Invariant {
        var copy = self
        copy.violations = violations.sorted { ($0.file, $0.line) < ($1.file, $1.line) }
        return copy
    }
}

public struct Violation: Codable, Sendable, Equatable {
    public var file: String
    public var line: Int
    public var detail: String

    public init(file: String, line: Int = 0, detail: String) {
        self.file = file
        self.line = line
        self.detail = detail
    }
}
