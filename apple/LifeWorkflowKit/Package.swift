// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LifeWorkflowKit",
    // watchOS 保留在平台列表里：M4 暂缓但不排除，等付费账号就位可直接编译。
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "LifeWorkflowKit", targets: ["LifeWorkflowKit"])
    ],
    targets: [
        .target(
            name: "LifeWorkflowKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LifeWorkflowKitTests",
            dependencies: ["LifeWorkflowKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
