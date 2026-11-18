// swift-tools-version: 6.2
import PackageDescription

/// ASCKit is the App Store Connect API client shared by the apps.
/// PlayKit reads Google Play (service account, report files, reviews, crash rates) for the Mac app.
/// asc-peek is a command-line tool that prints the raw App Store Connect responses for a configured API key.
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
        .testTarget(name: "ASCKitTests", dependencies: ["ASCKit"]),
        .executableTarget(name: "asc-peek", dependencies: ["ASCKit"]),
    ]
)
