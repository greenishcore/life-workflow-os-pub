import Foundation

/// 从源码树提取架构模型，并校验架构约束。
///
/// 依赖边的判定不能只看 `import`：Swift 同一 target 内的文件互相可见，
/// import 只反映跨 target 依赖。真正的模块间依赖要靠**类型引用**——
/// A 组的文件里出现了 B 组声明的 public 类型，才算 A 依赖 B。
public enum ArchExtractor {

    public struct Result: Sendable {
        public let model: ArchModel
        /// 代码里存在、但 LayerRules 没登记的目录 —— 地图与实现脱节的信号
        public let uncoveredPaths: [String]
    }

    public enum Failure: LocalizedError {
        case rootMissing(String)
        case noSources(String)

        public var errorDescription: String? {
            switch self {
            case .rootMissing(let p): "仓库根目录不存在：\(p)"
            case .noSources(let p): "在 \(p) 下没有找到任何 .swift 源文件"
            }
        }
    }

    public static func extract(repoRoot: URL) throws -> Result {
        guard FileManager.default.fileExists(atPath: repoRoot.path) else {
            throw Failure.rootMissing(repoRoot.path)
        }
        let appleRoot = repoRoot.appendingPathComponent("apple")
        let files = SourceScanner.swiftFiles(under: appleRoot)
        guard !files.isEmpty else { throw Failure.noSources(appleRoot.path) }

        // ---- 第 1 遍：扫描并归组 ----
        var scanned: [(file: SourceFile, code: String, moduleID: String?)] = []
        var uncovered = Set<String>()

        for url in files {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let path = SourceScanner.relativePath(of: url, under: repoRoot)
            // 测试文件不进依赖图，但要留着做覆盖判定
            let file = SourceScanner.scan(text: text, path: path)
            let mapped = LayerRules.module(for: path)
            // Package.swift 是构建配置不是模块，不该算进"地图未覆盖"
            if mapped == nil, !isTest(path), !path.hasSuffix("Package.swift") {
                uncovered.insert((path as NSString).deletingLastPathComponent)
            }
            scanned.append((file, strippedCode(text), mapped?.id))
        }

        // ---- 组装模块 ----
        var modules: [String: Module] = [:]
        for entry in LayerRules.moduleMap {
            modules[entry.id] = Module(id: entry.id, name: entry.name, path: entry.prefix,
                                       layerID: entry.layer, target: entry.target)
        }
        for item in scanned {
            guard let id = item.moduleID, !isTest(item.file.path) else { continue }
            modules[id]?.files.append(item.file)
            modules[id]?.publicTypes.append(contentsOf: item.file.publicTypes)
        }
        // 没有文件的模块不进图（比如还没建的目录）
        modules = modules.filter { !$0.value.files.isEmpty }

        // ---- 第 2 遍：按类型引用建边 ----
        var ownerOfType: [String: String] = [:]
        for (id, module) in modules {
            for type in Set(module.publicTypes) where type.count >= 3 {
                ownerOfType[type] = id
            }
        }
        var edgeFiles: [String: Set<String>] = [:]   // "from->to" → 文件集合
        for item in scanned {
            guard let from = item.moduleID, !isTest(item.file.path) else { continue }
            for (type, owner) in ownerOfType where owner != from {
                guard containsIdentifier(item.code, type) else { continue }
                edgeFiles["\(from)->\(owner)", default: []].insert(item.file.path)
            }
        }
        let edges = edgeFiles.map { key, files -> Edge in
            let parts = key.components(separatedBy: "->")
            return Edge(from: parts[0], to: parts[1], viaFiles: Array(files))
        }

        // ---- 数据产物的读写方 ----
        var artifacts = LayerRules.artifacts
        for i in artifacts.indices {
            for item in scanned {
                guard let id = item.moduleID, !isTest(item.file.path) else { continue }
                let touched = artifacts[i].markers.filter { containsIdentifier(item.code, $0) }
                guard !touched.isEmpty else { continue }

                // 只是**声明**了路径（AppConfig 定义 runLogJSONL 之类）算不上读写方。
                // 不区分的话，配置模块会被误判成所有产物的写方。
                if touched.allSatisfy({ declaresSymbol(item.code, $0) }) {
                    artifacts[i].declaredBy.append(id)
                    continue
                }
                if writesData(item.code) { artifacts[i].producers.append(id) }
                artifacts[i].consumers.append(id)
            }
        }

        // ---- 阶段 ----
        var stages = LayerRules.stages
        for i in stages.indices {
            stages[i].moduleIDs = LayerRules.stageModules[stages[i].id] ?? []
        }

        let model = ArchModel(
            layers: LayerRules.layers,
            modules: Array(modules.values),
            edges: edges,
            artifacts: artifacts,
            stages: stages,
            invariants: checkInvariants(modules: modules, edges: edges, scanned: scanned))

        return Result(model: model.normalized(), uncoveredPaths: uncovered.sorted())
    }

