// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TorliStats",
    defaultLocalization: "en",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(name: "TorliStats", targets: ["TorliStats"]),
        .executable(name: "TorliStatsHelper", targets: ["TorliStatsHelper"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.8.0")
    ],
    targets: [
        .testTarget(
            name: "TorliStatsTests",
            dependencies: ["TorliStats"]
        ),
        .target(
            name: "TorliStatsShared",
            path: "Sources/TorliStatsShared"
        ),
        .executableTarget(
            name: "TorliStats",
            dependencies: [
                "TorliStatsShared",
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Sources/TorliStats",
            resources: [
                .process("NotesResources"),
                .process("StatsResources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "TorliStatsHelper",
            dependencies: ["TorliStatsShared"],
            path: "Sources/TorliStatsHelper",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        )
    ]
)
