import AppIntents

/// 预置快捷指令短语。
///
/// 这些短语在 App 安装后自动出现在「快捷指令」App 与 Siri 里，
/// 用户不必自己拼流程就能用上——这是 iOS 上替代「读 Apple 便签」的实际入口。
struct LifeOSShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .orange

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureIdeaIntent(),
            phrases: [
                "用 \(.applicationName) 记一条",
                "在 \(.applicationName) 里记一条想法",
                "\(.applicationName) 捕获",
            ],
            shortTitle: "记一条",
            systemImageName: "square.and.pencil")

        AppShortcut(
            intent: TodayFocusIntent(),
            phrases: [
                "\(.applicationName) 今天该推进什么",
                "问 \(.applicationName) 今天做什么",
            ],
            shortTitle: "今天该推进什么",
            systemImageName: "sun.max")

        AppShortcut(
            intent: CreateIdeaIntent(),
            phrases: [
                "用 \(.applicationName) 新建想法",
                "在 \(.applicationName) 里创建想法",
            ],
            shortTitle: "新建想法",
            systemImageName: "lightbulb")

        AppShortcut(
            intent: AddThinkingNoteIntent(),
            phrases: [
                "用 \(.applicationName) 补一条思路",
                "给 \(.applicationName) 的想法加注释",
            ],
            shortTitle: "补一条思路注释",
            systemImageName: "text.quote")

        AppShortcut(
            intent: AdvanceIdeaIntent(),
            phrases: [
                "用 \(.applicationName) 推进想法",
            ],
            shortTitle: "推进想法状态",
            systemImageName: "arrow.right.circle")
    }
}
