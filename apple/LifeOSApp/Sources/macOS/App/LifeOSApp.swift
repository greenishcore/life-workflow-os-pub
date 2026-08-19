import SwiftUI
import LifeWorkflowKit

@main
struct LifeOSApp: App {
    @State private var state = AppState()

    init() {
        // `--snapshot <dir>` 时渲染完页面就退出，不进入正常交互流程
        Snapshot.runIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .frame(minWidth: 1040, minHeight: 680)
                .task { await state.bootstrap() }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建想法") { state.requestNewItem() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("刷新") { Task { await state.reload() } }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                ForEach(Array(Destination.allCases.enumerated()), id: \.element) { index, dest in
                    Button(dest.title) { state.selection = dest }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
        }
    }
}
