// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PoleWeatherKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PoleWeatherKit", targets: ["PoleWeatherKit"]),
    ],
    dependencies: [
        .package(path: "../PoleSharedKit"),
    ],
    targets: [
        .target(name: "PoleWeatherKit", dependencies: ["PoleSharedKit"]),
        .testTarget(name: "PoleWeatherKitTests", dependencies: ["PoleWeatherKit"]),
    ]
)
