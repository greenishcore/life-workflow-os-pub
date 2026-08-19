import Foundation

/// frontmatter 解析器：按行 + 缩进的递归下降，覆盖本项目实际用到的 YAML 子集。
///
/// 支持：块映射、块序列、内联数组 `[a, b]`、流式映射 `{k: v}`、
/// 单/双引号标量、块标量 `|` `|-` `>` `>-`、行内注释、嵌套结构。
/// 解析失败一律降级为「无 frontmatter」，**绝不抛错**——笔记是用户资产，
/// 宁可当成纯正文也不能让应用崩掉。
public enum FrontmatterParser {

    /// 拆出 (frontmatter 原文, 正文)；无 frontmatter 时 yaml 为 nil。
    public static func split(_ text: String) -> (yaml: String?, body: String) {
        guard text.hasPrefix("---") else { return (nil, text) }
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespaces) == "---" else { return (nil, text) }

        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                let yaml = lines[1..<i].joined(separator: "\n")
                let rest = lines[(i + 1)...].joined(separator: "\n")
                // 去掉紧跟分隔线的那一个换行，与 Python 版的正则行为一致
                return (yaml, rest.hasPrefix("\n") ? String(rest.dropFirst()) : rest)
            }
        }
        return (nil, text)
    }

    /// 返回 (frontmatter 映射, 正文)。没有或解析不了时映射为空。
    public static func parse(_ text: String) -> (mapping: YAMLMapping, body: String) {
        let (yaml, body) = split(text)
        guard let yaml else { return (YAMLMapping(), body) }
        return (parseMapping(yaml), body)
    }

    /// 解析一段 YAML 文本为映射。
    public static func parseMapping(_ yaml: String) -> YAMLMapping {
        var scanner = LineScanner(yaml)
        guard let first = scanner.peek() else { return YAMLMapping() }
        return scanner.readMapping(indent: first.indent)
    }
}

// MARK: - 行扫描

private struct Line {
    let indent: Int
    let content: String
}

private struct LineScanner {
    private var lines: [Line]
    private var pos = 0

    init(_ text: String) {
        lines = text.components(separatedBy: "\n").compactMap { raw in
            let indent = raw.prefix { $0 == " " }.count
            let content = String(raw.dropFirst(indent))
            // 跳过空行与整行注释
            if content.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
            if content.hasPrefix("#") { return nil }
            return Line(indent: indent, content: content)
        }
    }


    func peek() -> Line? { pos < lines.count ? lines[pos] : nil }

    mutating func advance() { pos += 1 }

    // MARK: 映射

    mutating func readMapping(indent: Int) -> YAMLMapping {
        var mapping = YAMLMapping()
        while let line = peek(), line.indent == indent, !line.content.hasPrefix("-") {
            advance()
            guard let (key, rest) = Self.splitKey(line.content) else { continue }

            if let style = BlockScalarStyle(rest) {
                mapping[key] = .string(readBlockScalar(parentIndent: indent, style: style))
            } else if rest.isEmpty {
                if let next = peek(), next.indent > indent {
                    mapping[key] = readNode(indent: next.indent)
                } else if let next = peek(), next.indent == indent, next.content.hasPrefix("-") {
                    // 序列与父键同缩进（YAML 允许）
                    mapping[key] = readNode(indent: indent)
                } else {
                    mapping[key] = .null
                }
            } else {
                mapping[key] = ScalarParser.parse(rest)
            }
        }
        return mapping
    }

    mutating func readNode(indent: Int) -> YAMLValue {
        guard let line = peek() else { return .null }
        if line.content.hasPrefix("-") {
            return readSequence(indent: line.indent)
        }
        return .mapping(readMapping(indent: indent))
    }

    // MARK: 序列

