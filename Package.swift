// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Keys",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Keys",
            resources: [.copy("Resources")]
        )
    ]
)
