// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Benri",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "BenriCore", targets: ["BenriCore"]),
        .executable(name: "Benri", targets: ["Benri"]),
        .executable(name: "BenriChecks", targets: ["BenriChecks"])
    ],
    targets: [
        .target(
            name: "BenriCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Benri",
            dependencies: ["BenriCore"]
        ),
        .executableTarget(
            name: "BenriChecks",
            dependencies: ["BenriCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
