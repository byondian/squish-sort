// swift-tools-version:5.9
import PackageDescription

// Game rules and policy, kept free of UIKit, SpriteKit and any SDK so they run
// in `swift test` on CI and in the level-check tool.
let package = Package(
    name: "SquishKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SquishCore", targets: ["SquishCore"]),
        .library(name: "SquishLevels", targets: ["SquishLevels"]),
        .library(name: "SquishPolicy", targets: ["SquishPolicy"]),
        .library(name: "SquishSoft", targets: ["SquishSoft"]),
        .library(name: "SquishWorkshop", targets: ["SquishWorkshop"]),
        .executable(name: "squish-levels", targets: ["squish-levels"]),
    ],
    targets: [
        .target(name: "SquishCore"),
        .target(name: "SquishLevels", dependencies: ["SquishCore"]),
        .target(name: "SquishWorkshop"),
        .target(name: "SquishPolicy", dependencies: ["SquishWorkshop"]),
        .target(name: "SquishSoft"),
        .executableTarget(name: "squish-levels", dependencies: ["SquishLevels"]),
        .testTarget(name: "SquishCoreTests", dependencies: ["SquishCore"]),
        .testTarget(name: "SquishLevelsTests", dependencies: ["SquishLevels", "SquishPolicy"]),
        .testTarget(name: "SquishPolicyTests", dependencies: ["SquishPolicy"]),
        .testTarget(name: "SquishSoftTests", dependencies: ["SquishSoft"]),
        .testTarget(name: "SquishWorkshopTests", dependencies: ["SquishWorkshop", "SquishPolicy"]),
    ]
)