    // MARK: 约束校验

    static func checkInvariants(
        modules: [String: Module], edges: [Edge],
        scanned: [(file: SourceFile, code: String, moduleID: String?)]
    ) -> [Invariant] {
        var out: [Invariant] = []

        // 1. 核心包不得 import UI 框架
        var uiViolations: [Violation] = []
        for item in scanned where item.file.path.hasPrefix("apple/LifeWorkflowKit/Sources") {
            for framework in item.file.imports where SourceScanner.uiFrameworks.contains(framework) {
                uiViolations.append(.init(file: item.file.path,
                                          detail: "核心包 import 了 \(framework)"))
            }
        }
        out.append(Invariant(
            id: "kit-no-ui",
            title: "核心包不得依赖 UI 框架",
            rationale: "核心包要同时供 macOS / iOS（及将来的 watchOS）使用。"
                + "这是唯一编译器给不了的保护：SwiftUI 在 macOS 与 iOS 上都可用，"
                + "核心包 import 了照样编过，代价要等到加 watchOS 或核心包变得难测时才显现——"
                + "延迟且弥散，正是该用门禁挡的那类",
            violations: uiViolations))

        // 2. 依赖只能向下
        var directionViolations: [Violation] = []
        for edge in edges {
            guard let from = modules[edge.from], let to = modules[edge.to] else { continue }
            let fromRank = LayerRules.rank(of: from.layerID)
            let toRank = LayerRules.rank(of: to.layerID)
            guard fromRank < toRank else { continue }
            directionViolations.append(.init(
                file: edge.viaFiles.first ?? from.path,
                detail: "\(from.name)（\(from.layerID)）依赖了上层的 \(to.name)（\(to.layerID)）"))
        }
        out.append(Invariant(
            id: "downward-only",
            title: "依赖只能向下",
            rationale: "底层不该知道上层存在。但分层模型是本文件声明的、不是语言固有的，"
                + "首次运行就误报过一次（当时是分层定义写错，不是代码错）。"
                + "在架构还在演进时把它设成硬门禁只会持续要求重新裁定，因此降为参考",
            severity: .advisory,
            violations: directionViolations))

        // 3. macOS 与 iOS 的 UI 互不依赖
        let crossUI = edges.filter {
            ($0.from == "app.macos" && $0.to == "app.ios") ||
            ($0.from == "app.ios" && $0.to == "app.macos")
        }
        out.append(Invariant(
            id: "ui-targets-isolated",
            title: "macOS 与 iOS 的 UI 互不依赖",
            rationale: "两端 UI 刻意各写各的。**构建系统已经保证了这一点**——"
                + "macOS 与 iOS 是不同 target（Shared+macOS / Shared+iOS），跨端引用根本编译不过。"
                + "这里保留只为说明意图，不作门禁",
            severity: .advisory,
            violations: crossUI.map {
                .init(file: $0.viaFiles.first ?? "", detail: "\($0.from) → \($0.to)")
            }))

        // 4. 子进程调用必须限定在 macOS
        var processViolations: [Violation] = []
        for item in scanned where item.file.path.hasPrefix("apple/LifeWorkflowKit/Sources") {
            for symbol in item.file.guardedSymbols where symbol.symbol == "Process" {
                let gate = symbol.insideGate ?? ""
                let macOSOnly = gate.contains("os(macOS)") && !gate.contains("!os(macOS)")
                guard !macOSOnly else { continue }
                processViolations.append(.init(
                    file: item.file.path, line: symbol.line,
                    detail: "Process 未被 #if os(macOS) 包住"))
            }
        }
        out.append(Invariant(
            id: "subprocess-macos-only",
            title: "子进程调用限定 macOS",
            rationale: "iOS 沙盒不允许 fork 子进程。**编译器已经保证了这一点**——"
                + "iOS SDK 里根本没有 NSTask.h，Process 在 iOS 上不存在，用了就是编译错误。"
                + "这里保留只为说明意图，不作门禁",
            severity: .advisory,
            violations: processViolations))

        // 5. 每个模块至少被测试引用（参考项，不阻断 CI）
        let testCode = scanned.filter { isTest($0.file.path) }.map(\.code).joined(separator: "\n")
        var untested: [Violation] = []
        for module in modules.values.sorted(by: { $0.id < $1.id }) {
            guard module.target == "kit" else { continue }   // 只要求核心包
            let referenced = module.publicTypes.contains { containsIdentifier(testCode, $0) }
            if !referenced {
                untested.append(.init(file: module.path, detail: "\(module.name) 没有被任何测试引用"))
            }
        }
        out.append(Invariant(
            id: "kit-modules-tested",
            title: "核心包每个模块都有测试覆盖",
            rationale: "核心包会被三端共用，出问题是三端一起出；这里只作参考不阻断，避免为了指标写假测试",
            severity: .advisory,
            violations: untested))

        // ---- 界面设计交接的三条护栏 ----
        //
        // 这三条守的是「界面设计可以交给别人改」这条边界。编译器一条也管不了：
        // 写死字号编得过、视图里跑 git 也编得过，代价要等到交接之后才显现。
        out.append(contentsOf: uiHandoffInvariants(scanned: scanned))

        return out
    }

