// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PoleDomain",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PoleDomain", targets: ["PoleDomain"]),
    ],
    dependencies: [
        .package(path: "../PoleSharedKit"),
    ],
    targets: [
        .target(
            name: "PoleDomain",
            dependencies: ["PoleSharedKit"]
        ),
        .testTarget(
            name: "PoleDomainTests",
            dependencies: ["PoleDomain"]
        ),
    ]
)
