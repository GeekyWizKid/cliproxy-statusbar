// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CliproxyStatusBar",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "CliproxyStatusBar", targets: ["CliproxyStatusBar"]),
    ],
    targets: [
        .executableTarget(
            name: "CliproxyStatusBar"
        ),
    ]
)
