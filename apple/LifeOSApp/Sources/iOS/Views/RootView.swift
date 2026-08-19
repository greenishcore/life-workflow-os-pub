import SwiftUI
import LifeWorkflowKit

/// iOS 用底部标签栏而不是侧边栏：
/// 手机是「随身捕捉 + 查阅」的场景，五阶段闭环那套侧边分组在小屏上是负担。
struct RootView: View {
    @Environment(AppState.self) private var state
    @State private var tab: Tab = Tab.launchArgument ?? .today

    enum Tab: String, CaseIterable {
        case today, capture, ideas, dashboard, settings

        /// `--tab ideas` 指定初始标签页。
        /// 用途是自动化验证截图——模拟器里没有输入注入时无法手动切页。
        static var launchArgument: Tab? {
            let args = CommandLine.arguments
            guard let i = args.firstIndex(of: "--tab"), i + 1 < args.count else { return nil }
            return Tab(rawValue: args[i + 1])
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("今日", systemImage: "sun.max") }.tag(Tab.today)
            CaptureView()
                .tabItem { Label("捕捉", systemImage: "square.and.pencil") }.tag(Tab.capture)
            IdeasView()
                .tabItem { Label("想法", systemImage: "lightbulb") }.tag(Tab.ideas)
            DashboardView()
                .tabItem { Label("看板", systemImage: "chart.dots.scatter") }.tag(Tab.dashboard)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }.tag(Tab.settings)
        }
        .overlay(alignment: .bottom) {
            if !state.statusMessage.isEmpty {
                Text(state.statusMessage)
                    .font(.footnote)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 60)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: state.statusMessage)
    }
}
