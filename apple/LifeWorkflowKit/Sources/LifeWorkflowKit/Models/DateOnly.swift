import Foundation

/// 日期工具：全项目统一用 `YYYY-MM-DD` 文本表示日期。
///
/// 不用 `Date`，因为：frontmatter 里存的就是无时区的日历日，
/// 转成 `Date` 再转回来会引入时区漂移，破坏「读写往返逐字节一致」。
public enum DateOnly {
    /// 用固定的公历 + POSIX 语言环境，避免用户的农历/地区设置影响输出
    // DateFormatter 在 Apple 平台上格式化操作是线程安全的，且此处只读不改
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func today(_ date: Date = Date()) -> String {
        formatter.string(from: date)
    }

    public static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    public static func date(from string: String) -> Date? {
        formatter.date(from: String(string.prefix(10)))
    }

    /// 归一化任意日期写法为 `YYYY-MM-DD`；识别不了返回空串（对齐 Python 版 norm_date）。
    public static func normalize(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return ""
        }
        // 接受 2026-8-6 这种非补零写法，输出补零形式
        let pattern = /^(\d{4})-(\d{1,2})-(\d{1,2})/
        guard let m = try? pattern.firstMatch(in: raw) else { return "" }
        let year = String(m.1)
        let month = Int(m.2) ?? 1
        let day = Int(m.3) ?? 1
        return String(format: "%@-%02d-%02d", year, month, day)
    }

    /// 两个日期串之间相差的天数（含首尾则再 +1，由调用方决定）
    public static func daysBetween(_ from: String, _ to: String) -> Int? {
        guard let a = date(from: from), let b = date(from: to) else { return nil }
        let cal = Calendar(identifier: .gregorian)
        return cal.dateComponents([.day], from: a, to: b).day
    }

    public static func adding(days: Int, to string: String) -> String? {
        guard let d = date(from: string) else { return nil }
        let cal = Calendar(identifier: .gregorian)
        guard let next = cal.date(byAdding: .day, value: days, to: d) else { return nil }
        return self.string(from: next)
    }
}
