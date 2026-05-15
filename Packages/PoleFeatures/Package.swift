// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PoleFeatures",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PoleFeatures", targets: ["PoleFeatures"]),
    ],
    dependencies: [
        .package(path: "../PoleSharedKit"),
        .package(path: "../PoleDesignSystem"),
        .package(path: "../PoleDomain"),
        .package(path: "../PoleMotorsportKit"),
        .package(path: "../PoleAIKit"),
        .package(path: "../PoleUI"),
        .package(path: "../PoleNewsKit"),
        .package(path: "../PoleWeatherKit"),
        .package(path: "../PoleSpeechKit"),
    ],
    targets: [
        .target(
            name: "PoleFeatures",
            dependencies: [
                "PoleSharedKit",
                "PoleDesignSystem",
                "PoleDomain",
                "PoleMotorsportKit",
                "PoleAIKit",
                "PoleUI",
                "PoleNewsKit",
                "PoleWeatherKit",
                "PoleSpeechKit",
            ]
        ),
        .testTarget(name: "PoleFeaturesTests", dependencies: ["PoleFeatures"]),
    ]
)
