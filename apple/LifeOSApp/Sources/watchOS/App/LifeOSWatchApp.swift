import SwiftUI
import LifeWorkflowKit

/// 手表端入口。
///
/// **定位是只读投影，不是第三个完整端。** 这不是取舍，是平台约束：
/// - `EKEventStore.save(_:commit:)` 在 watchOS 被显式标为不可用，写不了提醒与日程；
/// - 拿不到 iCloud Drive（`ubiquityIdentityToken` 运行时为 nil）；
/// - App Groups 与 CloudKit 都要付费开发者账号。
///
/// **数据怎么来：还没有来。** 免费账号下唯一可用的通道是 WatchConnectivity
/// （`WCSession` / `updateApplicationContext` / `transferFile` 实测都在），
/// 它要求手表应用是 iOS 应用的**伴侣应用**——本 target 因此嵌在 iOS 应用里，
/// 并在 Info.plist 声明了 `WKCompanionAppBundleIdentifier`。
/// 但同步本身尚未实现，现在读的是手表自己容器里的 vault。
///
/// 所以：**界面可以设计，"手表上真能用"这件事还没验证过。**
/// 验证需要真机联调（模拟器上 WatchConnectivity 配对不可靠），而真机需要签名身份。
@main
struct LifeOSWatchApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(state)
                .task { await state.bootstrap() }
        }
    }
}
