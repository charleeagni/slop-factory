// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SlopFactory",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FactoryCore", targets: ["FactoryCore"]),
        .executable(name: "SlopFactory", targets: ["SlopFactory"]),
    ],
    targets: [
        .target(name: "FactoryCore", resources: [.process("Resources")]),
        .executableTarget(name: "SlopFactory", dependencies: ["FactoryCore"]),
        .testTarget(name: "FactoryCoreTests", dependencies: ["FactoryCore"]),
    ]
)
