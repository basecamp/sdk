// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ConformanceRunner",
    platforms: [
        .macOS(.v12),
    ],
    dependencies: [
        .package(path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ConformanceRunner",
            dependencies: [
                .product(name: "Basecamp", package: "basecamp-sdk"),
            ],
            path: "Sources/ConformanceRunner",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
