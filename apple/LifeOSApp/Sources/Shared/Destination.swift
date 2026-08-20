import Foundation

/// 侧边栏导航项，按「捕捉 → 整理 → 执行 → 复盘 → 归档」五阶段闭环分组。
enum Destination: String, CaseIterable, Identifiable, Hashable {
    case dashboard, archmap, capture, ideas, convert, prompts, logs, archive, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "看板"
        case .archmap:   "架构地图"
        case .capture:   "快速捕获"
        case .ideas:     "想法库"
        case .convert:   "格式转换"
        case .prompts:   "提示词工作台"
        case .logs:      "运行日志与复盘"
        case .archive:   "版本归档"
        case .settings:  "设置"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: "融合时间 · 精力 · 优先级 · 状态 · 思维轨迹"
        case .archmap:   "模块依赖 · 信息流向 · 架构约束 · 改动风险"
        case .capture:   "想到什么先记下来，之后再整理成想法"
        case .ideas:     "想法是一等公民：时间 · 状态 · 优先级 · 标签 · 思路注释"
        case .convert:   "任意格式 → Markdown（带缓存）→ PDF / Word / HTML"
        case .prompts:   "口语需求 → 五段式提示词文档 → 版本化留档"
        case .logs:      "每次 agent 操作留痕 → 聚合成可沉淀的复盘"
        case .archive:   "阶段成果 commit / push，里程碑 tag + release"
        case .settings:  "知识库位置、外观、Apple 默认值、依赖体检"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "chart.dots.scatter"
        case .archmap:   "square.stack.3d.up"
        case .capture:   "square.and.pencil"
        case .ideas:     "lightbulb"
        case .convert:   "arrow.left.arrow.right"
        case .prompts:   "text.append"
        case .logs:      "clock.arrow.circlepath"
        case .archive:   "shippingbox"
        case .settings:  "gearshape"
        }
    }

    var group: NavGroup {
        switch self {
        case .dashboard, .archmap: .overview
        case .capture:   .capture
        case .ideas, .convert: .organize
        case .prompts:   .execute
        case .logs:      .review
        case .archive:   .archive
        case .settings:  .system
        }
    }
}

enum NavGroup: String, CaseIterable, Identifiable, Hashable {
    case overview, capture, organize, execute, review, archive, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "总览"
        case .capture:  "捕捉"
        case .organize: "整理"
        case .execute:  "执行"
        case .review:   "复盘"
        case .archive:  "归档"
        case .system:   ""
        }
    }

    var destinations: [Destination] {
        Destination.allCases.filter { $0.group == self }
    }
}
