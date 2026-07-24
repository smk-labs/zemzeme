// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "zemzeme",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "zemzeme",
            path: ".",
            swiftSettings: [.unsafeFlags(["-swift-version", "5"])]
        )
    ]
)
