// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "PortHarbor",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PortHarborCore", targets: ["PortHarborCore"]),
        .library(name: "PortHarborDiscovery", targets: ["PortHarborDiscovery"]),
        .library(name: "PortHarborSafety", targets: ["PortHarborSafety"]),
        .library(name: "PortHarborTimeline", targets: ["PortHarborTimeline"]),
        .executable(name: "PortHarbor", targets: ["PortHarborApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0")
    ],
    targets: [
        .target(name: "PortHarborCore"),
        .target(
            name: "PortHarborDiscovery",
            dependencies: ["PortHarborCore"]
        ),
        .target(
            name: "PortHarborSafety",
            dependencies: ["PortHarborCore"]
        ),
        .target(
            name: "PortHarborTimeline",
            dependencies: ["PortHarborCore"]
        ),
        .executableTarget(
            name: "PortHarborApp",
            dependencies: [
                "PortHarborCore",
                "PortHarborDiscovery",
                "PortHarborSafety",
                "PortHarborTimeline",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PortHarborCoreTests",
            dependencies: ["PortHarborCore"]
        ),
        .testTarget(
            name: "PortHarborDiscoveryTests",
            dependencies: ["PortHarborCore", "PortHarborDiscovery"]
        ),
        .testTarget(
            name: "PortHarborSafetyTests",
            dependencies: ["PortHarborCore", "PortHarborSafety"]
        ),
        .testTarget(
            name: "PortHarborTimelineTests",
            dependencies: ["PortHarborCore", "PortHarborTimeline"]
        )
    ],
    swiftLanguageModes: [.v6]
)
