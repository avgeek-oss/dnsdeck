// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AvgeekAppleFoundations",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "AvgeekLocalizationCore", targets: ["AvgeekLocalizationCore"]),
        .library(name: "AvgeekLocalizationUI", targets: ["AvgeekLocalizationUI"]),
        .library(name: "AvgeekNetworking", targets: ["AvgeekNetworking"]),
    ],
    targets: [
        .target(name: "AvgeekLocalizationCore"),
        .target(
            name: "AvgeekLocalizationUI",
            dependencies: ["AvgeekLocalizationCore"]
        ),
        .target(name: "AvgeekNetworking"),
        .testTarget(
            name: "AvgeekAppleFoundationsTests",
            dependencies: [
                "AvgeekLocalizationCore",
                "AvgeekLocalizationUI",
                "AvgeekNetworking",
            ],
            resources: [.copy("Fixtures/TestCatalog.bundle")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
