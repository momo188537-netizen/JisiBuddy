// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "JisiKit",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "JisiKit", targets: ["JisiKit"]),
    ],
    targets: [
        .target(name: "JisiKit", resources: [.process("Resources")]),
        .testTarget(name: "JisiKitTests", dependencies: ["JisiKit"]),
    ]
)
