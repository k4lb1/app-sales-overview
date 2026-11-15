// swift-tools-version: 6.2
import PackageDescription

/// ASCKit talks to the App Store Connect API; the iPhone app will use it too.
/// PlayKit reads Google Play (service account, report files, reviews, crash rates) for the Mac app.
/// asc-peek is the M0 tool: prints what Apple returns for our own key, to see the real data first.
let package = Package(
    name: "AppSales",
    platforms: [.macOS(.v15), .iOS(.v26)],
    products: [
        .library(name: "ASCKit", targets: ["ASCKit"]),
        .library(name: "PlayKit", targets: ["PlayKit"]),
    ],
    targets: [
        .target(name: "ASCKit"),
        .target(name: "PlayKit", dependencies: ["ASCKit"]),
        .testTarget(name: "PlayKitTests", dependencies: ["PlayKit"]),
        .executableTarget(name: "asc-peek", dependencies: ["ASCKit"]),
    ]
)
