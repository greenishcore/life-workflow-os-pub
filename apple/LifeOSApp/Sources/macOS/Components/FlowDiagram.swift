import SwiftUI
import LifeWorkflowKit

/// 信息流图：五阶段闭环 × 数据产物的读写方向。
///
/// 这是「信息处理流向」那条需求的正面回答——谁产生数据、谁消费数据，
/// 都由扫描代码里的标志符号得出，不是手画上去的。
struct FlowDiagram: View {
    let model: ArchModel
    @State private var hovered: String?

    var body: some View {
        GeometryReader { geo in
            let stages = model.stages.sorted { $0.order < $1.order }
            let artifacts = model.artifacts.sorted { $0.id < $1.id }
            let sf = row(stages.map(\.id), width: geo.size.width, y: 10, height: 34)
            let af = row(artifacts.map(\.id), width: geo.size.width,
                         y: geo.size.height - 42, height: 32)

            Canvas { ctx, _ in
                // 阶段推进
                for (i, stage) in stages.enumerated() where i < stages.count - 1 {
                    guard let a = sf[stage.id], let b = sf[stages[i + 1].id] else { continue }
                    var p = Path()
                    p.move(to: CGPoint(x: a.maxX + 1, y: a.midY))
                    p.addLine(to: CGPoint(x: b.minX - 1, y: b.midY))
                    ctx.stroke(p, with: .color(Theme.accent.opacity(0.45)), lineWidth: 1.5)
                }
                // 阶段 ↔ 产物
                for stage in stages {
                    guard let s = sf[stage.id] else { continue }
                    for aid in stage.artifactIDs {
                        guard let a = af[aid],
                              let artifact = model.artifacts.first(where: { $0.id == aid })
                        else { continue }
                        let writes = !Set(artifact.producers).isDisjoint(with: Set(stage.moduleIDs))
                        let related = hovered == stage.id || hovered == aid
                        var p = Path()
                        p.move(to: CGPoint(x: s.midX, y: s.maxY))
                        p.addLine(to: CGPoint(x: a.midX, y: a.minY))
                        ctx.stroke(p,
                                   with: .color((writes ? Color.orange : Color.secondary)
                                                    .opacity(related ? 0.9 : 0.2)),
                                   style: StrokeStyle(lineWidth: related ? 1.8 : 1,
                                                      dash: writes ? [] : [3, 3]))
                    }
                }
                draw(ctx, items: stages.map { ($0.id, $0.name) }, frames: sf, tint: Theme.accent)
                draw(ctx, items: artifacts.map { ($0.id, $0.name) }, frames: af, tint: .orange)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    hovered = sf.merging(af) { a, _ in a }.first { $0.value.contains(p) }?.key
                case .ended: hovered = nil
                }
            }
            .help(tooltip)
        }
        .frame(height: 180)
    }

    private func row(_ ids: [String], width: CGFloat, y: CGFloat, height: CGFloat) -> [String: CGRect] {
        guard !ids.isEmpty else { return [:] }
        let slot = max(40, (width - 16) / CGFloat(ids.count))
        return Dictionary(uniqueKeysWithValues: ids.enumerated().map { i, id in
            (id, CGRect(x: 8 + slot * CGFloat(i) + 3, y: y, width: slot - 6, height: height))
        })
    }

    private func draw(_ ctx: GraphicsContext, items: [(String, String)],
                      frames: [String: CGRect], tint: Color) {
        for (id, name) in items {
            guard let rect = frames[id] else { continue }
            let active = hovered == id
            ctx.fill(Path(roundedRect: rect, cornerRadius: 6),
                     with: .color(tint.opacity(active ? 0.3 : 0.14)))
            ctx.stroke(Path(roundedRect: rect, cornerRadius: 6),
                       with: .color(tint.opacity(active ? 1 : 0.5)), lineWidth: active ? 1.8 : 1)
            ctx.draw(Text(name).font(.system(size: 10, weight: .medium)),
                     at: CGPoint(x: rect.midX, y: rect.midY))
        }
    }

    private var tooltip: String {
        guard let hovered else { return "橙色实线 = 写入 · 灰色虚线 = 读取" }
        if let s = model.stages.first(where: { $0.id == hovered }) {
            return "\(s.name)：\(s.summary)\n参与模块：\(s.moduleIDs.joined(separator: "、"))"
        }
        if let a = model.artifacts.first(where: { $0.id == hovered }) {
            return """
            \(a.name)  \(a.path)
            \(a.summary)
            写入：\(a.producers.isEmpty ? "—" : a.producers.joined(separator: "、"))
            读取：\(a.consumers.isEmpty ? "—" : a.consumers.joined(separator: "、"))
            """
        }
        return ""
    }
}
