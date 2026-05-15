// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PoleAIKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PoleAIKit", targets: ["PoleAIKit"]),
    ],
    dependencies: [
        .package(path: "../PoleSharedKit"),
        .package(path: "../PoleDomain"),
        .package(path: "../PoleMotorsportKit"),
    ],
    targets: [
        .target(
            name: "PoleAIKit",
            dependencies: ["PoleSharedKit", "PoleDomain", "PoleMotorsportKit"]
        ),
        .testTarget(
            name: "PoleAIKitTests",
            dependencies: ["PoleAIKit"]
        ),
    ]
)
