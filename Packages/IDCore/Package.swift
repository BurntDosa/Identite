// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IDCore",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [.library(name: "IDCore", targets: ["IDCore"])],
    targets: [.target(name: "IDCore", resources: [.process("Resources")]), .testTarget(name: "IDCoreTests", dependencies: ["IDCore"])],
    swiftLanguageModes: [.v6]
)
