// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "BookScoutCore", platforms: [.macOS(.v14)],
    products: [.library(name: "BookScoutCore", targets: ["BookScoutCore"])],
    targets: [
        .target(name: "BookScoutCore", path: "BookScout", exclude: ["BookScoutApp.swift"]),
        .testTarget(name: "BookScoutCoreTests", dependencies: ["BookScoutCore"])
    ]
)
