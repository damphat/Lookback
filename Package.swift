// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Lookback",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Lookback", path: "Sources/Lookback")
    ]
)
