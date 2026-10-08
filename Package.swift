// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DNSDeckMCP",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "DNSDeckMCP", targets: ["DNSDeckMCP"]),
    ],
    dependencies: [
        .package(name: "AvgeekAppleFoundations", path: "packages/apple-foundations"),
    ],
    targets: [
        .executableTarget(
            name: "DNSDeckMCP",
            dependencies: [
                .product(name: "AvgeekLocalizationCore", package: "AvgeekAppleFoundations"),
                .product(name: "AvgeekNetworking", package: "AvgeekAppleFoundations"),
            ],
            path: ".",
            exclude: [
                "AGENTS.md",
                "Tests",
                "build",
                "node_modules",
                "Config",
                "docs",
                "packages",
                "LICENSE",
                "package.json",
                "package-lock.json",
                "DNSDeck.xcodeproj",
                "DNSDeck/AppIcon.icon",
                "DNSDeck/App",
                "DNSDeck/Assets.xcassets",
                "DNSDeck/Common/ErrorHandling/ErrorHandler.swift",
                "DNSDeck/Common/Extensions/Notification+Extensions.swift",
                "DNSDeck/Common/Utilities/BINDParser.swift",
                "DNSDeck/Common/Utilities/BulkReplaceEngine.swift",
                "DNSDeck/Common/Utilities/CSVParser.swift",
                "DNSDeck/Common/Utilities/DateFormatter+Extensions.swift",
                "DNSDeck/Common/Utilities/DNSRecordHelpers.swift",
                "DNSDeck/Common/Utilities/DebouncedSearch.swift",
                "DNSDeck/Common/Utilities/RecordConversionMap.swift",
                "DNSDeck/Common/Utilities/SearchFilter.swift",
                "DNSDeck/DNSDeck-iOS.entitlements",
                "DNSDeck/DNSDeck-macOS.entitlements",
                "DNSDeck/Localizable.xcstrings",
                "DNSDeck/Model/InlineRecord.swift",
                "DNSDeck/PrivacyInfo.xcprivacy",
                "DNSDeck/Services/Cache",
                "DNSDeck/Services/EnvironmentManager.swift",
                "DNSDeck/Services/SettingsManager.swift",
                "DNSDeck/UI",
                "DNSDeckUITests",
                "Makefile",
                "README.md",
                "scripts",
            ],
            sources: [
                "DNSDeck/Common/AppLocalization.swift",
                "DNSDeck/Common/Configuration.swift",
                "DNSDeck/Common/Constants.swift",
                "DNSDeck/Common/ErrorHandling/AppError.swift",
                "DNSDeck/Common/Extensions/String+Extensions.swift",
                "DNSDeck/Common/InputValidator.swift",
                "DNSDeck/Common/Logger.swift",
                "DNSDeck/Common/UITestConfiguration.swift",
                "DNSDeck/Common/Utilities/DNSRecordValidator.swift",
                "DNSDeck/Model/DNSEnvironment.swift",
                "DNSDeck/Model/DNSProvider.swift",
                "DNSDeck/Model/NormalizedDNSModels.swift",
                "DNSDeck/Model/NameserverUpdate.swift",
                "DNSDeck/Model/ProviderDefinition.swift",
                "DNSDeck/Model/ProviderDNSCodec.swift",
                "DNSDeck/Model/Providers",
                "DNSDeck/Model/ProviderZone.swift",
                "DNSDeck/Model/SupportedLanguage.swift",
                "DNSDeck/Services/KeychainTokenStore.swift",
                "DNSDeck/Services/NetworkConfiguration.swift",
                "DNSDeck/Services/NetworkTransport.swift",
                "DNSDeck/Services/ProviderCredentialStore.swift",
                "DNSDeck/Services/Providers",
                "DNSDeckMCP",
            ],
            resources: [
                .process("DNSDeck/Configuration.plist"),
                .process("DNSDeck/ProviderDefinitions.json"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "DNSDeckTests",
            dependencies: ["DNSDeckMCP"],
            path: "Tests/DNSDeckTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
