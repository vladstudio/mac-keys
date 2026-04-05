// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Keys",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../mac-app-kit"),
    ],
    targets: [
        .executableTarget(
            name: "Keys",
            dependencies: [.product(name: "MacAppKit", package: "mac-app-kit")],
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
