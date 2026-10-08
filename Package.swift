// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MathMLLayout",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "MathMLLayout", targets: ["MathMLLayout"]),
    ],
    targets: [
        .target(name: "MathMLLayout"),
        .testTarget(name: "MathMLLayoutTests", dependencies: ["MathMLLayout"]),
    ]
)
