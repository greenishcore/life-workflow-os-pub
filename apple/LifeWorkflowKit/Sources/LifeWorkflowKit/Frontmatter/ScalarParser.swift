import Foundation

/// 标量与流式集合的解析。
enum ScalarParser {

    static let nullTokens: Set<String> = ["null", "Null", "NULL", "~", "None", ""]
    static let trueTokens: Set<String> = ["true", "True", "TRUE", "yes", "Yes", "on", "On"]
    static let falseTokens: Set<String> = ["false", "False", "FALSE", "no", "No", "off", "Off"]

    /// 解析一个值：可能是流式集合、引号标量或裸标量。
    static func parse(_ raw: String) -> YAMLValue {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return .null }
        if s.hasPrefix("[") { return parseFlow(s).value }
        if s.hasPrefix("{") { return parseFlow(s).value }
        if s.hasPrefix("\"") || s.hasPrefix("'") { return .string(unquote(s)) }
        return parseBare(stripInlineComment(s))
    }

    /// 裸标量：识别 null / bool / int / double / 日期，其余当字符串。
    static func parseBare(_ raw: String) -> YAMLValue {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if nullTokens.contains(s) { return .null }
        if trueTokens.contains(s) { return .bool(true) }
        if falseTokens.contains(s) { return .bool(false) }
        if isDateShaped(s) { return .date(s) }
        if let i = Int(s), String(i) == s { return .int(i) }
        // 避免把 "1.0.0"、"2026-08" 这类误判成数字
        if let d = Double(s), s.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789")) != nil,
           s.filter({ $0 == "." }).count <= 1, !s.contains("-") || s.hasPrefix("-") {
            return .double(d)
        }
        return .string(s)
    }

    /// `YYYY-MM-DD` 形状判断。手写而不用 Regex：静态 Regex 不是 Sendable，
    /// 而每次构造又是无谓开销——这个判断在扫描整个 vault 时会被调用几万次。
    static func isDateShaped(_ s: String) -> Bool {
        let c = Array(s)
        guard c.count == 10, c[4] == "-", c[7] == "-" else { return false }
        for i in [0, 1, 2, 3, 5, 6, 8, 9] where !c[i].isASCII || !c[i].isNumber { return false }
        return true
    }

    /// 去掉裸标量后面的行内注释（` #` 起）。模板里 `status: seed   # seed → sprout…` 就靠这个。
    static func stripInlineComment(_ s: String) -> String {
        guard let range = s.range(of: " #") else { return s }
        return String(s[s.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    /// 去引号并处理转义。
    static func unquote(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") {
            return unescapeDouble(String(s.dropFirst().dropLast()))
        }
        if s.count >= 2, s.hasPrefix("'"), s.hasSuffix("'") {
            return String(s.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return s
    }

    private static func unescapeDouble(_ s: String) -> String {
        var out = ""
        var iter = s.makeIterator()
        while let c = iter.next() {
            guard c == "\\" else { out.append(c); continue }
            guard let e = iter.next() else { out.append("\\"); break }
            switch e {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            case "\"": out.append("\"")
            case "\\": out.append("\\")
            case "0": out.append("\0")
            default: out.append(e)
            }
        }
        return out
    }

    // MARK: 流式集合

    /// 解析 `[...]` 或 `{...}`，返回值与消费掉的长度。
    static func parseFlow(_ s: String) -> (value: YAMLValue, consumed: Int) {
        var chars = Array(s)
        var i = 0
        return (parseFlowValue(&chars, &i), i)
    }

    private static func parseFlowValue(_ chars: inout [Character], _ i: inout Int) -> YAMLValue {
        skipSpaces(&chars, &i)
        guard i < chars.count else { return .null }
        switch chars[i] {
        case "[": return parseFlowSequence(&chars, &i)
        case "{": return parseFlowMapping(&chars, &i)
        default:  return parseFlowScalar(&chars, &i, terminators: [",", "]", "}"])
        }
    }

    private static func parseFlowSequence(_ chars: inout [Character], _ i: inout Int) -> YAMLValue {
        i += 1                       // 吃掉 [
        var items: [YAMLValue] = []
        while i < chars.count {
            skipSpaces(&chars, &i)
            if i < chars.count, chars[i] == "]" { i += 1; break }
            let v = parseFlowValue(&chars, &i)
            items.append(v)
            skipSpaces(&chars, &i)
            if i < chars.count, chars[i] == "," { i += 1; continue }
            if i < chars.count, chars[i] == "]" { i += 1; break }
            if i >= chars.count { break }
        }
        return .array(items)
    }

    private static func parseFlowMapping(_ chars: inout [Character], _ i: inout Int) -> YAMLValue {
        i += 1                       // 吃掉 {
        var m = YAMLMapping()
        while i < chars.count {
            skipSpaces(&chars, &i)
            if i < chars.count, chars[i] == "}" { i += 1; break }
            let keyValue = parseFlowScalar(&chars, &i, terminators: [":", ",", "}"])
            let key = keyValue.stringValue ?? ""
            skipSpaces(&chars, &i)
            var value: YAMLValue = .null
            if i < chars.count, chars[i] == ":" {
                i += 1
                value = parseFlowValue(&chars, &i)
            }
            if !key.isEmpty { m[key] = value }
            skipSpaces(&chars, &i)
            if i < chars.count, chars[i] == "," { i += 1; continue }
            if i < chars.count, chars[i] == "}" { i += 1; break }
            if i >= chars.count { break }
        }
        return .mapping(m)
    }

    private static func parseFlowScalar(
        _ chars: inout [Character], _ i: inout Int, terminators: Set<Character>
    ) -> YAMLValue {
        skipSpaces(&chars, &i)
        guard i < chars.count else { return .null }

        // 引号标量：整段吃到闭合引号，内部的逗号/冒号不算分隔符
        if chars[i] == "\"" || chars[i] == "'" {
            let quote = chars[i]
            var buf = String(quote)
            i += 1
            while i < chars.count {
                let c = chars[i]
                if c == "\\", quote == "\"", i + 1 < chars.count {
                    buf.append(c); buf.append(chars[i + 1]); i += 2; continue
                }
                if c == quote {
                    // '' 是单引号里的转义
                    if quote == "'", i + 1 < chars.count, chars[i + 1] == "'" {
                        buf.append("''"); i += 2; continue
                    }
                    buf.append(c); i += 1; break
                }
                buf.append(c); i += 1
            }
            return .string(unquote(buf))
        }

        var buf = ""
        while i < chars.count, !terminators.contains(chars[i]) {
            buf.append(chars[i]); i += 1
        }
        return parseBare(buf.trimmingCharacters(in: .whitespaces))
    }

    private static func skipSpaces(_ chars: inout [Character], _ i: inout Int) {
        while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 }
    }
}
