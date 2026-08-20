import Foundation
import Testing
@testable import LifeWorkflowKit

@Suite("源码扫描")
struct SourceScannerTests {

    @Test("提取 import、行数与顶层公开类型")
    func basics() {
        let file = SourceScanner.scan(text: """
        import Foundation
        import SwiftUI

        public struct Widget {
            public enum Status { case a }
        }
        public actor Machine {}
        """, path: "a.swift")

        #expect(file.imports == ["Foundation", "SwiftUI"])
        #expect(file.publicTypes == ["Machine", "Widget"], "嵌套的 Status 不该被登记")
        #expect(file.lines == 6)
    }

    // 这条是踩过的坑：本仓库注释里大量出现 Process / SwiftUI，
    // 不剥注释会把说明文字判成违例
    @Test("注释里的内容不算数")
    func commentsIgnored() {
        let file = SourceScanner.scan(text: """
        // 这里说明为什么用 Process 而不是别的
        /* import SwiftUI 只是举例 */
        import Foundation
        """, path: "a.swift")
        #expect(file.imports == ["Foundation"])
        #expect(file.guardedSymbols.isEmpty)
    }

    // 同样是踩过的坑：watchedSymbols = ["Process("] 这行会自我命中
    @Test("字符串字面量里的符号不算数")
    func stringLiteralsIgnored() {
        let file = SourceScanner.scan(text: """
        import Foundation
        let watched = ["Process(", "NSWorkspace"]
        """, path: "a.swift")
        #expect(file.guardedSymbols.isEmpty)
    }

    @Test("记录条件编译区间与其中的符号")
    func platformGates() throws {
        let file = SourceScanner.scan(text: """
        import Foundation
        #if os(macOS)
        let p = Process()
        #endif
        #if !os(watchOS)
        let x = 1
        #endif
        """, path: "a.swift")

        #expect(Set(file.platformGates) == ["macOS", "watchOS"])
        let symbol = try #require(file.guardedSymbols.first { $0.symbol == "Process" })
        #expect(symbol.insideGate == "os(macOS)")
    }

    @Test("未被条件编译包住的符号，insideGate 为 nil")
    func ungatedSymbol() throws {
        let file = SourceScanner.scan(text: """
        import Foundation
        let p = Process()
        """, path: "a.swift")
        let symbol = try #require(file.guardedSymbols.first)
        #expect(symbol.insideGate == nil)
        #expect(symbol.line == 2)
    }

    @Test("#else 会把条件取反")
    func elseBranch() throws {
        let file = SourceScanner.scan(text: """
        #if os(iOS)
        let a = 1
        #else
        let p = Process()
        #endif
        """, path: "a.swift")
        let symbol = try #require(file.guardedSymbols.first)
        #expect(symbol.insideGate == "!(os(iOS))")
    }
}

@Suite("架构提取与约束校验")
struct ArchExtractorTests {

