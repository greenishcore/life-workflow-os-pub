import Foundation

#if os(macOS)
/// 外部命令的统一封装。
///
/// 只在 macOS 可用：iOS/watchOS 沙盒不允许 fork 子进程，
/// 这也是「格式转换与 git 集中在 Mac」这条架构决定的技术依据。
public enum ProcessRunner {

    public struct Result: Sendable {
        public let code: Int32
        public let out: String
        public let err: String
        public var ok: Bool { code == 0 }
        public var text: String {
            let combined = out + (err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n" + err)
            return combined.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// 常见工具的安装位置。GUI 应用继承的 PATH 很窄，
    /// 不显式找路径的话 pandoc/gh 这类 Homebrew 工具会「明明装了却找不到」。
    static let searchPaths = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
        (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin"),
    ]

    public static func which(_ name: String) -> String? {
        for dir in searchPaths {
            let path = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    public static func have(_ name: String) -> Bool { which(name) != nil }

    @discardableResult
    public static func run(
        _ command: String,
        _ arguments: [String],
        cwd: URL? = nil,
        timeout: TimeInterval = 300,
        log: (@Sendable (String) -> Void)? = nil
    ) async -> Result {
        guard let executable = which(command) ?? (command.hasPrefix("/") ? command : nil) else {
            let message = "找不到命令：\(command)"
            log?("❌ " + message)
            return Result(code: 127, out: "", err: message)
        }
        log?("$ \(command) \(arguments.joined(separator: " "))")

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                if let cwd { process.currentDirectoryURL = cwd }
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = (searchPaths + [env["PATH"] ?? ""]).joined(separator: ":")
                process.environment = env

                let outPipe = Pipe(), errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: Result(
                        code: 127, out: "", err: "启动失败：\(error.localizedDescription)"))
                    return
                }

                // 超时保护：卡住的转换不能把界面拖死
                let deadline = DispatchTime.now() + timeout
                let watchdog = DispatchWorkItem {
                    if process.isRunning { process.terminate() }
                }
                DispatchQueue.global().asyncAfter(deadline: deadline, execute: watchdog)

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()

                let result = Result(
                    code: process.terminationStatus,
                    out: String(data: outData, encoding: .utf8) ?? "",
                    err: String(data: errData, encoding: .utf8) ?? "")
                if let log {
                    for line in result.text.components(separatedBy: "\n")
                    where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                        log(line)
                    }
                }
                continuation.resume(returning: result)
            }
        }
    }
}
#endif
