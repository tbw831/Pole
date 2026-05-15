// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PoleMotorsportKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PoleMotorsportKit", targets: ["PoleMotorsportKit"]),
    ],
    dependencies: [
        .package(path: "../PoleSharedKit"),
        .package(path: "../PoleDomain"),
    ],
    targets: [
        .target(
            name: "PoleMotorsportKit",
            dependencies: ["PoleSharedKit", "PoleDomain"]
        ),
        .testTarget(
            name: "PoleMotorsportKitTests",
            dependencies: ["PoleMotorsportKit"]
        ),
    ]
)
