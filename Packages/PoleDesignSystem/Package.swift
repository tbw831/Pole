// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PoleDesignSystem",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PoleDesignSystem", targets: ["PoleDesignSystem"]),
    ],
    dependencies: [
        .package(path: "../PoleDomain"),
    ],
    targets: [
        .target(
            name: "PoleDesignSystem",
            dependencies: ["PoleDomain"]
        ),
        .testTarget(name: "PoleDesignSystemTests", dependencies: ["PoleDesignSystem"]),
    ]
)
