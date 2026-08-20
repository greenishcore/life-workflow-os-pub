import Foundation
import Testing
@testable import LifeWorkflowKit

/// 两套实现（Swift 应用 / Python 命令行）写同一个配置文件，字段名却是两套：
/// Swift 用 `roots` / `logsPath`…，Python 用 `vault_dir` / `logs_dir`…。
///
/// 曾经谁都读不懂对方，`load()` 只会静默退回默认值——**正是「命令行改的 vault
/// 和应用里看到的不一样」这个本来要防的毛病**。这组测试把互通钉住。
@Suite("配置互通")
struct ConfigInteropTests {

    /// Python 版 `Config.save()` 实际写出来的形状（字段名逐字照抄）
    static let pythonShaped = """
    {
      "vault_dir": "/tmp/py-vault",
      "logs_dir": "/tmp/py-logs",
      "prompts_dir": "/tmp/py-prompts",
      "cache_dir": "/tmp/py-cache",
      "scripts_dir": "/tmp/py-scripts",
      "skills_dir": "/tmp/py-skills",
      "theme": "dark",
      "default_calendar": "工作",
      "default_reminder_list": "待办",
      "openai_base_url": "https://example.com/v1",
      "openai_model": "gpt-4o"
    }
    """

    @Test("能读懂 Python 写的配置")
    func readsPythonConfig() throws {
        let cfg = try JSONDecoder().decode(AppConfig.self, from: Data(Self.pythonShaped.utf8))
        #expect(cfg.roots.count == 1, "Python 只表达得了单个 vault")
        #expect(cfg.roots.first?.path == "/tmp/py-vault")
        #expect(cfg.logsPath == "/tmp/py-logs")
        #expect(cfg.skillsPath == "/tmp/py-skills")
        #expect(cfg.theme == "dark")
        #expect(cfg.defaultCalendar == "工作")
        #expect(cfg.openAIModel == "gpt-4o")
    }

    @Test("写出来的配置带上 Python 认识的字段")
    func writesPythonReadableKeys() throws {
        let cfg = AppConfig(roots: [.init(id: "icloud", path: "/tmp/v", displayName: "iCloud")],
                            logsPath: "/tmp/l", skillsPath: "/tmp/s", theme: "dark")
        let data = try JSONEncoder().encode(cfg)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // 自己的富字段
        #expect(json["roots"] != nil)
        // 给 Python 看的那一份
        #expect(json["vault_dir"] as? String == "/tmp/v")
        #expect(json["logs_dir"] as? String == "/tmp/l")
        #expect(json["skills_dir"] as? String == "/tmp/s")
        #expect(json["default_calendar"] as? String == "个人")
    }

    @Test("roots 比 vault_dir 优先——它能表达复合 vault，后者不能")
    func rootsWinOverVaultDir() throws {
        let mixed = """
        {"roots":[{"id":"a","path":"/tmp/a","folders":[],"needsCoordination":false,"displayName":"A"},
                  {"id":"b","path":"/tmp/b","folders":[],"needsCoordination":false,"displayName":"B"}],
         "vault_dir":"/tmp/single"}
        """
        let cfg = try JSONDecoder().decode(AppConfig.self, from: Data(mixed.utf8))
        #expect(cfg.roots.map(\.path) == ["/tmp/a", "/tmp/b"])
    }

    @Test("空文件不崩，退回空 roots 让上层去补默认值")
    func emptyObjectIsTolerated() throws {
        let cfg = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        #expect(cfg.roots.isEmpty)
        #expect(cfg.theme == "system")
        #expect(cfg.defaultReminderList == "提醒事项")
    }

    @Test("自己写的自己读得回来")
    func swiftRoundTrips() throws {
        let cfg = AppConfig(roots: [.init(id: "x", path: "/tmp/v", displayName: "V")], theme: "dark")
        let back = try JSONDecoder().decode(AppConfig.self, from: try JSONEncoder().encode(cfg))
        #expect(back == cfg)
    }
}
