import Foundation

/// 架构地图的**实时指标**：变更频率与风险排序。
///
/// 刻意不写进 archmap.json —— 变更频率每次提交都在变，
/// 入库只会制造噪音提交。结构留在版本历史里，指标打开应用时现算。
public enum ArchMetrics {

    public struct ModuleRisk: Sendable, Identifiable, Equatable {
        public let moduleID: String
        public let name: String
        public let layerID: String
        public let lines: Int
        public let fileCount: Int
        /// 最近 N 天该目录被改动的次数
        public let churn: Int
        /// 有多少模块依赖它
        public let fanIn: Int
        public let fanOut: Int
        public let hasTests: Bool

        public var id: String { moduleID }

        /// 风险 = 改得勤 × 被依赖得多，有测试则减半。
        ///
        /// 刻意用一个能一句话解释清楚的算式，而不是黑箱评分：
        /// 常改说明还在演进，被依赖多说明改错了波及面大，
        /// 有测试至少能在改错时被挡一下。
        public var risk: Double {
            let base = Double(max(churn, 1)) * Double(max(fanIn, 1))
            return hasTests ? base / 2 : base
        }

        public var explanation: String {
            "近期改动 \(churn) 次 · 被 \(fanIn) 个模块依赖 · "
            + (hasTests ? "有测试覆盖（风险减半）" : "无测试覆盖")
        }
    }

    /// 用 git 统计各模块目录的改动次数。拿不到 git 时全部返回 0，不报错。
    public static func churn(
        repo: URL, modules: [Module], days: Int = 90
    ) async -> [String: Int] {
        var out: [String: Int] = [:]
        #if os(macOS)
        for module in modules {
            let result = await ProcessRunner.run(
                "git", ["log", "--since=\(days).days", "--format=%H", "--", module.path],
                cwd: repo, timeout: 30)
            out[module.id] = result.ok
                ? result.out.split(separator: "\n").filter { !$0.isEmpty }.count
                : 0
        }
        #endif
        return out
    }

    /// 组装风险排序（高风险在前）
    public static func risks(
        model: ArchModel, churn: [String: Int], testedModuleIDs: Set<String>
    ) -> [ModuleRisk] {
        model.modules.map { module in
            ModuleRisk(
                moduleID: module.id,
                name: module.name,
                layerID: module.layerID,
                lines: module.lineCount,
                fileCount: module.fileCount,
                churn: churn[module.id] ?? 0,
                fanIn: model.fanIn(module.id),
                fanOut: model.fanOut(module.id),
                hasTests: testedModuleIDs.contains(module.id))
        }
        .sorted { ($1.risk, $0.name) < ($0.risk, $1.name) }
    }

    /// 从「模块有测试覆盖」这条参考约束的违例反推出哪些模块有测试
    public static func testedModuleIDs(model: ArchModel) -> Set<String> {
        let untestedPaths = Set(
            model.invariants
                .first { $0.id == "kit-modules-tested" }?
                .violations.map(\.file) ?? [])
        return Set(model.modules.filter { !untestedPaths.contains($0.path) }.map(\.id))
    }
}
