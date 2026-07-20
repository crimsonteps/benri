// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "valuet",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "QuickVaultCore", targets: ["QuickVaultCore"]),
        .executable(name: "valuet", targets: ["QuickVault"]),
        .executable(name: "QuickVaultChecks", targets: ["QuickVaultChecks"])
    ],
    targets: [
        .target(name: "QuickVaultCore"),
        .executableTarget(
            name: "QuickVault",
            dependencies: ["QuickVaultCore"]
        ),
        .executableTarget(
            name: "QuickVaultChecks",
            dependencies: ["QuickVaultCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
