import SwiftUI
import LifeWorkflowKit

/// 架构地图：模块依赖、信息流向、架构约束、改动风险。
///
/// 结构来自入库的 `docs/02-architecture/archmap.json`（CI 会随代码变动重新生成），
/// 变更频率等指标打开页面时用 git 现算——那类数据每次提交都变，入库只会制造噪音。
struct ArchMapView: View {
    @Environment(AppState.self) private var state
    @Environment(\.isSnapshotting) private var isSnapshotting

    @State private var selectedModule: String?

    private var model: ArchModel? { state.archModel }

    var body: some View {
        PageScaffold(destination: .archmap,
                     subtitleOverride: subtitle) {
            Button {
                Task { await state.loadArchMap(recomputeFromSource: true) }
            } label: {
                Label("从源码重算", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(state.isLoadingArch)
            .help("不读入库的 JSON，直接扫描源码——改完代码想立刻看到效果时用")
        } content: {
            if let error = state.archError {
                Card(title: "无法加载架构地图") {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12)).foregroundStyle(.orange)
                }
            } else if let model {
                kpis(model)
                invariantsCard(model)
                benchmarkCard
                robustnessCard(model)
                runtimeCard
                graphCard(model)
                flowCard(model)
                riskCard
                if let detail = selectedModule.flatMap({ model.module(id: $0) }) {
                    moduleDetail(detail, model: model)
                }
            } else {
                Card(title: "架构地图") {
                    HStack {
                        if state.isLoadingArch { ProgressView().controlSize(.small) }
                        Text(state.isLoadingArch ? "正在扫描源码…" : "尚未加载")
                            .font(.system(size: 12)).foregroundStyle(Theme.faint)
                    }
                }
            }
        }
        .task {
            if state.archModel == nil { await state.loadArchMap() }
            await state.loadPerformance()
        }
    }

    private var subtitle: String {
        guard let model else { return Destination.archmap.subtitle }
        let files = model.modules.reduce(0) { $0 + $1.fileCount }
        return "\(Destination.archmap.subtitle) · \(model.modules.count) 模块 / \(files) 源文件"
    }

    // MARK: KPI

    private func kpis(_ model: ArchModel) -> some View {
        let blocking = model.invariants.filter { $0.severity == .blocking }
        let failed = blocking.filter { !$0.passed }.count
        return HStack(spacing: Theme.gap) {
            StatTile(label: "模块", value: "\(model.modules.count)",
                     delta: "\(model.layers.count) 层")
            StatTile(label: "依赖边", value: "\(model.edges.count)",
                     delta: "按类型引用判定")
            StatTile(label: "硬约束", value: "\(blocking.count - failed)/\(blocking.count)",
                     delta: failed == 0
                        ? "通过 · 另有 \(model.invariants.count - blocking.count) 条参考项"
                        : "\(failed) 条被违反",
                     color: failed == 0 ? .green : .red)
            StatTile(label: "代码量",
                     value: "\(model.modules.reduce(0) { $0 + $1.lineCount })",
                     delta: "行（不含注释空行）", color: Theme.accent)
        }
    }

    // MARK: 约束

    private func invariantsCard(_ model: ArchModel) -> some View {
        Card(title: "架构约束校验",
             hint: "只有硬约束会让 CI 失败；参考项照样检查、照样显示，但不阻断") {
            VStack(spacing: 0) {
                ForEach(Array(model.invariants.enumerated()), id: \.element.id) { index, inv in
                    if index > 0 { Divider() }
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: inv.passed ? "checkmark.circle.fill"
                                : (inv.severity == .blocking ? "xmark.octagon.fill"
                                                             : "exclamationmark.triangle.fill"))
                            .foregroundStyle(inv.passed ? .green
                                             : (inv.severity == .blocking ? .red : .orange))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(inv.title).font(.system(size: 13, weight: .semibold))
                                Badge(text: inv.severity.label,
                                      color: inv.severity == .blocking ? .red : .orange)
                            }
                            // 理由里带 **加粗**，用 Markdown 渲染，否则星号会原样显示
                            Text(.init(inv.rationale)).font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(Array(inv.violations.enumerated()), id: \.offset) { _, v in
                                Text("· \(v.file)\(v.line > 0 ? ":\(v.line)" : "")  \(v.detail)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(inv.severity == .blocking ? .red : .orange)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 7)
                }
            }
        }
    }

    // MARK: 图

