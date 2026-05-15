// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PoleNewsKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PoleNewsKit", targets: ["PoleNewsKit"]),
    ],
    dependencies: [
        .package(path: "../PoleSharedKit"),
        .package(path: "../PoleDomain"),
    ],
    targets: [
        .target(
            name: "PoleNewsKit",
            dependencies: ["PoleSharedKit", "PoleDomain"]
        ),
        .testTarget(name: "PoleNewsKitTests", dependencies: ["PoleNewsKit"]),
    ]
)
