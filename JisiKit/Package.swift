// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "JisiKit",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "JisiKit", targets: ["JisiKit"]),
        /// 手表 App、手表小组件只用这个（同步消息、倒计时、头像），不编整个 JisiKit
        .library(name: "JisiWatchKit", targets: ["JisiWatchKit"]),
    ],
    targets: [
        .target(name: "JisiKit", dependencies: ["JisiWatchKit"], resources: [.process("Resources")]),
        .target(name: "JisiWatchKit", resources: [.process("Resources")]),
        .testTarget(name: "JisiKitTests", dependencies: ["JisiKit", "JisiWatchKit"]),
    ]
)
