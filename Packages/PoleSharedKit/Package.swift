// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PoleSharedKit",
    platforms: [.iOS(.v17), .macOS(.v11)],
    products: [
        .library(name: "PoleSharedKit", targets: ["PoleSharedKit"]),
    ],
    targets: [
        .target(name: "PoleSharedKit"),
        .testTarget(name: "PoleSharedKitTests", dependencies: ["PoleSharedKit"]),
    ]
)