    private func graphCard(_ model: ArchModel) -> some View {
        Card(title: "分层依赖图",
             hint: "上层依赖下层，箭头一律向下；反向依赖标红。悬停看详情，点击固定") {
            ArchGraph(model: model,
                      violatingEdges: violatingEdgeKeys(model),
                      selected: $selectedModule)
            HStack(spacing: 14) {
                // 按「共享程度」排，不用字典序
                ForEach([("kit", "共享核心包"), ("shared", "跨端共享 UI"),
                         ("macOS", "macOS 专属"), ("iOS", "iOS 专属"),
                         ("tool", "命令行工具")], id: \.0) { key, label in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(legendColor(key)).frame(width: 9, height: 9)
                        Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private func flowCard(_ model: ArchModel) -> some View {
        Card(title: "信息流向",
             hint: "捕捉 → 整理 → 执行 → 复盘 → 归档，以及每一环读写哪些数据产物") {
            FlowDiagram(model: model)
        }
    }

    // MARK: 效率与稳健性

    private var benchmarkCard: some View {
        Card(title: "热路径基准",
             hint: "预算按实测基线定；结果记入 logs/bench.jsonl，Debug 与 Release 分开算趋势") {
            if state.benchmarks.isEmpty {
                HStack {
                    Text("还没跑过基准。点右边跑一次，约 1 秒。")
                        .font(.system(size: 12)).foregroundStyle(Theme.faint)
                    Spacer()
                    runBenchButton
                }
            } else {
                ForEach(state.benchmarks) { result in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Image(systemName: result.overBudget
                                  ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(result.overBudget ? .orange : .green)
                            Text(result.name).font(.system(size: 12, weight: .semibold))
                            Badge(text: stageName(result.stage), color: Theme.accent)
                            Spacer()
                            Text(String(format: "%.3f %@", result.value, result.unit))
                                .font(.system(size: 12, design: .monospaced))
                            Text(String(format: "预算 %.2f", result.budget))
                                .font(.system(size: 10)).foregroundStyle(Theme.faint)
                        }
                        // 预算占比条
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2).fill(Theme.border)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(result.overBudget ? Color.orange : Theme.accent)
                                    .frame(width: geo.size.width * min(1, result.ratio))
                            }
                        }
                        .frame(height: 4)
                        Text(result.detail).font(.system(size: 10)).foregroundStyle(Theme.faint)
                    }
                    .padding(.vertical, 5)
                    Divider()
                }
                HStack {
                    if let last = state.benchHistory.first {
                        Text("上次：\(last.timestamp.prefix(16).replacingOccurrences(of: "T", with: " ")) · \(last.configuration) 构建 · 共 \(state.benchHistory.count) 次记录")
                            .font(.system(size: 10)).foregroundStyle(Theme.faint)
                    }
                    Spacer()
                    runBenchButton
                }
            }
        }
    }

    private var runBenchButton: some View {
        HStack(spacing: 6) {
            if state.isBenchmarking { ProgressView().controlSize(.small) }
            Button("跑一次基准") { Task { await state.runBenchmarks() } }
                .disabled(state.isBenchmarking)
        }
    }

