import AppIntents
import LifeWorkflowKit

/// 记一条随手记 → vault 的 Inbox。
///
/// `openAppWhenRun = false`：不打开界面直接写文件，这样「嘿 Siri，记一条想法」
/// 才是几秒钟的事。也因此它必须在 App 自己的进程里跑——
/// vault 的访问书签存在 App 的 UserDefaults 里，扩展进程读不到
/// （共享需要 App Group，而 App Group 要付费账号）。
struct CaptureIdeaIntent: AppIntent {
    static let title: LocalizedStringResource = "记一条想法"
    static let description = IntentDescription(
        "把一句话捕获到知识库的 Inbox，稍后再整理成想法。",
        categoryName: "捕捉")
    static let openAppWhenRun = false

    @Parameter(title: "内容", requestValueDialog: "想记点什么？")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("记一条：\(\.$text)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw AppIntentError.emptyText
        }
        let store = await VaultResolver.makeStore()
        let url = try await store.capture(content)
        return .result(dialog: "已记到 \(url.lastPathComponent)")
    }
}

/// 直接建成一条带状态机的想法（而不是躺在 Inbox 里）
struct CreateIdeaIntent: AppIntent {
    static let title: LocalizedStringResource = "新建想法"
    static let description = IntentDescription(
        "创建一条带状态、优先级与思路注释的想法。",
        categoryName: "捕捉")
    static let openAppWhenRun = false

    @Parameter(title: "标题", requestValueDialog: "这条想法叫什么？")
    var title: String

    @Parameter(title: "初始思路", default: "")
    var firstNote: String

    static var parameterSummary: some ParameterSummary {
        Summary("新建想法「\(\.$title)」") { \.$firstNote }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IdeaEntity> & ProvidesDialog {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AppIntentError.emptyText }

        guard var item = IdeaActions.makeIdea(from: name, firstNote: firstNote) else {
            throw AppIntentError.emptyText
        }
        let store = await VaultResolver.makeStore()
        try await store.save(&item)
        return .result(value: IdeaEntity(item), dialog: "已创建想法「\(item.title)」")
    }
}

/// 给某条想法补一条思路注释 —— 这是本系统区别于普通笔记的地方，
/// 让它能被 Siri 直接调用，思维轨迹才可能真的被记下来。
struct AddThinkingNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "补一条思路注释"
    static let description = IntentDescription(
        "给某条想法追加一条带日期的思路注释，记录它如何演进。",
        categoryName: "整理")
    static let openAppWhenRun = false

    @Parameter(title: "想法")
    var idea: IdeaEntity

    @Parameter(title: "思路", requestValueDialog: "想到了什么？")
    var note: String

    static var parameterSummary: some ParameterSummary {
        Summary("给「\(\.$idea)」补一条思路：\(\.$note)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AppIntentError.emptyText }

        let store = await VaultResolver.makeStore()
        guard var item = await store.item(id: idea.id) else {
            throw AppIntentError.ideaNotFound(idea.title)
        }
        item.addThinkingNote(text)
        try await store.save(&item)
        return .result(dialog: "已给「\(item.title)」补上第 \(item.thinkingNotes.count) 条思路注释")
    }
}

/// 推进到下一个状态：seed → sprout → doing → done → archived
struct AdvanceIdeaIntent: AppIntent {
    static let title: LocalizedStringResource = "推进想法状态"
    static let description = IntentDescription(
        "把想法推进到状态机的下一步，并自动留下一条思路注释。",
        categoryName: "整理")
    static let openAppWhenRun = false

    @Parameter(title: "想法")
    var idea: IdeaEntity

    static var parameterSummary: some ParameterSummary {
        Summary("推进「\(\.$idea)」")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = await VaultResolver.makeStore()
        guard var item = await store.item(id: idea.id) else {
            throw AppIntentError.ideaNotFound(idea.title)
        }
        let result = IdeaActions.advance(&item)
        guard result.didAdvance else { return .result(dialog: "\(result.message)") }
        try await store.save(&item)
        return .result(dialog: "\(result.message)")
    }
}

/// 今天该推进什么 —— 抬手就能问的那句话
struct TodayFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "今天该推进什么"
    static let description = IntentDescription(
        "列出正在推进和已发芽的想法，按最近活动排序。",
        categoryName: "查阅")
    static let openAppWhenRun = false

    @Parameter(title: "最多几条", default: 3, inclusiveRange: (1, 10))
    var limit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("今天该推进什么（前 \(\.$limit) 条）")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[IdeaEntity]> & ProvidesDialog {
        let store = await VaultResolver.makeStore()
        let focus = IdeaActions.todayFocus(await store.allItems, limit: limit)

        guard !focus.isEmpty else {
            return .result(value: [], dialog: "今天没有待推进的想法")
        }
        let names = focus.map(\.title).joined(separator: "、")
        return .result(value: focus.map(IdeaEntity.init),
                       dialog: "\(focus.count) 条待推进：\(names)")
    }
}

enum AppIntentError: Error, CustomLocalizedStringResourceConvertible {
    case emptyText
    case ideaNotFound(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .emptyText: "内容不能为空"
        case .ideaNotFound(let title): "找不到想法「\(title)」，它可能已被删除或归档"
        }
    }
}