    @Test("模块归属按最长前缀匹配（Shared/Intents 要盖过 Shared）")
    func longestPrefixWins() throws {
        let intents = try #require(LayerRules.module(
            for: "apple/LifeOSApp/Sources/Shared/Intents/CaptureIntents.swift"))
        #expect(intents.id == "app.intents")
        let shared = try #require(LayerRules.module(
            for: "apple/LifeOSApp/Sources/Shared/AppState.swift"))
        #expect(shared.id == "app.shared")
    }

    @Test("词边界匹配：Item 不该命中 ItemType")
    func identifierBoundary() {
        #expect(ArchExtractor.containsIdentifier("let x: Item = y", "Item"))
        #expect(!ArchExtractor.containsIdentifier("let x: ItemType = y", "Item"))
        #expect(!ArchExtractor.containsIdentifier("MyItem", "Item"))
        #expect(ArchExtractor.containsIdentifier("[Item]", "Item"))
        #expect(!ArchExtractor.containsIdentifier("", "Item"))
    }

    // MARK: 真实仓库

    static let repo = repoRoot

    @Test("在真实仓库上提取出的规模与实际吻合")
    func realRepoShape() throws {
        let result = try ArchExtractor.extract(repoRoot: Self.repo)
        let model = result.model
        #expect(model.modules.count >= 10, "实际 \(model.modules.count) 个模块")
        #expect(!model.edges.isEmpty)
        #expect(model.artifacts.count == LayerRules.artifacts.count)
        #expect(model.stages.count == 5, "五阶段闭环")
        #expect(model.modules.allSatisfy { !$0.files.isEmpty }, "空模块不该进图")
    }

    // 这条把「哪几条是硬门禁」这个决定固定下来。
    //
    // 判据始终是同一条：**编译器管得了的，不设门禁**。
    // 降级的三条里两条编译器/构建系统已经保证（iOS 无 Process、macOS 与 iOS 是不同
    // target），一条基于本仓库自己声明的分层模型、误报过一次。
    //
    // 后加的两条 ui-* 是硬门禁，因为编译器一条也管不了：写死字号编得过、
    // 视图里跑 git 也编得过，代价要等到界面设计交接出去之后才显现。
    // 间距那条是参考项，它的作用是给接手方列规范化清单，不是拦人。
    //
    // 想增删硬门禁请连同理由一起改，别无声地改回去。
    @Test("硬门禁只有编译器管不了的那几条")
    func blockingInvariantsAreDeliberate() throws {
        let model = try ArchExtractor.extract(repoRoot: Self.repo).model
        let blocking = Set(model.invariants.filter { $0.severity == .blocking }.map(\.id))
        #expect(blocking == ["kit-no-ui", "ui-typography-tokens", "ui-no-services"],
                "硬约束实际是 \(blocking.sorted())")
        let advisory = Set(model.invariants.filter { $0.severity == .advisory }.map(\.id))
        #expect(advisory == ["downward-only", "ui-targets-isolated", "subprocess-macos-only",
                             "kit-modules-tested", "ui-spacing-tokens"])
    }

    // MARK: 界面交接护栏

    @Test("视图里写死字号会被抓到，令牌定义处不会")
    func typographyGuard() throws {
        let view = SourceScanner.scan(
            text: "Text(\"x\").font(.system(size: 11))",
            path: "apple/LifeOSApp/Sources/macOS/Views/FakeView.swift")
        let token = SourceScanner.scan(
            text: "static let hint = Font.system(size: 11)",
            path: "apple/LifeOSApp/Sources/Shared/Theme.swift")
        let rule = try #require(ArchExtractor.uiHandoffInvariants(scanned: [
            (view, "Text(x).font(.system(size: 11))", nil),
            (token, "static let hint = Font.system(size: 11)", nil),
        ]).first { $0.id == "ui-typography-tokens" })
        #expect(rule.severity == .blocking)
        #expect(rule.violations.count == 1, "只该抓视图那处，令牌定义要放行")
        #expect(rule.violations.first?.file.contains("FakeView") == true)
    }

    @Test("Service 后跟小写是调用要拦，跟大写是嵌套类型要放行")
    func serviceGuardDistinguishesTypesFromCalls() throws {
        let path = "apple/LifeOSApp/Sources/macOS/Views/FakeView.swift"
        let file = SourceScanner.scan(text: "x", path: path)
        let rule = try #require(ArchExtractor.uiHandoffInvariants(scanned: [
            (file, "let t: ConvertService.Target = .pdf", nil),          // 类型，放行
            (file, "await GitService.status(repo: url)", nil),           // 调用，拦
            (file, "if PromptService.llmAvailable {", nil),              // 属性，拦
            (file, "let b = EventKitBridge()", nil),                     // 实例化，拦
        ]).first { $0.id == "ui-no-services" })
        #expect(rule.severity == .blocking)
        #expect(rule.violations.count == 3, "实际：\(rule.violations.map(\.detail))")
        #expect(rule.violations.allSatisfy { !$0.detail.contains("Target") })
    }

    @Test("间距只报不在档位上的，且是参考项不阻断")
    func spacingGuardOnlyReportsOffScale() throws {
        let path = "apple/LifeOSApp/Sources/macOS/Views/FakeView.swift"
        let file = SourceScanner.scan(text: "x", path: path)
        let rule = try #require(ArchExtractor.uiHandoffInvariants(scanned: [
            (file, ".padding(8)", nil),                 // 在档位上，不报
            (file, ".padding(.horizontal, 7)", nil),    // 不在档位上，报
            (file, "VStack(spacing: 3) {", nil),        // 不在档位上，报
            (file, ".padding(Theme.pad)", nil),         // 用了令牌，不报
        ]).first { $0.id == "ui-spacing-tokens" })
        #expect(rule.severity == .advisory, "这条是清单不是门禁")
        #expect(rule.violations.count == 2, "实际：\(rule.violations.map(\.detail))")
    }

    @Test("护栏只管视图与绘图组件，AppState 调服务是本职")
    func guardsScopedToDesignSurface() throws {
        let appState = SourceScanner.scan(
            text: "x", path: "apple/LifeOSApp/Sources/Shared/AppState.swift")
        let rules = ArchExtractor.uiHandoffInvariants(scanned: [
            (appState, "await GitService.status(repo: url)\n.font(.system(size: 11))", nil),
        ])
        #expect(rules.allSatisfy { $0.violations.isEmpty },
                "AppState 不该被这三条管到")
    }

    @Test("降级的约束仍然在算、仍然会显示，只是不阻断")
    func advisoryStillEvaluated() throws {
        let model = try ArchExtractor.extract(repoRoot: Self.repo).model
        // 注入一条反向依赖，确认参考项照样报出来
        let modules = [
            "low": Module(id: "low", name: "Low", path: "a", layerID: "data", target: "kit",
                          files: [SourceFile(path: "a/x.swift", lines: 1)]),
            "high": Module(id: "high", name: "High", path: "b", layerID: "presentation",
                           target: "macOS", files: [SourceFile(path: "b/y.swift", lines: 1)]),
        ]
        let rule = try #require(ArchExtractor
            .checkInvariants(modules: modules, edges: [Edge(from: "low", to: "high")], scanned: [])
            .first { $0.id == "downward-only" })
        #expect(rule.violations.count == 1, "降级不等于不检查")
        #expect(rule.severity == .advisory)
        _ = model
    }

    @Test("真实仓库当前零硬约束违例")
    func realRepoHasNoBlockingViolations() throws {
        let model = try ArchExtractor.extract(repoRoot: Self.repo).model
        let blocking = model.invariants
            .filter { $0.severity == .blocking }
            .flatMap(\.violations)
        #expect(blocking.isEmpty, "存在硬约束违例：\(blocking.map(\.detail))")
    }

    @Test("地图覆盖了所有源码目录，没有漏登记的")
    func noUncoveredPaths() throws {
        let result = try ArchExtractor.extract(repoRoot: Self.repo)
        #expect(result.uncoveredPaths.isEmpty,
                "这些目录 LayerRules 里没登记：\(result.uncoveredPaths)")
    }

    @Test("两次提取逐字节相同（确定性，CI 才不会反复提交）")
    func deterministic() throws {
        let a = try ArchExtractor.extract(repoRoot: Self.repo).model.encoded()
        let b = try ArchExtractor.extract(repoRoot: Self.repo).model.encoded()
        #expect(a == b)
    }

    @Test("JSON 里不含时间戳一类每次都变的东西")
    func noVolatileFields() throws {
        let data = try ArchExtractor.extract(repoRoot: Self.repo).model.encoded()
        let text = try #require(String(data: data, encoding: .utf8))
        for token in ["generatedAt", "timestamp", "churn", "20260"] {
            #expect(!text.contains(token), "JSON 不该含易变字段：\(token)")
        }
    }

    @Test("编码后能原样解回来")
    func roundTrip() throws {
        let model = try ArchExtractor.extract(repoRoot: Self.repo).model
        let back = try ArchModel.decode(from: model.encoded())
        #expect(back == model)
    }

    // MARK: 违例检测（注入假模块）

    @Test("注入 import SwiftUI 的核心包文件能被抓到")
    func detectsUIImportInKit() {
        let scanned = [(
            file: SourceScanner.scan(text: "import SwiftUI\npublic struct X {}",
                                     path: "apple/LifeWorkflowKit/Sources/LifeWorkflowKit/Models/Bad.swift"),
            code: "import SwiftUI",
            moduleID: Optional("kit.models"))]
        let invariants = ArchExtractor.checkInvariants(modules: [:], edges: [], scanned: scanned)
        let rule = invariants.first { $0.id == "kit-no-ui" }
        #expect(rule?.violations.count == 1)
        #expect(rule?.violations.first?.detail.contains("SwiftUI") == true)
        #expect(rule?.severity == .blocking)
    }

    @Test("反向依赖能被抓到")
    func detectsUpwardDependency() {
        let modules = [
            "low": Module(id: "low", name: "Low", path: "a", layerID: "data", target: "kit",
                          files: [SourceFile(path: "a/x.swift", lines: 1)]),
            "high": Module(id: "high", name: "High", path: "b", layerID: "presentation",
                           target: "macOS", files: [SourceFile(path: "b/y.swift", lines: 1)]),
        ]
        let edges = [Edge(from: "low", to: "high", viaFiles: ["a/x.swift"])]
        let rule = ArchExtractor
            .checkInvariants(modules: modules, edges: edges, scanned: [])
            .first { $0.id == "downward-only" }
        #expect(rule?.violations.count == 1)
        #expect(rule?.violations.first?.detail.contains("上层") == true)
    }

    @Test("同层之间互相依赖不算违例")
    func sameLayerIsFine() {
        let modules = [
            "a": Module(id: "a", name: "A", path: "a", layerID: "data", target: "kit",
                        files: [SourceFile(path: "a/x.swift", lines: 1)]),
            "b": Module(id: "b", name: "B", path: "b", layerID: "data", target: "kit",
                        files: [SourceFile(path: "b/y.swift", lines: 1)]),
        ]
        let rule = ArchExtractor
            .checkInvariants(modules: modules, edges: [Edge(from: "a", to: "b")], scanned: [])
            .first { $0.id == "downward-only" }
        #expect(rule?.violations.isEmpty == true)
    }

    @Test("未被条件编译保护的 Process 能被抓到")
    func detectsUngatedProcess() {
        let scanned = [(
            file: SourceScanner.scan(
                text: "import Foundation\nlet p = Process()",
                path: "apple/LifeWorkflowKit/Sources/LifeWorkflowKit/Services/Bad.swift"),
            code: "let p = Process()",
            moduleID: Optional("kit.services"))]
        let rule = ArchExtractor
            .checkInvariants(modules: [:], edges: [], scanned: scanned)
            .first { $0.id == "subprocess-macos-only" }
        #expect(rule?.violations.count == 1)
        #expect(rule?.violations.first?.line == 2)
    }

    @Test("被 #if os(macOS) 包住的 Process 不算违例")
    func gatedProcessIsFine() {
        let scanned = [(
            file: SourceScanner.scan(
                text: "import Foundation\n#if os(macOS)\nlet p = Process()\n#endif",
                path: "apple/LifeWorkflowKit/Sources/LifeWorkflowKit/Services/Good.swift"),
            code: "",
            moduleID: Optional("kit.services"))]
        let rule = ArchExtractor
            .checkInvariants(modules: [:], edges: [], scanned: scanned)
            .first { $0.id == "subprocess-macos-only" }
        #expect(rule?.violations.isEmpty == true)
    }

    // 回归：markers: ["VaultStore"] 这样的字符串字面量曾把声明它的文件
    // 自己判成该产物的读写方，也造出过假依赖边
    @Test("字符串字面量不产生依赖关系")
    func stringLiteralsDoNotCreateDependencies() {
        let code = ArchExtractor.strippedCode("""
        let markers = ["VaultStore", "RunLogService"]
        // 注释里提到 SkillsService 也不算
        let x = 1
        """)
        #expect(!ArchExtractor.containsIdentifier(code, "VaultStore"))
        #expect(!ArchExtractor.containsIdentifier(code, "RunLogService"))
        #expect(!ArchExtractor.containsIdentifier(code, "SkillsService"))
        #expect(ArchExtractor.containsIdentifier(code, "markers"))
    }

    @Test("只声明路径的模块算声明方，不算读写方")
    func pathDeclarerIsNotProducer() throws {
        let model = try ArchExtractor.extract(repoRoot: Self.repo).model
        let runlog = try #require(model.artifacts.first { $0.id == "runlog" })
        #expect(runlog.declaredBy.contains("kit.config"), "AppConfig 定义了 runLogJSONL")
        #expect(!runlog.producers.contains("kit.config"), "但它并不写日志内容")
        #expect(runlog.producers.contains("kit.services"), "RunLogService 才是写方")
    }

    @Test("扇入扇出统计")
    func fanInOut() {
        let model = ArchModel(edges: [
            .init(from: "a", to: "c"), .init(from: "b", to: "c"), .init(from: "c", to: "d"),
        ])
        #expect(model.fanIn("c") == 2)
        #expect(model.fanOut("c") == 1)
        #expect(model.fanIn("a") == 0)
    }

    @Test("目录不存在时给明确错误而不是崩溃")
    func missingRoot() {
        #expect(throws: ArchExtractor.Failure.self) {
            try ArchExtractor.extract(repoRoot: URL(fileURLWithPath: "/nonexistent-\(UUID())"))
        }
    }
}
