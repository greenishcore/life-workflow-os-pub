import Foundation
import LifeWorkflowKit

/// 架构地图数据的生成器。
///
/// 用法：
///   archmap-tool --repo <仓库根> [--out docs/02-architecture/archmap.json] [--check]
///   archmap-tool --bench [--repo <仓库根>]      跑热路径基准并追加到 logs/bench.jsonl
///
/// `--check` 只校验不写文件。任一硬约束被违反即以非零退出码结束，
/// 这正是把「文档里的散文」变成「CI 门禁」的那一步。
struct Tool {
    static func main() async {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let checkOnly = args.contains("--check")
        if args.contains("--bench") {
            await runBenchmarks(repo: URL(fileURLWithPath:
                value("--repo") ?? FileManager.default.currentDirectoryPath).standardizedFileURL)
            return
        }
        let repo = URL(fileURLWithPath: value("--repo") ?? FileManager.default.currentDirectoryPath)
            .standardizedFileURL

        let result: ArchExtractor.Result
        do {
            result = try ArchExtractor.extract(repoRoot: repo)
        } catch {
            fail("提取失败：\(error.localizedDescription)")
        }
        let model = result.model

        print("仓库：\(repo.path)")
        print("模块 \(model.modules.count) 个 · 依赖边 \(model.edges.count) 条 · "
              + "数据产物 \(model.artifacts.count) 个 · 源文件 \(model.modules.reduce(0) { $0 + $1.fileCount }) 个")

        if !result.uncoveredPaths.isEmpty {
            print("\n⚠️ 地图未覆盖的目录（LayerRules 里没登记）：")
            for path in result.uncoveredPaths { print("   · \(path)") }
        }

        print("\n约束校验：")
        var blocking = 0
        for inv in model.invariants {
            let mark = inv.passed ? "✅" : (inv.severity == .blocking ? "❌" : "⚠️")
            print("  \(mark) [\(inv.severity.label)] \(inv.title)"
                  + (inv.passed ? "" : "  —— \(inv.violations.count) 处"))
            for v in inv.violations {
                let where_ = v.line > 0 ? "\(v.file):\(v.line)" : v.file
                print("        \(where_)  \(v.detail)")
            }
            if !inv.passed, inv.severity == .blocking { blocking += inv.violations.count }
        }

        if !checkOnly {
            let out = URL(fileURLWithPath: value("--out")
                          ?? repo.appendingPathComponent("docs/02-architecture/archmap.json").path)
            do {
                let data = try model.encoded()
                try FileManager.default.createDirectory(
                    at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: out, options: .atomic)
                print("\n已写入 \(out.path)（\(data.count) 字节）")
            } catch {
                fail("写入失败：\(error.localizedDescription)")
            }
        }

        if blocking > 0 {
            FileHandle.standardError.write(Data("\n❌ 有 \(blocking) 处硬约束违例，构建应当失败\n".utf8))
            exit(1)
        }
        print("\n✅ 硬约束全部通过")
    }

    /// 跑基准并追加时间序列。结果不入 archmap.json —— 那份要求确定性，基准每次都不同。
    static func runBenchmarks(repo: URL) async {
        let results = await Benchmarks.runAll()
        print("热路径基准：")
        for r in results {
            let mark = r.overBudget ? "⚠️" : "✅"
            print(String(format: "  %@ %-18@ %8.3f %@（预算 %.2f，%.0f%%）",
                         mark, r.name as NSString, r.value, r.unit as NSString,
                         r.budget, r.ratio * 100))
            if !r.detail.isEmpty { print("       \(r.detail)") }
        }

        var config = AppConfig.load()
        config.logsPath = repo.appendingPathComponent("logs").path
        do {
            let url = try Benchmarks.append(.init(results: results), config: config)
            print("\n已追加 → \(url.path)")
        } catch {
            fail("写入失败：\(error.localizedDescription)")
        }
        if results.contains(where: \.overBudget) {
            FileHandle.standardError.write(Data("\n⚠️ 有指标超出预算\n".utf8))
        }
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("❌ \(message)\n".utf8))
        exit(2)
    }
}

await Tool.main()
