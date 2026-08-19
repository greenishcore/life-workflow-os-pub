import CryptoKit
import Foundation

#if os(macOS)
/// 格式互转 pipeline（算力经济层）。
///
/// 统一路径：任意格式 → Markdown（中间态，带缓存）→ 目标格式。
/// 缓存键 = sha256(输入文件) + 转换器版本，命中即复用，省掉重复的 OCR / 模型调用。
public enum ConvertService {

    public enum Target: String, CaseIterable, Sendable {
        case md, pdf, docx, html
        public var label: String {
            switch self {
            case .md: "Markdown（中间态）"
            case .pdf: "PDF"
            case .docx: "Word"
            case .html: "HTML"
            }
        }
    }

    public struct Outcome: Sendable {
        public let ok: Bool
        public let output: URL?
        public let markdown: URL?
        public let cached: Bool
        public let message: String
    }

    public struct ToolStatus: Sendable, Identifiable {
        public let name: String
        public let installed: Bool
        public let detail: String
        public var id: String { name }
    }

    static let chromeCandidates = [
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
        "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    ]

    public static func chromePath() -> String? {
        chromeCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// 「任意 → Markdown」的转换器，优先 markitdown（覆盖面广）
    public static func markdownTool() -> String? {
        if ProcessRunner.have("markitdown") { return "markitdown" }
        if ProcessRunner.have("pandoc") { return "pandoc" }
        return nil
    }

    /// 依赖体检：缺哪个装哪个，不影响其它功能
    public static func toolStatus() -> [ToolStatus] {
        let specs = [
            ("markitdown", "任意格式 → Markdown（推荐）", "pipx install markitdown"),
            ("pandoc", "Markdown ↔ docx/html/pdf 的主力", "brew install pandoc"),
            ("xelatex", "生成中文 PDF", "brew install --cask basictex"),
            ("ocrmypdf", "扫描件 OCR", "brew install ocrmypdf"),
            ("tesseract", "OCR 引擎", "brew install tesseract"),
            ("git", "版本归档", "系统自带"),
            ("gh", "GitHub release", "brew install gh"),
        ]
        var out = specs.map { name, desc, install -> ToolStatus in
            if let path = ProcessRunner.which(name) {
                return ToolStatus(name: name, installed: true, detail: path)
            }
            return ToolStatus(name: name, installed: false, detail: "\(desc) · \(install)")
        }
        out.append(ToolStatus(name: "chrome", installed: chromePath() != nil,
                              detail: chromePath() ?? "PDF 备用渲染引擎"))
        return out
    }

    // MARK: pipeline

    public static func convert(
        source: URL,
        to target: Target,
        output: URL? = nil,
        config: AppConfig,
        log: (@Sendable (String) -> Void)? = nil
    ) async -> Outcome {
        let (mdURL, cached, message) = await toMarkdown(source: source, config: config, log: log)
        guard let mdURL else {
            return Outcome(ok: false, output: nil, markdown: nil, cached: cached, message: message)
        }
        log?("  → 中间态：\(mdURL.path)")

        let outDir = config.cacheURL.deletingLastPathComponent().appendingPathComponent("out")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        if target == .md {
            let dest = output ?? mdURL
            if dest != mdURL { try? FileManager.default.copyItem(at: mdURL, to: dest) }
            return Outcome(ok: true, output: dest, markdown: mdURL, cached: cached,
                           message: "完成（Markdown 中间态）")
        }

        let dest = output ?? outDir.appendingPathComponent(
            "\(source.deletingPathExtension().lastPathComponent).\(target.rawValue)")
        try? FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

        let result: ProcessRunner.Result
        switch target {
        case .md:
            fatalError("unreachable")
        case .pdf:
            if ProcessRunner.have("xelatex"), ProcessRunner.have("pandoc") {
                log?("[to-pdf] pandoc + xelatex")
                result = await ProcessRunner.run("pandoc", [
                    mdURL.path, "-o", dest.path, "--pdf-engine=xelatex",
                    "-V", "CJKmainfont=PingFang SC", "-V", "geometry:margin=2cm",
                ], timeout: 900, log: log)
            } else if let chrome = chromePath(), ProcessRunner.have("pandoc") {
                log?("[to-pdf] Chrome headless（未装 xelatex，自动降级）")
                let tmpHTML = dest.deletingPathExtension().appendingPathExtension("tmp.html")
                let html = await ProcessRunner.run("pandoc", [
                    mdURL.path, "-f", "gfm", "-t", "html", "--standalone", "-o", tmpHTML.path,
                ], timeout: 300, log: log)
                guard html.ok else {
                    return Outcome(ok: false, output: nil, markdown: mdURL, cached: cached,
                                   message: "生成中间 HTML 失败")
                }
                result = await ProcessRunner.run(chrome, [
                    "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                    "--print-to-pdf=\(dest.path)", tmpHTML.absoluteString,
                ], timeout: 300, log: log)
                try? FileManager.default.removeItem(at: tmpHTML)
            } else {
                return Outcome(ok: false, output: nil, markdown: mdURL, cached: cached,
                               message: "生成 PDF 需要 pandoc + xelatex（brew install --cask basictex）或 Chrome")
            }
        case .docx:
            guard ProcessRunner.have("pandoc") else {
                return Outcome(ok: false, output: nil, markdown: mdURL, cached: cached,
                               message: "生成 docx 需要 pandoc（brew install pandoc）")
            }
            result = await ProcessRunner.run(
                "pandoc", [mdURL.path, "-o", dest.path, "-f", "gfm", "-t", "docx"],
                timeout: 300, log: log)
        case .html:
            guard ProcessRunner.have("pandoc") else {
                return Outcome(ok: false, output: nil, markdown: mdURL, cached: cached,
                               message: "生成 html 需要 pandoc（brew install pandoc）")
            }
            result = await ProcessRunner.run(
                "pandoc", [mdURL.path, "-o", dest.path, "-f", "gfm", "-t", "html", "--standalone"],
                timeout: 300, log: log)
        }

        guard result.ok, FileManager.default.fileExists(atPath: dest.path) else {
            return Outcome(ok: false, output: nil, markdown: mdURL, cached: cached,
                           message: "生成 \(target.rawValue) 失败：\(result.text)")
        }
        return Outcome(ok: true, output: dest, markdown: mdURL, cached: cached,
                       message: "完成 → \(dest.lastPathComponent)")
    }

    /// 第 1 步：任意 → Markdown（命中缓存则秒回）
    static func toMarkdown(
        source: URL, config: AppConfig, log: (@Sendable (String) -> Void)?
    ) async -> (URL?, Bool, String) {
        guard FileManager.default.fileExists(atPath: source.path) else {
            return (nil, false, "文件不存在：\(source.path)")
        }
        let ext = source.pathExtension.lowercased()
        if ext == "md" || ext == "markdown" {
            log?("[is-md] 输入已是 Markdown，跳过转换")
            return (source, true, "输入已是 Markdown")
        }
        guard let tool = markdownTool() else {
            return (nil, false, "需要 markitdown 或 pandoc（brew install pandoc / pipx install markitdown）")
        }

        let cacheDir = config.cacheURL
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let mdDir = cacheDir.deletingLastPathComponent().appendingPathComponent("md")
        try? FileManager.default.createDirectory(at: mdDir, withIntermediateDirectories: true)

        guard let digest = sha256(of: source) else {
            return (nil, false, "无法读取输入文件")
        }
        let version = await converterVersion(tool)
        let cacheFile = cacheDir.appendingPathComponent("\(digest)-\(version).md")
        let mdFile = mdDir.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent).md")

        if let size = try? cacheFile.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 {
            log?("[cache-hit] \(source.lastPathComponent)（跳过重复计算）")
            try? FileManager.default.removeItem(at: mdFile)
            try? FileManager.default.copyItem(at: cacheFile, to: mdFile)
            return (mdFile, true, "命中缓存")
        }

        log?("[to-md] \(tool) \(source.lastPathComponent)")
        let tmp = cacheDir.appendingPathComponent(".tmp-\(UUID().uuidString.prefix(8)).md")
        let result: ProcessRunner.Result
        if tool == "markitdown" {
            result = await ProcessRunner.run("markitdown", [source.path], timeout: 600)
            if result.ok, !result.out.isEmpty { try? result.out.write(to: tmp, atomically: true, encoding: .utf8) }
        } else {
            result = await ProcessRunner.run("pandoc", [
                source.path, "-f", ext, "-t", "gfm",
                "--extract-media", mdDir.appendingPathComponent("media").path, "-o", tmp.path,
            ], timeout: 600, log: log)
        }

        guard let size = try? tmp.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
            try? FileManager.default.removeItem(at: tmp)
            return (nil, false, "转换失败或结果为空：\(source.lastPathComponent)\n\(result.err)")
        }
        _ = try? FileManager.default.replaceItemAt(cacheFile, withItemAt: tmp)
        try? FileManager.default.removeItem(at: mdFile)
        try? FileManager.default.copyItem(at: cacheFile, to: mdFile)
        return (mdFile, false, "转换完成")
    }

    // MARK: 缓存

    public static func cacheStats(config: AppConfig) -> (count: Int, bytes: Int) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: config.cacheURL, includingPropertiesForKeys: [.fileSizeKey]) else { return (0, 0) }
        let mds = files.filter { $0.pathExtension == "md" && !$0.lastPathComponent.hasPrefix(".tmp") }
        let bytes = mds.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return (mds.count, bytes)
    }

    @discardableResult
    public static func clearCache(config: AppConfig) -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: config.cacheURL, includingPropertiesForKeys: nil) else { return 0 }
        var n = 0
        for f in files where f.pathExtension == "md" {
            try? FileManager.default.removeItem(at: f)
            n += 1
        }
        return n
    }

    // MARK: 私有

    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func converterVersion(_ tool: String) async -> String {
        let result = await ProcessRunner.run(tool, ["--version"], timeout: 20)
        let first = result.out.components(separatedBy: "\n").first ?? "0"
        return "\(tool)-\(first.replacingOccurrences(of: " ", with: "_"))"
    }
}
#endif
