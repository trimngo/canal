// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LedgerCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [.library(name: "LedgerCore", targets: ["LedgerCore"])],
    targets: [.target(name: "LedgerCore"), .testTarget(name: "LedgerCoreTests", dependencies: ["LedgerCore"])]
)
