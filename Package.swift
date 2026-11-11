// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build SparkleSFTP.

import PackageDescription

let package = Package(
    name: "SparkleSFTP",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SparkleSFTP", targets: ["SparkleSFTP"]),
        .library(name: "SparkleCore", targets: ["SparkleCore"]),
        .library(name: "SparkleSecurity", targets: ["SparkleSecurity"]),
        .library(name: "SparklePersistence", targets: ["SparklePersistence"]),
        .library(name: "SparkleNetworking", targets: ["SparkleNetworking"]),
        .library(name: "SparkleTransferEngine", targets: ["SparkleTransferEngine"]),
        .library(name: "SparkleFileManager", targets: ["SparkleFileManager"]),
        .library(name: "SparkleTerminal", targets: ["SparkleTerminal"]),
        .library(name: "SparkleSynchronization", targets: ["SparkleSynchronization"]),
        .library(name: "SparkleDesignSystem", targets: ["SparkleDesignSystem"]),
        .library(name: "SparkleFeatures", targets: ["SparkleFeatures"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio-ssh.git", "0.15.1" ..< "0.16.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.12.3"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", "1.19.0" ..< "1.99.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", "2.10.1" ..< "3.0.0")
    ],
    targets: [
        .target(
            name: "Clibcurl",
            path: "Packages/Clibcurl",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("curl")
            ]
        ),
        .target(
            name: "SparkleCore",
            path: "Packages/Core"
        ),
        .target(
            name: "SparkleSecurity",
            dependencies: [
                "SparkleCore",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh")
            ],
            path: "Packages/Security"
        ),
        .target(
            name: "SparklePersistence",
            dependencies: [
                "SparkleCore"
            ],
            path: "Packages/Persistence",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "SparkleNetworking",
            dependencies: [
                "Clibcurl",
                "SparkleCore",
                "SparkleSecurity",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh")
            ],
            path: "Packages/Networking"
        ),
        .target(
            name: "SparkleTransferEngine",
            dependencies: [
                "SparkleCore",
                "SparkleSecurity",
                .product(name: "Crypto", package: "swift-crypto")
            ],
            path: "Packages/TransferEngine"
        ),
        .target(
            name: "SparkleFileManager",
            dependencies: [
                "SparkleCore",
                "SparkleSecurity"
            ],
            path: "Packages/FileManager"
        ),
        .target(
            name: "SparkleTerminal",
            dependencies: [
                "SparkleCore",
                "SparkleNetworking",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Packages/Terminal"
        ),
        .target(
            name: "SparkleSynchronization",
            dependencies: [
                "SparkleCore",
                "SparkleSecurity",
                "SparkleTransferEngine",
                .product(name: "Crypto", package: "swift-crypto")
            ],
            path: "Packages/Synchronization"
        ),
        .target(
            name: "SparkleDesignSystem",
            dependencies: [
                "SparkleCore"
            ],
            path: "Packages/DesignSystem"
        ),
        .target(
            name: "SparkleFeatures",
            dependencies: [
                "SparkleCore",
                "SparkleDesignSystem",
                "SparkleFileManager",
                "SparkleNetworking",
                "SparklePersistence",
                "SparkleSecurity",
                "SparkleSynchronization",
                "SparkleTerminal",
                "SparkleTransferEngine"
            ],
            path: "Features"
        ),
        .executableTarget(
            name: "SparkleSFTP",
            dependencies: [
                "SparkleCore",
                "SparkleDesignSystem",
                "SparkleFeatures",
                "SparklePersistence",
                "SparkleSecurity",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "App",
            exclude: [
                "Resources/Info.plist",
                "SparkleSFTP.entitlements"
            ],
            resources: [
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/AppIcon.png")
            ]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: [
                "SparkleCore",
                "SparkleDesignSystem"
            ],
            path: "Tests/CoreTests"
        ),
        .testTarget(
            name: "SecurityTests",
            dependencies: [
                "SparkleCore",
                "SparkleSecurity",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "NIOSSH", package: "swift-nio-ssh")
            ],
            path: "Tests/SecurityTests"
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: [
                "SparkleCore",
                "SparklePersistence"
            ],
            path: "Tests/PersistenceTests"
        ),
        .testTarget(
            name: "NetworkingTests",
            dependencies: [
                "SparkleCore",
                "SparkleNetworking",
                "SparkleSecurity",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOEmbedded", package: "swift-nio")
            ],
            path: "Tests/NetworkingTests"
        ),
        .testTarget(
            name: "TransferEngineTests",
            dependencies: [
                "SparkleCore",
                "SparkleTransferEngine",
                .product(name: "Crypto", package: "swift-crypto")
            ],
            path: "Tests/TransferEngineTests"
        ),
        .testTarget(
            name: "FileManagerTests",
            dependencies: [
                "SparkleCore",
                "SparkleFileManager"
            ],
            path: "Tests/FileManagerTests"
        ),
        .testTarget(
            name: "SynchronizationTests",
            dependencies: [
                "SparkleCore",
                "SparkleSynchronization"
            ],
            path: "Tests/SynchronizationTests"
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: [
                "SparkleCore",
                "SparkleFeatures",
                "SparkleFileManager",
                "SparkleNetworking",
                "SparklePersistence",
                "SparkleSecurity",
                "SparkleSynchronization",
                "SparkleTerminal",
                "SparkleTransferEngine",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh")
            ],
            path: "Tests/IntegrationTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
