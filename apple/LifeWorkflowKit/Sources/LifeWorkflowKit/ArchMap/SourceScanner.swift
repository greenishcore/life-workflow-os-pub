import Foundation

/// Swift 源码的轻量扫描器：import、条件编译区间、行数、public 类型、敏感符号位置。
///
/// 逐行解析而不是接 SwiftSyntax：需要的信息就这几项，
/// 引一个几十 MB 的解析器依赖不划算，也违背仓库「零外部依赖」的既有原则。
///
/// **必须跳过注释**——本仓库的注释里大量出现 `Process`、`SwiftUI` 这类被约束关注的词，
/// 不剥离注释会把说明文字判成违例。
public enum SourceScanner {

    /// 约束关注的符号：出现位置与是否被条件编译包住都要记下来
    public static let watchedSymbols = ["Process(", "NSWorkspace", "NSOpenPanel", "UIApplication"]

    /// 被视为 UI 框架的 import（核心包里出现即违例）
    public static let uiFrameworks: Set<String> = ["SwiftUI", "UIKit", "AppKit", "WatchKit"]

    public static func scan(fileAt url: URL, relativeTo root: URL) -> SourceFile? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return scan(text: text, path: relativePath(of: url, under: root))
    }

    public static func scan(text: String, path: String) -> SourceFile {
        var imports: [String] = []
        var gates: [String] = []
        var publicTypes: [String] = []
        var guarded: [GuardedSymbol] = []

        var gateStack: [String] = []
        var inBlockComment = false
        var code = 0
        var robustness = Robustness()
        // 花括号深度：只有深度 0 的 public 类型才算这个模块「拥有」的类型。
        // 嵌套类型（RunLog.Status / ArchExtractor.Result）名字太通用，
        // 登记进去会和标准库或别的模块撞名，凭空造出依赖边。
        var braceDepth = 0

        for (index, rawLine) in text.components(separatedBy: "\n").enumerated() {
            let lineNumber = index + 1
            let (stripped, stillInBlock) = stripComments(rawLine, inBlockComment: inBlockComment)
            inBlockComment = stillInBlock
            let line = stripped.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            code += 1

            // ---- 条件编译 ----
            if line.hasPrefix("#if ") {
                gateStack.append(condition(of: line, prefix: "#if "))
                gates.append(contentsOf: platforms(in: line))
                continue
            }
            if line.hasPrefix("#elseif ") {
                if !gateStack.isEmpty { gateStack.removeLast() }
                gateStack.append(condition(of: line, prefix: "#elseif "))
                gates.append(contentsOf: platforms(in: line))
                continue
            }
            if line == "#else" {
                if let top = gateStack.popLast() { gateStack.append("!(\(top))") }
                continue
            }
            if line == "#endif" {
                if !gateStack.isEmpty { gateStack.removeLast() }
                continue
            }

            // ---- import ----
            if line.hasPrefix("import ") {
                let name = line.dropFirst("import ".count)
                    .split(separator: " ").first.map(String.init) ?? ""
                if !name.isEmpty { imports.append(name) }
                continue
            }

            // ---- public 类型（仅顶层）----
            if braceDepth == 0, let type = publicTypeName(in: line) { publicTypes.append(type) }

            // ---- 敏感符号（先剥字符串字面量，否则 watchedSymbols 自身的声明会自我命中）----
            let codeOnly = stripStringLiterals(line)
            for symbol in watchedSymbols where codeOnly.contains(symbol) {
                guarded.append(GuardedSymbol(
                    symbol: symbol.replacingOccurrences(of: "(", with: ""),
                    line: lineNumber,
                    insideGate: gateStack.isEmpty ? nil : gateStack.joined(separator: " && ")))
            }

            // ---- 稳健性信号（同样基于剥掉注释与字符串的代码）----
            countRobustness(in: codeOnly, into: &robustness)

            braceDepth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
            braceDepth = max(0, braceDepth)
        }

        return SourceFile(
            path: path, lines: code,
            imports: Array(Set(imports)).sorted(),
            platformGates: Array(Set(gates)).sorted(),
            publicTypes: Array(Set(publicTypes)).sorted(),
            guardedSymbols: guarded,
            robustness: robustness)
    }

    // MARK: 解析细节

    /// 去掉行注释与块注释。返回 (剩余代码, 是否仍处于块注释中)
    static func stripComments(_ line: String, inBlockComment: Bool) -> (String, Bool) {
        var out = ""
        var inBlock = inBlockComment
        var inString = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            if inBlock {
                if i + 1 < chars.count, chars[i] == "*", chars[i + 1] == "/" {
                    inBlock = false
                    i += 2
                    continue
                }
                i += 1
                continue
            }
            if chars[i] == "\"" { inString.toggle(); out.append(chars[i]); i += 1; continue }
            if !inString, i + 1 < chars.count {
                if chars[i] == "/", chars[i + 1] == "/" { break }          // 行注释
                if chars[i] == "/", chars[i + 1] == "*" { inBlock = true; i += 2; continue }
            }
            out.append(chars[i])
            i += 1
        }
        return (out, inBlock)
    }

    /// 统计一行里的稳健性信号。
    ///
    /// 注意顺序：`try!` 与 `try?` 都以 `try` 开头，必须先判 `try!` 再判 `try?`，
    /// 否则会漏计。强制解包要排除 `!=` 与前缀否定 `!foo`，只数后缀形式。
    static func countRobustness(in code: String, into r: inout Robustness) {
        r.forcedTries += occurrences(of: "try!", in: code)
        r.silencedErrors += occurrences(of: "try?", in: code)
        r.fatalSites += occurrences(of: "fatalError(", in: code)
            + occurrences(of: "preconditionFailure(", in: code)
        if code.contains("throws") { r.throwingFunctions += occurrences(of: "throws", in: code) }
        if code.contains("catch") { r.catchBlocks += occurrences(of: "catch", in: code) }
        r.forceUnwraps += forceUnwrapCount(in: code)
    }

    static func occurrences(of needle: String, in text: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var range = text.startIndex..<text.endIndex
        while let found = text.range(of: needle, range: range) {
            count += 1
            guard found.upperBound < text.endIndex else { break }
            range = found.upperBound..<text.endIndex
        }
        return count
    }

    /// 只数后缀强制解包（`foo!.bar` / `foo!`）。
    ///
    /// 要排除三种：`!=`、前缀否定 `!flag`、以及 **`try!` 里的那个 `!`**——
    /// 后者已经被 forcedTries 统计过，再算一次就是重复计数。
    static func forceUnwrapCount(in code: String) -> Int {
        let chars = Array(code)
        var count = 0
        for (i, c) in chars.enumerated() where c == "!" {
            guard i > 0 else { continue }
            let prev = chars[i - 1]
            let isSuffix = prev.isLetter || prev.isNumber || prev == "_" || prev == ")" || prev == "]"
            guard isSuffix else { continue }
            if i + 1 < chars.count, chars[i + 1] == "=" { continue }        // !=
            if i >= 3, String(chars[(i - 3)..<i]) == "try" { continue }     // try!
            count += 1
        }
        return count
    }

    /// 把 "..." 里的内容抹掉，只留代码。
    /// 不这么做的话，`watchedSymbols = ["Process("]` 这一行会把自己判成违例。
    public static func stripStringLiterals(_ line: String) -> String {
        var out = ""
        var inString = false
        var escaped = false
        for c in line {
            if escaped { escaped = false; continue }
            if c == "\\" , inString { escaped = true; continue }
            if c == "\"" { inString.toggle(); continue }
            if !inString { out.append(c) }
        }
        return out
    }

    static func condition(of line: String, prefix: String) -> String {
        String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    /// 从 `#if os(macOS) || os(iOS)` 里取出平台名
    static func platforms(in line: String) -> [String] {
        var found: [String] = []
        var rest = Substring(line)
        while let start = rest.range(of: "os(") {
            let after = rest[start.upperBound...]
            if let close = after.firstIndex(of: ")") {
                found.append(String(after[..<close]))
                rest = after[after.index(after: close)...]
            } else { break }
        }
        return found
    }

    static let typeKeywords = ["struct", "class", "enum", "actor", "protocol", "extension"]

    /// `public struct Foo` / `public actor Bar` → Foo / Bar
    static func publicTypeName(in line: String) -> String? {
        guard line.hasPrefix("public ") || line.hasPrefix("open ") else { return nil }
        let words = line.split(separator: " ").map(String.init)
        for (i, word) in words.enumerated() where typeKeywords.contains(word) {
            guard i + 1 < words.count else { return nil }
            let raw = words[i + 1]
            let name = raw.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            return name.isEmpty ? nil : String(name)
        }
        return nil
    }

    // MARK: 文件遍历

    /// 递归收集 .swift 文件，跳过构建产物
    public static func swiftFiles(under root: URL) -> [URL] {
        let skip: Set<String> = [".build", ".swiftpm", "DerivedData", ".git", "dist"]
        guard let e = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return [] }

        var out: [URL] = []
        for case let url as URL in e {
            let name = url.lastPathComponent
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                if skip.contains(name) { e.skipDescendants() }
                continue
            }
            if url.pathExtension == "swift" { out.append(url) }
        }
        return out.sorted { $0.path < $1.path }
    }

    static func relativePath(of url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count).drop { $0 == "/" })
    }
}
