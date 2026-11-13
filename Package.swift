// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftDWG",
    products: [
        .library(name: "SwiftDWG", targets: ["SwiftDWG"])
    ],
    dependencies: [
        // The drawing model a DWG is read into.
        .package(url: "https://github.com/SecondMouseAU/SwiftDXF.git", from: "0.4.0")
    ],
    targets: [
        .target(
            name: "SwiftDWG",
            dependencies: [.product(name: "SwiftDXF", package: "SwiftDXF")]),
        .testTarget(
            name: "SwiftDWGTests", dependencies: ["SwiftDWG"],
            // The fixtures are read by path, not as bundle resources.
            exclude: ["Fixtures"]),
    ]
)
