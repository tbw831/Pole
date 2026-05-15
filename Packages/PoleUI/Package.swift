// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PoleUI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PoleUI", targets: ["PoleUI"]),
    ],
    dependencies: [
        .package(path: "../PoleSharedKit"),
        .package(path: "../PoleDesignSystem"),
        .package(path: "../PoleDomain"),
        .package(path: "../PoleMotorsportKit"),
        .package(path: "../PoleAIKit"),
    ],
    targets: [
        .target(
            name: "PoleUI",
            dependencies: ["PoleSharedKit", "PoleDesignSystem", "PoleDomain", "PoleMotorsportKit", "PoleAIKit"]
        ),
        .testTarget(name: "PoleUITests", dependencies: ["PoleUI"]),
    ]
)
