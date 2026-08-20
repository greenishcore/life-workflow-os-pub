import Foundation
import LifeWorkflowKit

/// App Intent 用的 vault 解析入口。
///
/// 两端的 vault 来源不同，这是唯一需要分平台的地方：
/// · iOS —— 用户在文档选择器里选的目录，授权存在书签里；
/// · macOS —— 配置文件里的复合多根（可能同时有 iCloud 根与本地根）。
///
/// Intent 跑在没有界面的上下文里，不能依赖 AppState 这类 @MainActor 观察对象，
/// 所以每次自己建一个一次性 store。
enum IntentVault {
    static func makeStore() async -> VaultStore {
        #if os(iOS)
        return await VaultResolver.makeStore()
        #else
        return VaultStore(roots: AppConfig.load().vaultRoots)
        #endif
    }

    static func config() -> AppConfig {
        AppConfig.load()
    }
}
