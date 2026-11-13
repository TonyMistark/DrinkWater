// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DrinkWater",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "DrinkWater",
            path: "Sources/DrinkWater"
        ),
        .testTarget(
            name: "DrinkWaterTests",
            dependencies: ["DrinkWater"],
            path: "Tests/DrinkWaterTests"
        )
    ]
)
