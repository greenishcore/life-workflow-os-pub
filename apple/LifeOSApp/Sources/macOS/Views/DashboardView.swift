import Charts
import SwiftUI
import LifeWorkflowKit

struct DashboardView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        PageScaffold(destination: .dashboard,
                     subtitleOverride: "\(Destination.dashboard.subtitle) · 共 \(state.items.count) 条记录") {
            Button {
                Task { await state.reload() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
        } content: {
            kpis
            heatmapCard
            timelineCard
            HStack(alignment: .top, spacing: Theme.gap) {
                statusCard.frame(maxWidth: .infinity)
                tagCard.frame(maxWidth: .infinity)
            }
            trajectoryCard
        }
    }

    // MARK: KPI

    private var kpis: some View {
        let s = state.summary
        let completion = s.total == 0 ? 0 : Double(s.done) / Double(s.total) * 100
        let perItem = s.total == 0 ? 0 : Double(s.totalNotes) / Double(s.total)
        return HStack(spacing: Theme.gap) {
            StatTile(label: "想法总数", value: "\(s.total)", delta: "跨度 \(s.spanDays) 天")
            StatTile(label: "推进中", value: "\(s.active)",
                     delta: "平均进度 \(Int(s.averageProgress))%", color: Status.doing.color)
            StatTile(label: "已完成", value: "\(s.done)",
                     delta: "完成率 \(Int(completion))%", color: Status.done.color)
            StatTile(label: "思路注释", value: "\(s.totalNotes)",
                     delta: String(format: "人均 %.1f 条/想法", perItem), color: Theme.accent)
            StatTile(label: "连续活跃", value: "\(s.streak)",
                     delta: s.streak > 0 ? "天" : "今天还没记录", color: .orange)
        }
    }

    // MARK: 热力图

    private var heatmapCard: some View {
        Card(title: "活跃热力图", hint: "每格 = 当天新建想法 + 写下的思路注释") {
            HeatmapCalendar(data: Stats.activityHeat(state.items)) { day in
                let n = Stats.activityHeat(state.items)[day] ?? 0
                state.notify("\(day)：\(n) 次活动")
            }
        }
    }

    // MARK: 融合时间轴

    private var timelineCard: some View {
        Card(title: "融合时间轴",
             hint: "X=时间 · Y=精力 · 点径=优先级 · 颜色=状态 · 横线=思维轨迹") {
            if state.items.isEmpty {
                EmptyStateView(symbol: "chart.dots.scatter", title: "还没有带「精力/状态」的想法",
                               hint: "去「快速捕获」写下第一条")
                    .frame(height: 200)
            } else {
                Chart {
                    ForEach(Stats.lifelines(state.items)) { line in
                        if line.hasSpan,
                           let begin = DateOnly.date(from: line.begin),
                           let end = DateOnly.date(from: line.end) {
                            // 生命线：从「想法产生」延伸到最后一次思路演进
                            RuleMark(xStart: .value("起", begin),
                                     xEnd: .value("止", end),
                                     y: .value("精力", line.energy))
                                .foregroundStyle(line.status.color.opacity(0.38))
                                .lineStyle(.init(lineWidth: 2.5, lineCap: .round))
                        }
                        // 思路演进的刻度
                        ForEach(line.ticks, id: \.self) { tick in
                            if let d = DateOnly.date(from: tick) {
                                PointMark(x: .value("时间", d), y: .value("精力", line.energy))
                                    .symbol(.square)
                                    .symbolSize(22)
                                    .foregroundStyle(line.status.color.opacity(0.75))
                            }
                        }
                        // 起点
                        if let begin = DateOnly.date(from: line.begin) {
                            PointMark(x: .value("时间", begin), y: .value("精力", line.energy))
                                .symbolSize(Double(line.priority.weight) * 9)
                                .foregroundStyle(line.status.color)
                                .annotation(position: .top, spacing: 2) {
                                    if line.priority == .high {
                                        Text(line.title)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                        }
                    }
                }
                .chartYScale(domain: 0...10)
                .chartYAxis {
                    AxisMarks(values: [0, 2, 4, 6, 8, 10]) {
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartXAxis { AxisMarks(preset: .aligned) }
                .frame(height: 230)

                HStack(spacing: 14) {
                    ForEach(Status.allCases, id: \.self) { s in
                        HStack(spacing: 4) {
                            Circle().fill(s.color).frame(width: 7, height: 7)
                            Text(s.label).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: 状态分布

    private var statusCard: some View {
        Card(title: "状态分布", hint: "seed → sprout → doing → done → archived") {
            let counts = Stats.statusCounts(state.items)
            Chart(Status.allCases, id: \.self) { s in
                BarMark(x: .value("状态", s.label),
                        y: .value("数量", counts[s] ?? 0))
                    .foregroundStyle(s.color)
                    .cornerRadius(4)
                    .annotation(position: .top) {
                        Text("\(counts[s] ?? 0)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(counts[s] ?? 0 > 0 ? .primary : Theme.faint)
                    }
            }
            .chartYAxis(.hidden)
            .frame(height: 150)
        }
    }

    // MARK: 标签

    private var tagCard: some View {
        Card(title: "标签 TopN") {
            let tags = Stats.tagCounts(state.items, top: 8)
            if tags.isEmpty {
                Text("还没有打标签").font(.system(size: 12)).foregroundStyle(Theme.faint)
                    .frame(height: 150)
            } else {
                Chart(tags, id: \.tag) { entry in
                    BarMark(x: .value("次数", entry.count),
                            y: .value("标签", entry.tag))
                        .foregroundStyle(Theme.accent)
                        .cornerRadius(3)
                        .annotation(position: .trailing, spacing: 4) {
                            Text("\(entry.count)").font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    // 标签放左侧轴上，否则会压在条形上
                    AxisMarks(position: .leading) { AxisValueLabel() }
                }
                .chartPlotStyle { $0.padding(.trailing, 18) }
                .frame(height: max(150, CGFloat(tags.count) * 22))
            }
        }
    }

    // MARK: 思维轨迹

    private var trajectoryCard: some View {
        Card(title: "最近的思维轨迹", hint: "点击可跳到对应想法") {
            let rows = Stats.trajectory(state.items).prefix(8)
            if rows.isEmpty {
                Text("还没有思路注释。打开一个想法，把「为什么想到它、想法怎么变的」记下来。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { Divider() }
                        Button {
                            state.open(row.item)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text(row.date)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.faint)
                                    .frame(width: 74, alignment: .leading)
                                Circle().fill(row.item.status.color)
                                    .frame(width: 7, height: 7).padding(.top, 5)
                                Text(row.item.title)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 120, alignment: .leading)
                                    .lineLimit(1)
                                Text(row.note)
                                    .font(.system(size: 12))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
