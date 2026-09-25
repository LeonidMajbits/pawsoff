// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = [.library(name: "PawsOffCore", targets: ["PawsOffCore"])]
var targets: [Target] = [
    .target(name: "PawsOffCore"),
    .testTarget(name: "PawsOffCoreTests", dependencies: ["PawsOffCore"])
]
#if os(macOS)
products.append(.executable(name: "PawsOff", targets: ["PawsOff"]))
targets.append(.executableTarget(
    name: "PawsOff", dependencies: ["PawsOffCore"],
    linkerSettings: [
        .linkedFramework("AppKit"), .linkedFramework("ApplicationServices"),
        .linkedFramework("Carbon"), .linkedFramework("CoreGraphics"),
        .linkedFramework("IOKit"), .linkedFramework("QuartzCore")
    ]
))
#endif
let package = Package(
    name: "PawsOff", platforms: [.macOS(.v13)], products: products,
    targets: targets, swiftLanguageVersions: [.v5]
)
