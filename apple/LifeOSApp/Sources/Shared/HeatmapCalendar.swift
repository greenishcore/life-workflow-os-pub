import SwiftUI
import LifeWorkflowKit

/// 活跃热力图（GitHub 贡献图风格）。
///
/// 用 Canvas 手绘而不是 Swift Charts：日历热力图是「周×星期」的二维网格，
/// 不是 Charts 擅长的连续坐标系，硬套反而更啰嗦且难控制格子尺寸。
struct HeatmapCalendar: View {
    let data: [String: Int]
    var onSelect: ((String) -> Void)?

    @State private var hovered: String?

    private let cell: CGFloat = 12
    private let gap: CGFloat = 3
    private let leftPad: CGFloat = 24
    private let topPad: CGFloat = 18

    private var step: CGFloat { cell + gap }

    /// 色阶：0 = 无活动
    private func color(_ v: Int, max vmax: Int) -> Color {
        guard v > 0 else { return Theme.border.opacity(0.35) }
        let ratio = Double(v) / Double(Swift.max(vmax, 1))
        return Theme.accent.opacity(0.28 + 0.72 * min(1, ratio))
    }

    var body: some View {
        GeometryReader { geo in
            let weeks = Swift.max(4, Int((geo.size.width - leftPad) / step))
            let grid = Self.grid(weeks: weeks)
            let vmax = data.values.max() ?? 1

            Canvas { ctx, _ in
                // 星期标签（一 / 三 / 五 / 日）
                for (i, label) in ["一", "", "三", "", "五", "", "日"].enumerated() where !label.isEmpty {
                    ctx.draw(
                        Text(label).font(Theme.Typo.axis).foregroundStyle(Theme.faint),
                        at: CGPoint(x: leftPad - 8, y: topPad + CGFloat(i) * step + cell / 2),
                        anchor: .trailing)
                }
                // 月份标签：与上一个至少隔 3 周才画，避免挤在一起
                var lastMonth = -1
                var lastLabelWeek = -99
                for (w, column) in grid.enumerated() {
                    guard let first = column.first else { continue }
                    let month = Calendar.current.component(.month, from: first)
                    if month != lastMonth, w - lastLabelWeek >= 3 {
                        lastMonth = month
                        lastLabelWeek = w
                        ctx.draw(
                            Text("\(month)月").font(Theme.Typo.axis).foregroundStyle(Theme.faint),
                            at: CGPoint(x: leftPad + CGFloat(w) * step, y: 8), anchor: .leading)
                    }
                }
                // 格子
                let today = DateOnly.today()
                for (w, column) in grid.enumerated() {
                    for (d, day) in column.enumerated() {
                        let key = DateOnly.string(from: day)
                        guard key <= today else { continue }
                        let rect = CGRect(x: leftPad + CGFloat(w) * step,
                                          y: topPad + CGFloat(d) * step,
                                          width: cell, height: cell)
                        let path = Path(roundedRect: rect, cornerRadius: 2.5)
                        ctx.fill(path, with: .color(color(data[key] ?? 0, max: vmax)))
                        if key == today {
                            ctx.stroke(Path(roundedRect: rect.insetBy(dx: -1, dy: -1),
                                            cornerRadius: 3.5),
                                       with: .color(Theme.accent), lineWidth: 1)
                        }
                        if key == hovered {
                            ctx.stroke(path, with: .color(.primary), lineWidth: 1.5)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            // 悬停在 watchOS 上不存在（onContinuousHover 显式不可用），
            // 手表也没有指针，格子靠点击选中就够了
            #if !os(watchOS)
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hovered = Self.day(at: point, grid: grid,
                                       leftPad: leftPad, topPad: topPad, step: step, cell: cell)
                case .ended:
                    hovered = nil
                }
            }
            .help(hovered.map { "\($0)：\(data[$0] ?? 0) 次活动" } ?? "")
            #endif
            .onTapGesture { if let hovered { onSelect?(hovered) } }
        }
        .frame(height: topPad + 7 * (cell + gap) + 6)
    }

    /// 生成 weeks 列 × 7 行的日期网格，最后一列是本周
    private static func grid(weeks: Int) -> [[Date]] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2   // 周一起始
        let today = Date()
        let weekdayIndex = (cal.component(.weekday, from: today) + 5) % 7   // 一=0 … 日=6
        guard let end = cal.date(byAdding: .day, value: 6 - weekdayIndex, to: today),
              let start = cal.date(byAdding: .day, value: -(weeks * 7 - 1), to: end)
        else { return [] }

        return (0..<weeks).map { w in
            (0..<7).compactMap { d in
                cal.date(byAdding: .day, value: w * 7 + d, to: start)
            }
        }
    }

    private static func day(
        at point: CGPoint, grid: [[Date]],
        leftPad: CGFloat, topPad: CGFloat, step: CGFloat, cell: CGFloat
    ) -> String? {
        let w = Int((point.x - leftPad) / step)
        let d = Int((point.y - topPad) / step)
        guard w >= 0, w < grid.count, d >= 0, d < 7 else { return nil }
        // 落在格子间隙里不算命中
        guard (point.x - leftPad).truncatingRemainder(dividingBy: step) <= cell,
              (point.y - topPad).truncatingRemainder(dividingBy: step) <= cell else { return nil }
        return DateOnly.string(from: grid[w][d])
    }
}
