// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AvgeekAppleDesignSystem",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "AvgeekDesignSystem", targets: ["AvgeekDesignSystem"]),
        .library(name: "AvgeekDesignSystemCatalog", targets: ["AvgeekDesignSystemCatalog"]),
    ],
    dependencies: [
        .package(path: "../apple-foundations"),
    ],
    targets: [
        .target(
            name: "AvgeekDesignSystem",
            dependencies: [
                .product(name: "AvgeekLocalizationCore", package: "apple-foundations"),
                .product(name: "AvgeekLocalizationUI", package: "apple-foundations"),
            ]
        ),
        .target(
            name: "AvgeekDesignSystemCatalog",
            dependencies: ["AvgeekDesignSystem"]
        ),
        .testTarget(
            name: "AvgeekDesignSystemTests",
            dependencies: [
                "AvgeekDesignSystem",
                "AvgeekDesignSystemCatalog",
                .product(name: "AvgeekLocalizationCore", package: "apple-foundations"),
            ],
            resources: [.process("Resources")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
