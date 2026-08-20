import AppIntents
import LifeWorkflowKit

/// 让「想法」成为快捷指令里可以被引用、被搜索的实体。
///
/// 有了它，用户可以拼出「找到状态是推进中的想法 → 给它加一条思路注释」这类组合流程，
/// 而不只是调用几个孤立的动作。
struct IdeaEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "想法", numericFormat: "\(placeholder: .int) 条想法")

    static let defaultQuery = IdeaQuery()

    let id: String
    let title: String
    let status: String
    let lastActivity: String
    let noteCount: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(status) · \(lastActivity) · \(noteCount) 条思路注释")
    }

    init(_ item: Item) {
        id = item.id
        title = item.title
        status = item.status.label
        lastActivity = item.lastActivity
        noteCount = item.thinkingNotes.count
    }
}

struct IdeaQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [IdeaEntity] {
        let store = await IntentVault.makeStore()
        let items = await store.allItems
        return items.filter { identifiers.contains($0.id) }.map(IdeaEntity.init)
    }

    func entities(matching string: String) async throws -> [IdeaEntity] {
        let store = await IntentVault.makeStore()
        return await store.query(text: string).map(IdeaEntity.init)
    }

    /// 快捷指令里点开列表时默认展示「最近有动静的」
    func suggestedEntities() async throws -> [IdeaEntity] {
        let store = await IntentVault.makeStore()
        let items = await store.allItems
        return items
            .sorted { $0.lastActivity > $1.lastActivity }
            .prefix(10)
            .map(IdeaEntity.init)
    }
}
