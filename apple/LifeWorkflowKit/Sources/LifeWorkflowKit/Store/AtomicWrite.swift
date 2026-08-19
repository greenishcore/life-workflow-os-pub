import Foundation

/// 文件写入工具：原子替换 + iCloud 文件协调。
enum FileIO {

    /// 先写临时文件再替换，避免写一半崩溃留下半截笔记。
    static func writeAtomically(_ text: String, to url: URL, coordinated: Bool) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let write: () throws -> Void = {
            let tmp = url.appendingPathExtension("tmp-\(UUID().uuidString.prefix(8))")
            do {
                try text.write(to: tmp, atomically: false, encoding: .utf8)
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            } catch {
                try? FileManager.default.removeItem(at: tmp)
                throw error
            }
        }

        guard coordinated else { return try write() }

        var coordinatorError: NSError?
        var thrown: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: url, options: .forReplacing, error: &coordinatorError
        ) { _ in
            do { try write() } catch { thrown = error }
        }
        if let thrown { throw thrown }
        if let coordinatorError { throw coordinatorError }
    }

    static func read(_ url: URL, coordinated: Bool) throws -> String {
        guard coordinated else { return try String(contentsOf: url, encoding: .utf8) }

        var coordinatorError: NSError?
        var result: Result<String, Error>?
        NSFileCoordinator().coordinate(
            readingItemAt: url, options: .withoutChanges, error: &coordinatorError
        ) { readURL in
            result = Result { try String(contentsOf: readURL, encoding: .utf8) }
        }
        if let coordinatorError { throw coordinatorError }
        guard let result else {
            throw VaultError.unreadable(url.path, "文件协调未返回结果")
        }
        return try result.get()
    }

    static func append(_ text: String, to url: URL, coordinated: Bool) throws {
        let existing = (try? read(url, coordinated: coordinated)) ?? ""
        try writeAtomically(existing + text, to: url, coordinated: coordinated)
    }
}

public enum VaultError: LocalizedError, Sendable {
    case rootMissing(String)
    case unreadable(String, String)
    case emptyCapture
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .rootMissing(let p): "vault 根目录不存在：\(p)"
        case .unreadable(let p, let why): "无法读取 \(p)：\(why)"
        case .emptyCapture: "捕获内容为空"
        case .notFound(let p): "找不到记录：\(p)"
        }
    }
}
