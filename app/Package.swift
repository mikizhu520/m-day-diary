// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RiJi",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RiJi",
            path: "Sources/RiJi",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