    // MARK: 界面交接护栏

    /// 视图与绘图组件所在的目录。AppState 在 Shared/ 里，它调服务是本职，不在管辖范围。
    static func isDesignSurface(_ path: String) -> Bool {
        guard path.hasPrefix("apple/LifeOSApp/Sources") else { return false }
        return path.contains("/Views/") || path.contains("/Components/")
    }

    /// 设计令牌自身的定义处——它当然要写字面量，否则令牌从哪来。
    static func isTokenDefinition(_ path: String) -> Bool {
        path.hasSuffix("Sources/Shared/Theme.swift")
    }

    /// 已收录进 `Theme.Space` 的档位。用这些数字只是「还没换成令牌」，机械替换即可；
    /// 其它数字要先决定归到哪一档，那是设计决策。
    static let spacingScale: Set<Int> = [0, 2, 4, 8, 12, 16, 20]

    static func uiHandoffInvariants(
        scanned: [(file: SourceFile, code: String, moduleID: String?)]
    ) -> [Invariant] {
        var typography: [Violation] = []
        var offScaleSpacing: [Violation] = []
        var onScaleCount = 0
        var services: [Violation] = []

        for item in scanned where !isTokenDefinition(item.file.path) {
            let inDesignSurface = isDesignSurface(item.file.path)
            // code 已经剥掉注释与字符串字面量，行号仍与原文一一对应
            for (index, line) in item.code.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let text = String(line)
                let lineNo = index + 1

                if inDesignSurface, text.contains(".system(size:") {
                    typography.append(.init(
                        file: item.file.path, line: lineNo,
                        detail: "写死字号，应改用 Theme.Typo 的令牌"))
                }

                if inDesignSurface {
                    for value in spacingLiterals(in: text) {
                        if spacingScale.contains(value) {
                            onScaleCount += 1
                        } else {
                            offScaleSpacing.append(.init(
                                file: item.file.path, line: lineNo,
                                detail: "间距 \(value)pt 不在 Theme.Space 的档位上"))
                        }
                    }
                }

                if inDesignSurface, let hit = serviceCall(in: text) {
                    services.append(.init(
                        file: item.file.path, line: lineNo,
                        detail: "视图直接调用了 \(hit)，应经由 AppState"))
                }
            }
        }

