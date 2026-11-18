// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mac-razer-deathadder-essential-fix",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "deathadder-fix", targets: ["deathadder-fix"]),
        .library(name: "RazerKit", targets: ["RazerKit"]),
    ],
    targets: [
        .target(name: "RazerKit", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(
            name: "deathadder-fix",
            dependencies: ["RazerKit"],
            resources: [.copy("Web")]
        ),
        .testTarget(name: "RazerKitTests", dependencies: ["RazerKit"]),
    ]
)
