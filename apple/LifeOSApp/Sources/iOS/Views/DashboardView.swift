import Charts
import SwiftUI
import LifeWorkflowKit

struct DashboardView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.gap) {
                    kpis
                    heatmap
                    timeline
                    statusChart
                    tags
                }
                .padding()
            }
            .background(Theme.pageBackground)
            .navigationTitle("看板")
            .refreshable { await state.reload() }
        }
    }

    private var kpis: some View {
        let s = state.summary
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.gap) {
            StatTile(label: "想法总数", value: "\(s.total)", delta: "跨度 \(s.spanDays) 天")
            StatTile(label: "推进中", value: "\(s.active)",
                     delta: "平均进度 \(Int(s.averageProgress))%", color: Status.doing.color)
            StatTile(label: "思路注释", value: "\(s.totalNotes)",
                     delta: String(format: "人均 %.1f 条", s.total == 0 ? 0 : Double(s.totalNotes) / Double(s.total)),
                     color: Theme.accent)
            StatTile(label: "连续活跃", value: "\(s.streak)",
                     delta: s.streak > 0 ? "天" : "今天还没记录", color: .orange)
        }
    }

    private var heatmap: some View {
        Card(title: "活跃热力图", hint: "新建想法 + 写下的思路注释") {
            HeatmapCalendar(data: Stats.activityHeat(state.items))
        }
    }

    private var timeline: some View {
        Card(title: "融合时间轴", hint: "Y=精力 · 点径=优先级 · 颜色=状态 · 横线=思维轨迹") {
            if state.items.isEmpty {
                Text("还没有数据").font(.caption).foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart {
                    ForEach(Stats.lifelines(state.items)) { line in
                        if line.hasSpan,
                           let begin = DateOnly.date(from: line.begin),
                           let end = DateOnly.date(from: line.end) {
                            RuleMark(xStart: .value("起", begin), xEnd: .value("止", end),
                                     y: .value("精力", line.energy))
                                .foregroundStyle(line.status.color.opacity(0.38))
                                .lineStyle(.init(lineWidth: 2.5, lineCap: .round))
                        }
                        ForEach(line.ticks, id: \.self) { tick in
                            if let d = DateOnly.date(from: tick) {
                                PointMark(x: .value("时间", d), y: .value("精力", line.energy))
                                    .symbol(.square).symbolSize(18)
                                    .foregroundStyle(line.status.color.opacity(0.75))
                            }
                        }
                        if let begin = DateOnly.date(from: line.begin) {
                            PointMark(x: .value("时间", begin), y: .value("精力", line.energy))
                                .symbolSize(Double(line.priority.weight) * 7)
                                .foregroundStyle(line.status.color)
                        }
                    }
                }
                .chartYScale(domain: 0...10)
                .frame(height: 200)
            }
        }
    }

    private var statusChart: some View {
        Card(title: "状态分布") {
            let counts = Stats.statusCounts(state.items)
            Chart(Status.allCases, id: \.self) { s in
                BarMark(x: .value("状态", s.label), y: .value("数量", counts[s] ?? 0))
                    .foregroundStyle(s.color).cornerRadius(4)
                    .annotation(position: .top) {
                        Text("\(counts[s] ?? 0)").font(.caption2)
                    }
            }
            .chartYAxis(.hidden)
            .frame(height: 140)
        }
    }

    private var tags: some View {
        Card(title: "标签 TopN") {
            let entries = Stats.tagCounts(state.items, top: 8)
            if entries.isEmpty {
                Text("还没有打标签").font(.caption).foregroundStyle(Theme.faint)
            } else {
                Chart(entries, id: \.tag) { entry in
                    BarMark(x: .value("次数", entry.count), y: .value("标签", entry.tag))
                        .foregroundStyle(Theme.accent).cornerRadius(3)
                }
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel() } }
                .frame(height: max(120, CGFloat(entries.count) * 22))
            }
        }
    }
}