        return [
            Invariant(
                id: "ui-typography-tokens",
                title: "视图不得写死字号",
                rationale: "排版要有单一事实源，接手方才可能只改一处就调完整套界面。"
                    + "迁移前全仓 154 处写死字号、21 种组合，改「次要说明大一号」要翻 22 个文件。"
                    + "编译器管不了这件事，只能靠门禁",
                violations: typography),
            Invariant(
                id: "ui-spacing-tokens",
                title: "间距应落在 Theme.Space 的档位上",
                rationale: "这条是**给接手方的规范化清单**，不是门禁。列出的是不在档位上的取值"
                    + "（1/3/5/7/9/11/18pt 这类）——把它们对齐到刻度会改变布局，"
                    + "那是设计决策，不该由重构顺手决定。"
                    + "另有 \(onScaleCount) 处虽是裸数字但已在档位上，属机械替换，未计入",
                severity: .advisory,
                violations: offScaleSpacing),
            Invariant(
                id: "ui-no-services",
                title: "视图不得直接调用服务",
                rationale: "界面设计要能独立交接，改排版就不该碰到跑 git、起子进程、写文件的代码。"
                    + "判定只看「Service. 后面跟小写开头的成员」——那是方法或属性；"
                    + "跟大写开头的是嵌套类型（如 ConvertService.Target），"
                    + "选择器要用它来渲染选项，属于合理引用",
                violations: services),
        ]
    }

    /// 抓 `.padding(8)` / `.padding(.horizontal, 6)` / `spacing: 12` 里的裸数字
    static func spacingLiterals(in line: String) -> [Int] {
        var out: [Int] = []
        for marker in [".padding(", "spacing:"] {
            var search = line[...]
            while let range = search.range(of: marker) {
                let rest = search[range.upperBound...]
                out.append(contentsOf: leadingNumbers(in: rest))
                search = rest
            }
        }
        return out
    }

    /// SwiftUI 的边指定符。`.padding(.horizontal, 6)` 里要先跳过它才够得着数字。
    static let edgeSpecifiers: Set<String> = [
        "horizontal", "vertical", "top", "bottom", "leading", "trailing", "all",
    ]

    /// 从 `8)` / `.horizontal, 6)` 这样的片段里取出那个裸数字。
    /// 数字前面若是标识符（`Theme.pad`、某个变量），说明已经用了令牌，返回空。
    static func leadingNumbers(in fragment: Substring) -> [Int] {
        var rest = fragment.drop { $0 == " " }
        if rest.first == "." {
            let name = rest.dropFirst().prefix { $0.isLetter }
            if edgeSpecifiers.contains(String(name)) {
                rest = rest.dropFirst(1 + name.count).drop { $0 == "," || $0 == " " }
            }
        }
        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty, let n = Int(digits) else { return [] }
        return [n]
    }

    /// 视图里对服务的**调用**。`Service.` 后跟小写 = 方法或属性；跟大写 = 嵌套类型，放行。
    static func serviceCall(in line: String) -> String? {
        if line.contains("EventKitBridge(") { return "EventKitBridge" }
        var search = line[...]
        while let range = search.range(of: "Service.") {
            let head = search[..<range.lowerBound]
            let name = String(head.reversed().prefix { $0.isLetter }.reversed()) + "Service"
            if let next = search[range.upperBound...].first, next.isLowercase {
                return name + "." + String(search[range.upperBound...].prefix { $0.isLetter || $0.isNumber })
            }
            search = search[range.upperBound...]
        }
        return nil
    }

    // MARK: 辅助

    static func isTest(_ path: String) -> Bool {
        path.contains("/Tests/") || path.hasSuffix("Tests.swift")
    }

    /// 词边界匹配，避免 `Item` 命中 `ItemType`
    static func containsIdentifier(_ text: String, _ identifier: String) -> Bool {
        guard !identifier.isEmpty else { return false }
        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: identifier, range: searchRange) {
            let beforeOK = found.lowerBound == text.startIndex
                || !isIdentifierChar(text[text.index(before: found.lowerBound)])
            let afterOK = found.upperBound == text.endIndex
                || !isIdentifierChar(text[found.upperBound])
            if beforeOK && afterOK { return true }
            guard found.upperBound < text.endIndex else { return false }
            searchRange = found.upperBound..<text.endIndex
        }
        return false
    }

    static func isIdentifierChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }

    /// 粗判「这个模块是否在写数据」：出现落盘/追加/创建类调用即算写方。
    /// 粗略但足够——目的是在信息流图上区分箭头方向，不是做静态分析。
    /// 判断这段代码是「声明」这个符号，而不是「使用」它
    static func declaresSymbol(_ code: String, _ symbol: String) -> Bool {
        ["var \(symbol)", "let \(symbol)", "func \(symbol)"].contains { code.contains($0) }
    }

    static func writesData(_ code: String) -> Bool {
        // 刻意不含 create( —— createDirectory 只是建目录，不是写内容，
        // 算进去会让 AppConfig 被误判成所有产物的写方
        ["writeAtomically", ".write(to:", ".save(", ".append(", "removeItem(", "moveItem("]
            .contains { code.contains($0) }
    }

    /// 剥掉注释**与字符串字面量**后的代码。
    ///
    /// 两者都必须剥：注释里会讨论其它模块的类型名，
    /// 字符串里会出现标志符号本身（`markers: ["VaultStore"]` 这一行就会自我命中）。
    /// 不剥就会凭空造出依赖边和读写关系。
    static func strippedCode(_ text: String) -> String {
        var out: [String] = []
        var inBlock = false
        for line in text.components(separatedBy: "\n") {
            let (stripped, still) = SourceScanner.stripComments(line, inBlockComment: inBlock)
            inBlock = still
            out.append(SourceScanner.stripStringLiterals(stripped))
        }
        return out.joined(separator: "\n")
    }
}