    mutating func readSequence(indent: Int) -> YAMLValue {
        var items: [YAMLValue] = []
        while let line = peek(), line.indent == indent, line.content.hasPrefix("-") {
            advance()
            var rest = String(line.content.dropFirst())
            if rest.hasPrefix(" ") { rest = String(rest.drop { $0 == " " }) }

            if rest.isEmpty {
                if let next = peek(), next.indent > indent {
                    items.append(readNode(indent: next.indent))
                } else {
                    items.append(.null)
                }
                continue
            }

            // `- key: value` 形式：这一项是个映射，可能还有更深缩进的兄弟键
            if !rest.hasPrefix("{"), !rest.hasPrefix("["),
               let (key, value) = Self.splitKey(rest) {
                var m = YAMLMapping()
                // 该项内部键的缩进 = 短横线所在列 + "- " 的宽度
                let innerIndent = indent + (line.content.count - rest.count)
                if let style = BlockScalarStyle(value) {
                    m[key] = .string(readBlockScalar(parentIndent: innerIndent - 1, style: style))
                } else if value.isEmpty {
                    if let next = peek(), next.indent > innerIndent {
                        m[key] = readNode(indent: next.indent)
                    } else {
                        m[key] = .null
                    }
                } else {
                    m[key] = ScalarParser.parse(value)
                }
                // 继续吃同属这一项的后续键
                while let next = peek(), next.indent == innerIndent, !next.content.hasPrefix("-") {
                    advance()
                    guard let (k2, v2) = Self.splitKey(next.content) else { continue }
                    if let style = BlockScalarStyle(v2) {
                        m[k2] = .string(readBlockScalar(parentIndent: innerIndent, style: style))
                    } else if v2.isEmpty {
                        if let deeper = peek(), deeper.indent > innerIndent {
                            m[k2] = readNode(indent: deeper.indent)
                        } else {
                            m[k2] = .null
                        }
                    } else {
                        m[k2] = ScalarParser.parse(v2)
                    }
                }
                items.append(.mapping(m))
                continue
            }

            items.append(ScalarParser.parse(rest))
        }
        return .array(items)
    }

    // MARK: 块标量

    mutating func readBlockScalar(parentIndent: Int, style: BlockScalarStyle) -> String {
        var collected: [String] = []
        var contentIndent: Int?
        while let line = peek(), line.indent > parentIndent {
            advance()
            if contentIndent == nil { contentIndent = line.indent }
            let strip = min(line.indent, contentIndent ?? line.indent)
            collected.append(String(repeating: " ", count: line.indent - strip) + line.content)
        }
        var text = style.folded
            ? collected.joined(separator: " ")
            : collected.joined(separator: "\n")
        if style.chompStrip {
            while text.hasSuffix("\n") { text.removeLast() }
        } else if style.chompClip, !text.isEmpty {
            text += "\n"
        }
        return text
    }

    // MARK: 键拆分

    /// 找到第一个不在引号/括号内的 `: ` 或行尾的 `:`，拆成 (key, rest)。
    static func splitKey(_ line: String) -> (String, String)? {
        var inSingle = false, inDouble = false, depth = 0
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "'" , !inDouble { inSingle.toggle() }
            else if c == "\"", !inSingle { inDouble.toggle() }
            else if !inSingle, !inDouble {
                if c == "[" || c == "{" { depth += 1 }
                else if c == "]" || c == "}" { depth -= 1 }
                else if c == ":", depth == 0 {
                    let isLast = i == chars.count - 1
                    if isLast || chars[i + 1] == " " {
                        let key = String(chars[0..<i]).trimmingCharacters(in: .whitespaces)
                        let rest = isLast ? "" : String(chars[(i + 2)...]).trimmingCharacters(in: .whitespaces)
                        return (ScalarParser.unquote(key), rest)
                    }
                }
            }
            i += 1
        }
        return nil
    }
}

// MARK: - 块标量样式

private struct BlockScalarStyle {
    let folded: Bool
    let chompStrip: Bool
    let chompClip: Bool

    init?(_ token: String) {
        let t = token.trimmingCharacters(in: .whitespaces)
        guard t == "|" || t == "|-" || t == "|+" || t == ">" || t == ">-" || t == ">+" else { return nil }
        folded = t.hasPrefix(">")
        chompStrip = t.hasSuffix("-")
        chompClip = t.count == 1
    }
}
