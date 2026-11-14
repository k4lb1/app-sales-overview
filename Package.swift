// swift-tools-version: 6.2
import PackageDescription

/// ASCKit talks to the App Store Connect API; the iPhone app will use it too.
/// asc-peek is the M0 tool: prints what Apple returns for our own key, to see the real data first.
let package = Package(
    name: "AppSales",
    platforms: [.macOS(.v15), .iOS(.v26)],
    products: [
        .library(name: "ASCKit", targets: ["ASCKit"]),
    ],
    targets: [
        .target(name: "ASCKit"),
        .executableTarget(name: "asc-peek", dependencies: ["ASCKit"]),
    ]
)
