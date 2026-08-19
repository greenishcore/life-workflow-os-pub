import Foundation
#if canImport(EventKit)
import EventKit
#endif

/// 提醒事项 / 日历 → Markdown 的桥。
///
/// **平台差异是硬约束，不是权限问题**：
/// watchOS 上 EventKit 的 10 个写入 API（`saveReminder` / `saveEvent` / `removeReminder`
/// / `saveCalendar` / `commit` …）被标记为 `__WATCHOS_PROHIBITED`，编译期就不可用。
/// 所以写入能力用 `#if !os(watchOS)` 隔离——手表上根本看不到这些方法，
/// 而不是运行时才失败。手表的写入意图必须走队列，由 iPhone/Mac 代为执行。
public struct EventKitBridge: Sendable {

    public enum Access: Sendable {
        case granted
        case denied
        case unavailable(String)
    }

    public struct ReminderItem: Sendable, Hashable {
        public let title: String
        public let isCompleted: Bool
        public let dueDate: String?
        public let notes: String?
    }

    public struct EventItem: Sendable, Hashable {
        public let title: String
        public let start: Date
        public let end: Date
        public let location: String?
    }

    public init() {}

    /// 手表上是否可写。写死为编译期常量，调用方据此隐藏 UI 而不是等失败。
    public static var canWriteEventKit: Bool {
        #if os(watchOS)
        false
        #else
        true
        #endif
    }

    #if canImport(EventKit)

    // MARK: 权限

    public func requestRemindersAccess() async -> Access {
        let store = EKEventStore()
        do {
            let ok = try await store.requestFullAccessToReminders()
            return ok ? .granted : .denied
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    public func requestCalendarAccess() async -> Access {
        let store = EKEventStore()
        do {
            let ok = try await store.requestFullAccessToEvents()
            return ok ? .granted : .denied
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    // MARK: 读（三端都可用）

    /// 读取某个列表的提醒；`listName` 为空则读全部。
    public func reminders(listName: String = "", includeCompleted: Bool = false) async -> [ReminderItem] {
        let store = EKEventStore()
        let calendars = store.calendars(for: .reminder).filter {
            listName.isEmpty || $0.title == listName
        }
        guard !calendars.isEmpty else { return [] }

        let predicate = store.predicateForReminders(in: calendars)
        // 必须在回调内部就把 EKReminder 转成自己的值类型：
        // EKReminder 不是 Sendable，让它跨越 continuation 的隔离边界在 Swift 6 下是编译错误。
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { fetched in
                let items = (fetched ?? [])
                    .filter { includeCompleted || !$0.isCompleted }
                    .map { r in
                        ReminderItem(
                            title: r.title ?? "",
                            isCompleted: r.isCompleted,
                            dueDate: r.dueDateComponents.flatMap {
                                Calendar.current.date(from: $0).map(DateOnly.string(from:))
                            },
                            notes: r.notes
                        )
                    }
                continuation.resume(returning: items)
            }
        }
    }

    /// 读取未来 N 天的日历事件
    public func events(calendarName: String = "", days: Int = 7) async -> [EventItem] {
        let store = EKEventStore()
        let calendars = store.calendars(for: .event).filter {
            calendarName.isEmpty || $0.title == calendarName
        }
        guard !calendars.isEmpty else { return [] }

        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: calendars)
        return store.events(matching: predicate).map {
            EventItem(title: $0.title ?? "", start: $0.startDate, end: $0.endDate,
                      location: $0.location?.isEmpty == false ? $0.location : nil)
        }
    }

    // MARK: 写（watchOS 上不存在这些方法）

    #if !os(watchOS)
    /// 新建一条提醒。watchOS 上此方法**不存在**（EventKit 禁写）。
    public func addReminder(title: String, listName: String = "", due: Date? = nil) async throws {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = store.calendars(for: .reminder).first { $0.title == listName }
            ?? store.defaultCalendarForNewReminders()
        if let due {
            reminder.dueDateComponents = Calendar.current
                .dateComponents([.year, .month, .day, .hour, .minute], from: due)
        }
        try store.save(reminder, commit: true)
    }
    #endif

    #endif   // canImport(EventKit)

    // MARK: Markdown 渲染（纯函数，无平台依赖，可单测）

    public static func markdown(for reminders: [ReminderItem]) -> String {
        guard !reminders.isEmpty else { return "" }
        return reminders.map { r in
            var line = r.isCompleted ? "- [x] \(r.title)" : "- [ ] \(r.title)"
            if let due = r.dueDate { line += " 📅 \(due)" }
            if let notes = r.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                line += "\n  - \(notes.replacingOccurrences(of: "\n", with: " "))"
            }
            return line
        }.joined(separator: "\n")
    }

    public static func markdown(for events: [EventItem]) -> String {
        guard !events.isEmpty else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm"
        return events
            .sorted { $0.start < $1.start }
            .map { e in
                var line = "- \(f.string(from: e.start)) → \(f.string(from: e.end)) | \(e.title)"
                if let loc = e.location { line += " @ \(loc)" }
                return line
            }
            .joined(separator: "\n")
    }
}
