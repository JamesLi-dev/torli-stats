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
    targets: [
        .target(
            name: "TorliStatsShared",
            path: "Sources/TorliStatsShared"
        ),
        .executableTarget(
            name: "TorliStats",
            dependencies: ["TorliStatsShared"],
            path: "Sources/TorliStats",
            resources: [
                .process("NotesResources")
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
