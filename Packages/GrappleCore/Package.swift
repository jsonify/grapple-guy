// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GrappleCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GrappleCore", targets: ["GrappleCore"]),
    ],
    targets: [
        .target(name: "GrappleCore"),
        .testTarget(name: "GrappleCoreTests", dependencies: ["GrappleCore"]),
    ]
)