    private func robustnessCard(_ model: ArchModel) -> some View {
        let ranked = model.modules
            .filter { $0.robustness.silencedErrors > 0 || $0.robustness.crashRisks > 0 }
            .sorted { $0.silencedPer100Lines > $1.silencedPer100Lines }
        return Card(title: "稳健性热点",
                    hint: "try? 不一定是坏事——目录已存在就忽略是合理的；它是「错误在哪被静默吞掉」的信号，值得看一眼") {
            if ranked.isEmpty {
                Text("没有静默吞错，也没有崩溃风险写法。")
                    .font(.system(size: 12)).foregroundStyle(Theme.faint)
            } else {
                ForEach(ranked) { module in
                    HStack(spacing: 10) {
                        Text(module.name).font(.system(size: 12, weight: .semibold))
                            .frame(width: 90, alignment: .leading)
                        Text("\(module.lineCount) 行").font(.system(size: 10))
                            .foregroundStyle(Theme.faint).frame(width: 56, alignment: .trailing)
                        Text("try? \(module.robustness.silencedErrors)")
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 62, alignment: .leading)
                        Text(String(format: "%.1f/百行", module.silencedPer100Lines))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(module.silencedPer100Lines >= 2 ? .orange : .secondary)
                            .frame(width: 76, alignment: .leading)
                        if module.robustness.crashRisks > 0 {
                            Badge(text: "崩溃风险 \(module.robustness.crashRisks)", color: .red)
                        }
                        Spacer()
                        Text("throws \(module.robustness.throwingFunctions) · catch \(module.robustness.catchBlocks)")
                            .font(.system(size: 10)).foregroundStyle(Theme.faint)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var runtimeCard: some View {
        Card(title: "运行时表现",
             hint: "来自 logs/run-log.jsonl 的真实操作，近 30 天；样本少时分位数意义有限") {
            if state.runtimeOps.isEmpty {
                Text("近 30 天还没有运行日志。做一次格式转换或版本归档，系统会自动留痕。")
                    .font(.system(size: 12)).foregroundStyle(Theme.faint)
            } else {
                ForEach(state.runtimeOps) { op in
                    HStack(spacing: 10) {
                        Text(op.kind).font(.system(size: 12, weight: .semibold))
                            .frame(width: 100, alignment: .leading)
                        Text("\(op.count) 次").font(.system(size: 11))
                            .foregroundStyle(Theme.faint).frame(width: 50, alignment: .leading)
                        Text(String(format: "成功 %.0f%%", op.successRate * 100))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(op.successRate < 1 ? .orange : .secondary)
                            .frame(width: 76, alignment: .leading)
                        Text(String(format: "P50 %.0fms · P95 %.0fms", op.p50, op.p95))
                            .font(.system(size: 11, design: .monospaced))
                        if let hit = op.cacheHitRate {
                            Badge(text: String(format: "缓存命中 %.0f%%", hit * 100),
                                  color: hit >= 0.5 ? .green : .orange)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func stageName(_ id: String) -> String {
        model?.stages.first { $0.id == id }?.name ?? id
    }

    // MARK: 决策支持

    private var riskCard: some View {
        Card(title: "改动风险排序",
             hint: "风险 = 近期改动次数 × 被依赖数 ÷（有测试则减半）。排在前面的，改之前先补测试") {
            if state.archRisks.isEmpty {
                Text("正在统计变更频率…（需要 git）")
                    .font(.system(size: 12)).foregroundStyle(Theme.faint)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(state.archRisks.prefix(isSnapshotting ? 6 : 20).enumerated()),
                            id: \.element.id) { index, risk in
                        if index > 0 { Divider() }
                        HStack(spacing: 10) {
                            Text("\(index + 1)").font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.faint).frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(risk.name).font(.system(size: 12, weight: .semibold))
                                Text(risk.explanation).font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if !risk.hasTests {
                                Badge(text: "无测试", color: .orange)
                            }
                            Text("\(risk.lines) 行").font(.system(size: 11))
                                .foregroundStyle(Theme.faint)
                            Text(String(format: "%.0f", risk.risk))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(risk.risk >= 20 ? .red
                                                 : (risk.risk >= 8 ? .orange : .secondary))
                                .frame(width: 36, alignment: .trailing)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
    }

    // MARK: 模块详情

    private func moduleDetail(_ module: Module, model: ArchModel) -> some View {
        Card(title: "模块详情 · \(module.name)",
             hint: module.path) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("依赖（\(model.fanOut(module.id))）")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(model.edges.filter { $0.from == module.id }, id: \.to) { edge in
                        Text("→ \(model.module(id: edge.to)?.name ?? edge.to)")
                            .font(.system(size: 11))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("被依赖（\(model.fanIn(module.id))）")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(model.edges.filter { $0.to == module.id }, id: \.from) { edge in
                        Text("← \(model.module(id: edge.from)?.name ?? edge.from)")
                            .font(.system(size: 11))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("文件（\(module.fileCount)）")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(module.files.prefix(12)) { file in
                        Text("\((file.path as NSString).lastPathComponent) · \(file.lines) 行")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.faint)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack {
                Spacer()
                Button("取消选中") { selectedModule = nil }.controlSize(.small)
                if let repo = state.archRepo {
                    Button("在访达中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [repo.appendingPathComponent(module.path)])
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: 辅助

    /// 违反「依赖只能向下」的边，用于在图上标红
    private func violatingEdgeKeys(_ model: ArchModel) -> Set<String> {
        var keys = Set<String>()
        for edge in model.edges {
            guard let from = model.module(id: edge.from),
                  let to = model.module(id: edge.to) else { continue }
            let fromRank = model.layers.first { $0.id == from.layerID }?.rank ?? 0
            let toRank = model.layers.first { $0.id == to.layerID }?.rank ?? 0
            if fromRank < toRank { keys.insert("\(edge.from)->\(edge.to)") }
        }
        return keys
    }

    private func legendColor(_ target: String) -> Color {
        switch target {
        // kit 用 accent（蓝），macOS 必须换掉 .blue —— 两者视觉上几乎一样，
        // 图上分不出「共享核心包」和「macOS 专属」就失去了意义
        case "kit": Theme.accent
        case "shared": .purple
        case "macOS": .teal
        case "iOS": .green
        default: .gray
        }
    }
}
