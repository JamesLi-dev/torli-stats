// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TorliStats",
    platforms: [
        .macOS(.v13)
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
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
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
