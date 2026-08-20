import Charts
import SwiftUI
import LifeWorkflowKit

struct LogsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.isSnapshotting) private var isSnapshotting

    @State private var rangeDays = 7

    // 手动记一条
    @State private var objective = ""
    @State private var status: RunLog.Status = .success
    @State private var tools = ""
    @State private var outputs = ""
    @State private var errors = ""
    @State private var notes = ""
    @State private var model = ""
    @State private var duration = 0.0

    private let ranges: [(String, Int)] = [("最近 7 天", 7), ("最近 14 天", 14),
                                           ("最近 30 天", 30), ("全部", 3650)]

    var body: some View {
        PageScaffold(destination: .logs) {
            Picker("", selection: $rangeDays) {
                ForEach(ranges, id: \.1) { Text($0.0).tag($0.1) }
            }
            .labelsHidden()
            .frame(width: 120)

            Button("生成周复盘报告") { Task { await state.writeReviewReport() } }
                .buttonStyle(.borderedProminent)
                .disabled(state.reviewStats.total == 0)
        } content: {
            kpis
            charts
            proposalsCard
            skillsCard
            addCard
            tableCard
        }
        .task(id: rangeDays) { await state.refreshReview(days: rangeDays) }
    }

    private var kpis: some View {
        HStack(spacing: Theme.gap) {
            StatTile(label: "运行次数", value: "\(state.reviewStats.total)", delta: "\(state.reviewStats.since) 起")
            StatTile(label: "成功率", value: "\(Int(state.reviewStats.rate))%",
                     delta: "成功 \(state.reviewStats.success)", color: RunLog.Status.success.color)
            StatTile(label: "失败/部分", value: "\(state.reviewStats.failed)",
                     delta: "失败 + 部分成功", color: RunLog.Status.failed.color)
            StatTile(label: "总耗时", value: "\(Int(state.reviewStats.duration))s",
                     delta: state.reviewStats.total == 0 ? "—"
                        : String(format: "平均 %.1fs/次", state.reviewStats.duration / Double(state.reviewStats.total)),
                     color: Theme.accent)
        }
    }

    private var charts: some View {
        HStack(alignment: .top, spacing: Theme.gap) {
            Card(title: "状态分布") {
                if state.reviewStats.total == 0 {
                    emptyChart
                } else {
                    Chart(RunLog.Status.allCases, id: \.self) { s in
                        BarMark(x: .value("状态", s.label),
                                y: .value("次数", state.reviewStats.byStatus[s] ?? 0))
                            .foregroundStyle(s.color)
                            .cornerRadius(4)
                            .annotation(position: .top) {
                                Text("\(state.reviewStats.byStatus[s] ?? 0)").font(Theme.Typo.micro)
                            }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 140)
                }
            }
            Card(title: "工具使用 TopN") {
                rankChart(state.reviewStats.tools.map { ($0.name, $0.count) }, color: Theme.accent)
            }
            Card(title: "错误 TopN", hint: "高频错误 = 该沉淀成 skill 的信号") {
                rankChart(state.reviewStats.errors.map { ($0.message, $0.count) }, color: .red)
            }
        }
    }

    private var emptyChart: some View {
        Text("暂无数据").font(Theme.Typo.list).foregroundStyle(Theme.faint)
            .frame(maxWidth: .infinity, minHeight: 140)
    }

    @ViewBuilder
    private func rankChart(_ entries: [(String, Int)], color: Color) -> some View {
        if entries.isEmpty {
            emptyChart
        } else {
            Chart(entries, id: \.0) { entry in
                BarMark(x: .value("次数", entry.1), y: .value("项", entry.0))
                    .foregroundStyle(color)
                    .cornerRadius(3)
                    .annotation(position: .trailing, spacing: 4) {
                        Text("\(entry.1)").font(Theme.Typo.micro).foregroundStyle(.secondary)
                    }
            }
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel() } }
            .chartPlotStyle { $0.padding(.trailing, 18) }
            .frame(height: max(140, CGFloat(entries.count) * 24))
        }
    }

    private var addCard: some View {
        Card(title: "记一次操作", hint: "跑完一次 agent 任务后，把过程与产出记下来") {
            HStack(spacing: 8) {
                TextField("这次做了什么（必填）", text: $objective)
                Picker("", selection: $status) {
                    ForEach(RunLog.Status.allCases, id: \.self) { Text($0.label).tag($0) }
                }.labelsHidden().frame(width: 80)
                TextField("秒", value: $duration, format: .number).frame(width: 60)
            }
            HStack(spacing: 8) {
                TextField("用到的工具，逗号分隔", text: $tools)
                TextField("产出路径，逗号分隔", text: $outputs)
                TextField("错误，逗号分隔", text: $errors)
            }
            HStack(spacing: 8) {
                TextField("复盘备注：下次怎么做更好", text: $notes)
                TextField("模型", text: $model).frame(width: 140)
                Button("记录") { Task { await addLog() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(objective.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var tableCard: some View {
        Card(title: "运行日志", hint: "数据源 logs/run-log.jsonl") {
            if state.reviewLogs.isEmpty {
                EmptyStateView(symbol: "clock", title: "这段时间还没有日志",
                               hint: "用上面的表单记一条，或用命令行 lifeos log")
                    .frame(height: 130)
            } else if isSnapshotting {
                VStack(spacing: 0) {
                    ForEach(state.reviewLogs.prefix(6)) { LogRow(log: $0) }
                }
            } else {
                Table(state.reviewLogs) {
                    TableColumn("时间") { Text($0.timestamp.replacingOccurrences(of: "T", with: " ")) }
                        .width(160)
                    TableColumn("状态") { log in
                        Text("\(log.status.icon) \(log.status.label)").foregroundStyle(log.status.color)
                    }.width(70)
                    TableColumn("目标", value: \.objective)
                    TableColumn("工具") { Text($0.toolsUsed.joined(separator: ", ")) }.width(140)
                    TableColumn("耗时") { Text($0.durationSeconds == 0 ? "" : "\(Int($0.durationSeconds))s") }
                        .width(60)
                    TableColumn("产出 / 错误") { log in
                        Text(log.outputs.isEmpty ? log.errors.joined(separator: "; ")
                                                 : log.outputs.joined(separator: ", "))
                    }
                }
                .frame(minHeight: 240)
            }
        }
    }

    // MARK: 技能演进（主线 4）

    private var proposalsCard: some View {
        Card(title: "本期可沉淀",
             hint: "从运行日志算出来的：重复的坑该有对策，稳定的流程该被固化") {
            if state.proposals.isEmpty {
                Text(state.reviewLogs.isEmpty
                     ? "还没有运行日志。用一次格式转换或版本归档，系统会自动留痕，这里就有料可算了。"
                     : "本期没有值得沉淀的模式——错误没有重复，流程也没有稳定复现。")
                    .font(Theme.Typo.list).foregroundStyle(Theme.faint)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(state.proposals.enumerated()), id: \.element.id) { index, p in
                        if index > 0 { Divider() }
                        HStack(alignment: .top, spacing: 10) {
                            Badge(text: p.kind.label,
                                  color: p.kind.isActionable ? Theme.accent : .orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.title).font(Theme.Typo.cardTitle)
                                Text(p.rationale).font(Theme.Typo.hint)
                                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                ForEach(p.evidence, id: \.self) { e in
                                    Text(e).font(Theme.Typo.monoSmall)
                                        .foregroundStyle(Theme.faint)
                                }
                            }
                            Spacer(minLength: 8)
                            if p.kind.isActionable {
                                Button("采纳") { Task { await state.adopt(p) } }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 7)
                    }
                }
            }
        }
    }

    private var skillsCard: some View {
        Card(title: "技能库", hint: "已验证的可复用操作；用过一次就点「记一次」，闲置太久会被提醒") {
            if state.skills.isEmpty {
                Text("技能库是空的。上面有可沉淀的提议时点「采纳」，或手动往 skills/ 里加。")
                    .font(Theme.Typo.list).foregroundStyle(Theme.faint)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(state.skills.enumerated()), id: \.element.id) { index, skill in
                        if index > 0 { Divider() }
                        HStack(spacing: 10) {
                            Badge(text: skill.status.label, color: Color(hex: skill.status.colorHex))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name).font(Theme.Typo.cardTitle)
                                if !skill.trigger.isEmpty {
                                    Text(skill.trigger).font(Theme.Typo.hint)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            Text(skill.uses == 0 ? "未用过" : "用过 \(skill.uses) 次")
                                .font(Theme.Typo.hint).foregroundStyle(Theme.faint)
                            if skill.isStale() {
                                Image(systemName: "clock.badge.exclamationmark")
                                    .foregroundStyle(.orange)
                                    .help("长期没用过")
                            }
                            Button("记一次") { Task { await state.recordSkillUse(skill) } }
                                .controlSize(.small)
                            if let url = skill.url {
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                } label: {
                                    Image(systemName: "folder")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    // MARK: 动作

    // 这一页只做布局与表单：日志聚合、落盘、生成复盘都在 AppState，
    // 这样界面设计交接出去之后，改排版碰不到业务逻辑。

    private func addLog() async {
        func split(_ s: String) -> [String] {
            s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        let log = RunLog(objective: objective.trimmingCharacters(in: .whitespaces),
                         toolsUsed: split(tools), outputs: split(outputs),
                         status: status, errors: split(errors),
                         durationSeconds: duration, model: model, notes: notes)
        if await state.appendRunLog(log, refreshingDays: rangeDays) {
            objective = ""; tools = ""; outputs = ""; errors = ""; notes = ""; model = ""
            duration = 0
        }
    }
}

private struct LogRow: View {
    let log: RunLog

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(log.status.icon)
            Text(log.timestamp.prefix(16).replacingOccurrences(of: "T", with: " "))
                .font(Theme.Typo.mono).foregroundStyle(Theme.faint)
                .frame(width: 120, alignment: .leading)
            Text(log.objective).font(Theme.Typo.list)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(log.toolsUsed.joined(separator: ", "))
                .font(Theme.Typo.hint).foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}
