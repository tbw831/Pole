// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PoleSpeechKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PoleSpeechKit", targets: ["PoleSpeechKit"]),
    ],
    dependencies: [
        .package(path: "../PoleSharedKit"),
        .package(path: "../PoleDomain"),
    ],
    targets: [
        .target(name: "PoleSpeechKit", dependencies: ["PoleSharedKit", "PoleDomain"]),
        .testTarget(name: "PoleSpeechKitTests", dependencies: ["PoleSpeechKit"]),
    ]
)
