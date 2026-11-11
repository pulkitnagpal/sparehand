// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Sparehand",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SparehandCore", targets: ["SparehandCore"]),
        .executable(name: "SparehandApp", targets: ["SparehandApp"]),
        .executable(name: "sparehand", targets: ["sparehand"]),
    ],
    targets: [
        .target(name: "SparehandCore"),
        .target(name: "CVirtualDisplay", linkerSettings: [.linkedFramework("CoreGraphics"), .linkedFramework("Foundation")]),
        .executableTarget(name: "SparehandApp", dependencies: ["SparehandCore", "CVirtualDisplay"]),
        .executableTarget(name: "sparehand", dependencies: ["SparehandCore"]),
        .testTarget(name: "SparehandCoreTests", dependencies: ["SparehandCore"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v5]
)
