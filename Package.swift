// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SwiftAgents",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0"),
        .package(url: "https://github.com/smittytone/HighlighterSwift", from: "3.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Calyx",
            dependencies: [
                "SwiftTerm",
                .product(name: "Highlighter", package: "HighlighterSwift"),
            ],
            path: "Sources"
        )
    ]
)
