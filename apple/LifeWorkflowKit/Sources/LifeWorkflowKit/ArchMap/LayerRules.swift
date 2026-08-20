import Foundation

/// 架构地图的「声明部分」：分层、模块归属、数据产物、五阶段闭环。
///
/// 为什么这部分是声明而不是推导：分层与信息流是**设计意图**，代码里推不出来。
/// 但把它写死在这里之后，提取器会拿它和真实代码比对，
/// 代码里冒出未登记的目录会被标为「地图未覆盖」，避免设计意图和实现悄悄脱节。
public enum LayerRules {

    /// 分层。
    ///
    /// 这里只有三层，而不是 `architecture-v2.md` 里写的四层——
    /// 那份文档描述的是 Python 版，「基础层」在 Swift 核心包里不对应任何独立的东西：
    /// `AppConfig` 描述数据在哪、`VaultStore` 读写数据，两者是**同层的邻居**而非上下级
    /// （提取器最初按四层跑，正是它抓出了 Config → Store 这条"违规"边，
    /// 才发现是分层定义写错了，不是代码错了）。
    public static let layers: [Layer] = [
        .init(id: "data", name: "数据层", rank: 0,
              summary: "领域模型、确定性序列化、配置、vault 读写——彼此是邻居，无上下之分"),
        .init(id: "service", name: "服务层", rank: 1,
              summary: "转换/提示词/日志/复盘/技能/归档/同步/架构提取，纯逻辑不碰 UI"),
        .init(id: "presentation", name: "表现层", rank: 2,
              summary: "各端 UI 与 App Intents，只做编排与呈现"),
    ]

    /// 目录组 → (显示名, 层, 所属产物)
    /// 路径以仓库根为起点
    public static let moduleMap: [(prefix: String, id: String, name: String, layer: String, target: String)] = [
        ("apple/LifeWorkflowKit/Sources/LifeWorkflowKit/Config",      "kit.config",     "Config",      "data",         "kit"),
        ("apple/LifeWorkflowKit/Sources/LifeWorkflowKit/Models",      "kit.models",     "Models",      "data",         "kit"),
        ("apple/LifeWorkflowKit/Sources/LifeWorkflowKit/Frontmatter", "kit.frontmatter","Frontmatter", "data",         "kit"),
        ("apple/LifeWorkflowKit/Sources/LifeWorkflowKit/Store",       "kit.store",      "Store",       "data",         "kit"),
        ("apple/LifeWorkflowKit/Sources/LifeWorkflowKit/Stats",       "kit.stats",      "Stats",       "service",      "kit"),
        ("apple/LifeWorkflowKit/Sources/LifeWorkflowKit/Services",    "kit.services",   "Services",    "service",      "kit"),
        ("apple/LifeWorkflowKit/Sources/LifeWorkflowKit/ArchMap",     "kit.archmap",    "ArchMap",     "service",      "kit"),
        ("apple/LifeWorkflowKit/Sources/LifeWorkflowKit/Perf",        "kit.perf",       "Perf",        "service",      "kit"),
        ("apple/LifeWorkflowKit/Sources/archmap-tool",                "kit.tool",       "archmap-tool","service",      "tool"),
        ("apple/LifeOSApp/Sources/Shared/Intents",                    "app.intents",    "Intents",     "presentation", "shared"),
        ("apple/LifeOSApp/Sources/Shared",                            "app.shared",     "Shared",      "presentation", "shared"),
        ("apple/LifeOSApp/Sources/macOS",                             "app.macos",      "macOS UI",    "presentation", "macOS"),
        ("apple/LifeOSApp/Sources/iOS",                               "app.ios",        "iOS UI",      "presentation", "iOS"),
        ("apple/LifeOSApp/Sources/watchOS",                           "app.watchos",    "watchOS UI",  "presentation", "watchOS"),
    ]

    /// 数据产物。`markers` 是判定「谁碰了它」的符号，不是手写死的读写方名单。
    public static let artifacts: [Artifact] = [
        .init(id: "vault", name: "vault（Markdown 事实源）", path: "vault/**.md",
              summary: "想法 / 日记 / 项目，唯一事实源",
              // 只用 VaultStore：VaultRoot 是描述"根在哪"的值类型，
              // AppConfig 也会用它，但那是配置不是读写 vault 内容
              markers: ["VaultStore"]),
        .init(id: "runlog", name: "运行日志", path: "logs/run-log.jsonl",
              summary: "每次操作的成果与过程，复盘的原料",
              markers: ["RunLogService", "runLogJSONL"]),
        .init(id: "skills", name: "技能库", path: "skills/*.md",
              summary: "从复盘提炼出的可复用操作",
              markers: ["SkillsService", "skillsURL"]),
        .init(id: "prompts", name: "提示词库", path: "prompts/01_rewritten/*.md",
              summary: "交互前重写的结构化提示词",
              markers: ["PromptService", "promptsURL"]),
        .init(id: "cache", name: "转换缓存", path: ".cache/*.md",
              summary: "sha256(输入)+转换器版本 为键，避免重复烧算力",
              markers: ["ConvertService", "cacheURL"]),
        .init(id: "conflicts", name: "冲突落败版本", path: "vault/.conflicts/**",
              summary: "iCloud 冲突中落败的版本，永不静默丢弃",
              markers: ["CloudSyncService", "ConflictPolicy"]),
    ]

    /// 五阶段闭环。`artifactIDs` 是声明的，`moduleIDs` 由产物读写方推导。
    public static let stages: [Stage] = [
        .init(id: "capture", name: "捕捉", order: 0,
              summary: "随手记、Apple 提醒/日历导入、快捷指令",
              artifactIDs: ["vault"]),
        .init(id: "organize", name: "整理", order: 1,
              summary: "想法状态机、思路注释、格式转换",
              artifactIDs: ["vault", "cache"]),
        .init(id: "execute", name: "执行", order: 2,
              summary: "提示词重写后交给 agent 执行",
              artifactIDs: ["prompts", "runlog"]),
        .init(id: "review", name: "复盘", order: 3,
              summary: "日志聚合 → 提炼可复用技能",
              artifactIDs: ["runlog", "skills"]),
        .init(id: "archive", name: "归档", order: 4,
              summary: "commit / push / 里程碑发布",
              artifactIDs: ["vault"]),
    ]

    /// 阶段 → 参与模块（由产物读写方无法完全推出，此处补声明）
    public static let stageModules: [String: [String]] = [
        "capture":  ["kit.store", "kit.services", "app.intents"],
        "organize": ["kit.models", "kit.frontmatter", "kit.store", "kit.services"],
        "execute":  ["kit.services"],
        "review":   ["kit.services", "kit.stats"],
        "archive":  ["kit.services"],
    ]

    public static func module(for path: String) -> (id: String, name: String, layer: String, target: String)? {
        // 前缀更长的先匹配（Shared/Intents 要盖过 Shared）
        for entry in moduleMap.sorted(by: { $0.prefix.count > $1.prefix.count })
        where path.hasPrefix(entry.prefix) {
            return (entry.id, entry.name, entry.layer, entry.target)
        }
        return nil
    }

    public static func rank(of layerID: String) -> Int {
        layers.first { $0.id == layerID }?.rank ?? 0
    }
}
