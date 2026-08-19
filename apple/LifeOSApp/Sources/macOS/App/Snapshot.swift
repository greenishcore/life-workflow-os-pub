import AppKit
import SwiftUI
import LifeWorkflowKit

/// 离屏快照：`--snapshot <目录>` 启动时，把每个页面渲染成 PNG 后退出。
///
/// 为什么要有这个：macOS 应用没有 iOS 模拟器那样的无头截图手段，
/// 而用 screencapture + AppleScript 取窗口位置会触发「自动化」权限弹窗，
/// 在 CI 和自动化验证里都不可用。ImageRenderer 直接渲染视图树，
/// 既不需要权限也不需要真的显示窗口。
@MainActor
enum Snapshot {

    static var requestedDirectory: URL? {
        argument("--snapshot").map { URL(fileURLWithPath: $0) }
    }

    /// 快照专用 vault。必须显式指定：默认的 ~/Documents 会触发 macOS 的
    /// 文件访问权限弹窗，在无人值守的快照/CI 场景下会把进程卡死。
    static var requestedVault: URL? {
        argument("--vault").map { URL(fileURLWithPath: $0) }
    }

    private static func argument(_ name: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private static func log(_ s: String) {
        FileHandle.standardOutput.write(Data((s + "\n").utf8))
    }

    static func runIfRequested() {
        guard let dir = requestedDirectory else { return }
        log("[snapshot] 启动")
        Task { @MainActor in
            log("[snapshot] 任务开始")
            var override: AppConfig?
            if let vault = requestedVault {
                override = AppConfig(roots: [
                    .init(id: "local", path: vault.path, displayName: "本地")
                ], logsPath: vault.deletingLastPathComponent().appendingPathComponent("logs").path)
            }
            let state = AppState(config: override)
            await state.bootstrap()
            log("[snapshot] 数据就绪，\(state.items.count) 条记录")
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                for scheme in [ColorScheme.light, .dark] {
                    for dest in Destination.allCases {
                        try render(dest, state: state, scheme: scheme, into: dir)
                    }
                }
                FileHandle.standardOutput.write(Data("✅ 快照完成 → \(dir.path)\n".utf8))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("❌ 快照失败：\(error)\n".utf8))
                exit(1)
            }
        }
    }

    private static func render(
        _ dest: Destination, state: AppState, scheme: ColorScheme, into dir: URL
    ) throws {
        state.selection = dest
        let view = SnapshotFrame(destination: dest)
            .environment(state)
            .environment(\.colorScheme, scheme)
            .environment(\.isSnapshotting, true)
            // 画布给足高度：内容比窗口高时 ImageRenderer 会居中裁切，
            // 顶部的标题与 KPI 会被切掉
            .frame(width: 1180, height: 1500, alignment: .topLeading)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            throw SnapshotError.renderFailed(dest.rawValue)
        }
        let name = "\(dest.rawValue)-\(scheme == .dark ? "dark" : "light").png"
        try png.write(to: dir.appendingPathComponent(name))
        FileHandle.standardOutput.write(Data("  ✅ \(name)\n".utf8))
    }

    /// 页面内容 + 一条模拟侧边栏，用来近似真实观感但避开 NavigationSplitView
    private struct SnapshotFrame: View {
        let destination: Destination
        @Environment(AppState.self) private var state

        var body: some View {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Life Workflow OS").font(.system(size: 14, weight: .bold))
                    Text("捕捉 → 整理 → 执行 → 复盘 → 归档")
                        .font(.system(size: 10)).foregroundStyle(Theme.faint)
                    Divider().padding(.vertical, 8)
                    ForEach(NavGroup.allCases) { group in
                        if !group.title.isEmpty {
                            Text(group.title).font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.faint).padding(.top, 6)
                        }
                        ForEach(group.destinations) { d in
                            Label(d.title, systemImage: d.symbol)
                                .font(.system(size: 12))
                                .foregroundStyle(d == destination ? Theme.accent : .secondary)
                                .fontWeight(d == destination ? .semibold : .regular)
                                .padding(.vertical, 3)
                        }
                    }
                    Spacer()
                }
                .padding(14)
                .frame(width: 200, alignment: .leading)
                .background(Theme.cardBackground)

                Divider()
                page.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }

        @ViewBuilder private var page: some View {
            switch destination {
            case .dashboard: DashboardView()
            case .capture:   CaptureView()
            case .ideas:     IdeasView()
            case .convert:   ConvertView()
            case .prompts:   PromptsView()
            case .logs:      LogsView()
            case .archive:   ArchiveView()
            case .settings:  SettingsView()
            }
        }
    }

    enum SnapshotError: LocalizedError {
        case renderFailed(String)
        var errorDescription: String? {
            switch self {
            case .renderFailed(let page): "页面 \(page) 渲染失败"
            }
        }
    }
}
