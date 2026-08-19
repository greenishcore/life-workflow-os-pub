import Foundation

#if os(macOS)
/// Git 版本归档：提交推送与里程碑发布。
///
/// 只在 macOS 提供：iOS 上 libgit2 生态破碎（SwiftGit2 无法为 iOS 编译），
/// 架构上由 Mac 端充当归档网关。
public enum GitService {

    public struct Status: Sendable {
        public var isRepo = false
        public var branch = ""
        public var changed: [String] = []
        public var ahead = 0
        public var behind = 0
        public var remote = ""
        public var lastCommit = ""
        public var dirty: Bool { !changed.isEmpty }

        public init() {}
    }

    public struct Commit: Sendable, Identifiable {
        public let hash: String
        public let when: String
        public let subject: String
        public var id: String { hash }
    }

    /// 从给定目录向上找最近的 git 仓库根（含 .git 的目录）。
    ///
    /// 比用 #filePath 推算可靠：#filePath 是编译期常量，
    /// 应用一旦被移动或在别的机器上构建就会指向不存在的路径。
    public static func findRepository(startingAt url: URL) -> URL? {
        var current = url.standardizedFileURL
        for _ in 0..<12 {
            let dotGit = current.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: dotGit.path) { return current }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    public static func status(repo: URL) async -> Status {
        var s = Status()
        guard ProcessRunner.have("git") else { return s }
        guard await ProcessRunner.run("git", ["rev-parse", "--is-inside-work-tree"],
                                      cwd: repo, timeout: 15).ok else { return s }
        s.isRepo = true
        s.branch = await line("git", ["rev-parse", "--abbrev-ref", "HEAD"], repo)
        // core.quotepath=false：否则中文文件名会显示成 \346\227\266 这样的八进制转义
        let porcelain = await ProcessRunner.run(
            "git", ["-c", "core.quotepath=false", "status", "--porcelain"], cwd: repo, timeout: 30)
        s.changed = porcelain.out.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        s.remote = await line("git", ["remote", "get-url", "origin"], repo)
        s.lastCommit = await line("git", ["log", "-1", "--pretty=%h %s (%cr)"], repo)

        let counts = await ProcessRunner.run(
            "git", ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"],
            cwd: repo, timeout: 20)
        let parts = counts.out.split(separator: " ").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if counts.ok, parts.count == 2 { s.behind = parts[0]; s.ahead = parts[1] }
        return s
    }

    public static func history(repo: URL, limit: Int = 30) async -> [Commit] {
        let result = await ProcessRunner.run(
            "git", ["log", "-\(limit)", "--pretty=%h\u{1f}%cr\u{1f}%s"], cwd: repo, timeout: 30)
        return result.out.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\u{1f}")
            guard parts.count == 3 else { return nil }
            return Commit(hash: parts[0], when: parts[1], subject: parts[2])
        }
    }

    public static func sync(
        repo: URL, message: String, push: Bool = true,
        log: (@Sendable (String) -> Void)? = nil
    ) async -> (ok: Bool, message: String) {
        guard ProcessRunner.have("git") else { return (false, "未安装 git") }
        _ = await ProcessRunner.run("git", ["pull", "--rebase", "--autostash"],
                                    cwd: repo, timeout: 180, log: log)
        _ = await ProcessRunner.run("git", ["add", "-A"], cwd: repo, timeout: 60, log: log)

        let staged = await ProcessRunner.run("git", ["diff", "--cached", "--quiet"],
                                             cwd: repo, timeout: 30)
        if staged.ok { return (true, "无变更，跳过提交") }

        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = text.isEmpty ? "auto: \(DateOnly.today()) 工作流同步" : text
        let commit = await ProcessRunner.run("git", ["commit", "-m", final],
                                             cwd: repo, timeout: 60, log: log)
        guard commit.ok else { return (false, commit.text.isEmpty ? "提交失败" : commit.text) }
        guard push else { return (true, "已提交（未推送）：\(final)") }

        let pushed = await ProcessRunner.run("git", ["push"], cwd: repo, timeout: 180, log: log)
        guard pushed.ok else { return (false, "已提交但推送失败：\(pushed.text)") }
        return (true, "已提交并推送：\(final)")
    }

    public static func tags(repo: URL) async -> [String] {
        let result = await ProcessRunner.run("git", ["tag", "--sort=-v:refname"],
                                             cwd: repo, timeout: 30)
        return result.out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    public static func release(
        repo: URL, version: String, notes: String,
        log: (@Sendable (String) -> Void)? = nil
    ) async -> (ok: Bool, message: String) {
        let v = version.trimmingCharacters(in: .whitespaces)
        guard isSemver(v) else { return (false, "版本号需形如 v0.2.0（语义化版本）") }
        if await tags(repo: repo).contains(v) { return (false, "标签 \(v) 已存在") }

        let text = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = text.isEmpty ? "\(v) 阶段成果" : text

        let tag = await ProcessRunner.run("git", ["tag", "-a", v, "-m", final],
                                          cwd: repo, timeout: 60, log: log)
        guard tag.ok else { return (false, tag.text.isEmpty ? "打标签失败" : tag.text) }

        let push = await ProcessRunner.run("git", ["push", "origin", v],
                                           cwd: repo, timeout: 180, log: log)
        guard push.ok else { return (false, "标签已创建但推送失败：\(push.text)") }
        guard ProcessRunner.have("gh") else {
            return (true, "标签 \(v) 已推送（未安装 gh，跳过 release）")
        }
        let rel = await ProcessRunner.run(
            "gh", ["release", "create", v, "--title", v, "--notes", final],
            cwd: repo, timeout: 180, log: log)
        guard rel.ok else { return (false, "标签已推送但 release 创建失败：\(rel.text)") }
        return (true, "已发布里程碑 \(v)")
    }

    /// vX.Y.Z
    static func isSemver(_ s: String) -> Bool {
        guard s.hasPrefix("v") else { return false }
        let parts = s.dropFirst().split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    private static func line(_ cmd: String, _ args: [String], _ cwd: URL) async -> String {
        await ProcessRunner.run(cmd, args, cwd: cwd, timeout: 15).out
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
