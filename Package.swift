// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "QuotaNest",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "QuotaNest", targets: ["QuotaNest"]), .library(name: "ArkCore", targets: ["ArkCore"])],
    targets: [.target(name: "ArkCore"), .executableTarget(name: "QuotaNest", dependencies: ["ArkCore"]), .testTarget(name: "ArkCoreTests", dependencies: ["ArkCore", "QuotaNest"])]
)
