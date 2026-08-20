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
        .task { if state.archModel == nil { await state.loadArchMap() } }
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
                            Text(inv.rationale).font(.system(size: 11))
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
