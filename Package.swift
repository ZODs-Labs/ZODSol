// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ZODSol",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "ZODSol", targets: ["ZODSol"]),
        .library(name: "SolanaKit", targets: ["SolanaKit"]),
        .library(name: "SolanaRPC", targets: ["SolanaRPC"]),
        .library(name: "KeychainKit", targets: ["KeychainKit"]),
        .library(name: "Formatters", targets: ["Formatters"]),
        .library(name: "Caching", targets: ["Caching"]),
        .library(name: "HeliusProvider", targets: ["HeliusProvider"]),
        .library(name: "WalletOverviewDomain", targets: ["WalletOverviewDomain"]),
        .library(name: "WalletOverviewUI", targets: ["WalletOverviewUI"]),
    ],
    targets: [
        .executableTarget(
            name: "ZODSol",
            dependencies: [
                "WalletOverviewUI",
                "WalletOverviewDomain",
                "HeliusProvider",
                "KeychainKit",
            ],
            path: "Sources/ZODSol",
            exclude: ["ZODSol.entitlements"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny"),
            ]),
        .testTarget(
            name: "ZODSolTests",
            dependencies: ["ZODSol"],
            path: "Tests/ZODSolTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]),

        // MARK: - SolanaKit

        .target(
            name: "SolanaKit",
            path: "Sources/SolanaKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny"),
            ]),
        .testTarget(
            name: "SolanaKitTests",
            dependencies: ["SolanaKit"],
            path: "Tests/SolanaKitTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]),

        // MARK: - SolanaRPC

        .target(
            name: "SolanaRPC",
            path: "Sources/SolanaRPC",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny"),
            ]),
        .testTarget(
            name: "SolanaRPCTests",
            dependencies: ["SolanaRPC"],
            path: "Tests/SolanaRPCTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]),

        // MARK: - KeychainKit

        .target(
            name: "KeychainKit",
            path: "Sources/KeychainKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny"),
            ]),
        .testTarget(
            name: "KeychainKitTests",
            dependencies: ["KeychainKit"],
            path: "Tests/KeychainKitTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]),

        // MARK: - Formatters

        .target(
            name: "Formatters",
            dependencies: ["SolanaKit"],
            path: "Sources/Formatters",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny"),
            ]),
        .testTarget(
            name: "FormattersTests",
            dependencies: ["Formatters"],
            path: "Tests/FormattersTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]),

        // MARK: - Caching

        .target(
            name: "Caching",
            path: "Sources/Caching",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny"),
            ]),
        .testTarget(
            name: "CachingTests",
            dependencies: ["Caching"],
            path: "Tests/CachingTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]),

        // MARK: - HeliusProvider

        .target(
            name: "HeliusProvider",
            dependencies: ["SolanaKit", "SolanaRPC", "KeychainKit"],
            path: "Sources/HeliusProvider",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny"),
            ]),
        .testTarget(
            name: "HeliusProviderTests",
            dependencies: ["HeliusProvider"],
            path: "Tests/HeliusProviderTests",
            exclude: ["Fixtures"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]),

        // MARK: - WalletOverviewDomain

        .target(
            name: "WalletOverviewDomain",
            dependencies: ["SolanaKit", "SolanaRPC", "KeychainKit", "Caching"],
            path: "Sources/WalletOverviewDomain",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny"),
            ]),
        .testTarget(
            name: "WalletOverviewDomainTests",
            dependencies: ["WalletOverviewDomain", "SolanaRPC"],
            path: "Tests/WalletOverviewDomainTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]),

        // MARK: - WalletOverviewUI

        .target(
            name: "WalletOverviewUI",
            dependencies: ["WalletOverviewDomain", "SolanaKit", "Formatters"],
            path: "Sources/WalletOverviewUI",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny"),
            ]),
        .testTarget(
            name: "WalletOverviewUITests",
            dependencies: ["WalletOverviewUI"],
            path: "Tests/WalletOverviewUITests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
    ])
