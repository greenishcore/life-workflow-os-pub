import SwiftUI
import LifeWorkflowKit

/// 分层依赖图。
///
/// 用确定性的分层布局而不是通用图布局算法：架构本身就是分层的，按层排布既准确又稳定——
/// 力导向布局每次生成的位置都不同，没法用来对比「这次改动让依赖图变成了什么样」。
struct ArchGraph: View {
    let model: ArchModel
    var violatingEdges: Set<String> = []
    @Binding var selected: String?

    @State private var hovered: String?

    private let nodeHeight: CGFloat = 42
    private let bandPadding: CGFloat = 22

    /// 表现层在上、数据层在下，箭头一律向下——一眼能看出有没有反向依赖
    private var bands: [(layer: Layer, modules: [Module])] {
        model.layers.sorted { $0.rank > $1.rank }
            .map { layer -> (Layer, [Module]) in
                let members = model.modules
                    .filter { $0.layerID == layer.id }
                    .sorted { $0.name < $1.name }
                return (layer, members)
            }
            .filter { !$0.1.isEmpty }
    }

    var body: some View {
        GeometryReader { geo in
            let frames = layout(in: geo.size)
            Canvas { ctx, size in
                drawBands(ctx, size: size)
                drawEdges(ctx, frames: frames)
                drawNodes(ctx, frames: frames)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hovered = frames.first { $0.value.contains(p) }?.key
                case .ended: hovered = nil
                }
            }
            .onTapGesture { selected = hovered }
            .help(hovered.flatMap(tooltip) ?? "悬停查看模块详情，点击可固定")
        }
        .frame(height: CGFloat(max(1, bands.count)) * (nodeHeight + bandPadding * 2) + 8)
    }

    private func layout(in size: CGSize) -> [String: CGRect] {
        var frames: [String: CGRect] = [:]
        let bandHeight = nodeHeight + bandPadding * 2
        for (row, band) in bands.enumerated() {
            let count = max(1, band.modules.count)
            let usable = max(120, size.width - 100)
            let slot = usable / CGFloat(count)
            let width = min(slot - 10, 150)
            for (i, module) in band.modules.enumerated() {
                frames[module.id] = CGRect(
                    x: 88 + slot * CGFloat(i) + (slot - width) / 2,
                    y: CGFloat(row) * bandHeight + bandPadding,
                    width: max(60, width), height: nodeHeight)
            }
        }
        return frames
    }

    private func drawBands(_ ctx: GraphicsContext, size: CGSize) {
        let bandHeight = nodeHeight + bandPadding * 2
        for (row, band) in bands.enumerated() {
            let rect = CGRect(x: 0, y: CGFloat(row) * bandHeight, width: size.width, height: bandHeight)
            if row % 2 == 0 {
                ctx.fill(Path(roundedRect: rect.insetBy(dx: 2, dy: 3), cornerRadius: 8),
                         with: .color(Color.primary.opacity(0.035)))
            }
            ctx.draw(Text(band.layer.name).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.faint),
                     at: CGPoint(x: 12, y: rect.midY), anchor: .leading)
        }
    }

    private func drawEdges(_ ctx: GraphicsContext, frames: [String: CGRect]) {
        for edge in model.edges {
            guard let from = frames[edge.from], let to = frames[edge.to] else { continue }
            let isViolation = violatingEdges.contains("\(edge.from)->\(edge.to)")
            let touched = [hovered, selected].contains(edge.from) || [hovered, selected].contains(edge.to)

            let start = CGPoint(x: from.midX, y: from.maxY)
            let end = CGPoint(x: to.midX, y: to.minY)
            var path = Path()
            path.move(to: start)
            path.addCurve(to: end,
                          control1: CGPoint(x: start.x, y: start.y + 18),
                          control2: CGPoint(x: end.x, y: end.y - 18))

            let color: Color = isViolation ? .red : (touched ? Theme.accent : .secondary)
            let opacity: Double = isViolation ? 0.9 : (touched ? 0.85 : 0.16)
            ctx.stroke(path, with: .color(color.opacity(opacity)),
                       lineWidth: isViolation ? 2 : (touched ? 1.8 : 1))

            var arrow = Path()
            arrow.move(to: CGPoint(x: end.x - 4, y: end.y - 6))
            arrow.addLine(to: end)
            arrow.addLine(to: CGPoint(x: end.x + 4, y: end.y - 6))
            ctx.stroke(arrow, with: .color(color.opacity(opacity)), lineWidth: 1.2)
        }
    }

    private func drawNodes(_ ctx: GraphicsContext, frames: [String: CGRect]) {
        for module in model.modules {
            guard let rect = frames[module.id] else { continue }
            let active = hovered == module.id || selected == module.id
            let tint = targetColor(module.target)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 7),
                     with: .color(tint.opacity(active ? 0.3 : 0.14)))
            ctx.stroke(Path(roundedRect: rect, cornerRadius: 7),
                       with: .color(tint.opacity(active ? 1 : 0.55)), lineWidth: active ? 2 : 1)
            ctx.draw(Text(module.name).font(.system(size: 11, weight: .semibold)),
                     at: CGPoint(x: rect.midX, y: rect.midY - 6))
            ctx.draw(Text("\(module.fileCount) 文件 · \(module.lineCount) 行")
                        .font(.system(size: 9)).foregroundStyle(Theme.faint),
                     at: CGPoint(x: rect.midX, y: rect.midY + 8))
        }
    }

    private func targetColor(_ target: String) -> Color {
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

    private func tooltip(_ id: String) -> String? {
        guard let m = model.module(id: id) else { return nil }
        return """
        \(m.name)（\(m.target)）
        \(m.path)
        \(m.fileCount) 文件 · \(m.lineCount) 行
        依赖 \(model.fanOut(id)) 个模块 · 被 \(model.fanIn(id)) 个模块依赖
        """
    }
}
