// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReviewGuide",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "reviewguide", targets: ["reviewguide"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/swiftlang/swift-cmark", exact: "0.9.0"),
    ],
    targets: [
        .target(name: "ReviewGuideCore"),
        .target(name: "Highlight", dependencies: ["ReviewGuideCore"]),
        .target(name: "Render", dependencies: [
            "ReviewGuideCore",
            .product(name: "cmark-gfm", package: "swift-cmark"),
            .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
        ], resources: [.copy("Resources")]),
        .executableTarget(name: "reviewguide", dependencies: [
            "ReviewGuideCore", "Highlight", "Render",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .testTarget(name: "ReviewGuideCoreTests", dependencies: ["ReviewGuideCore"]),
        .testTarget(name: "HighlightTests", dependencies: ["Highlight"]),
        .testTarget(name: "RenderTests", dependencies: ["Render"], resources: [.copy("Fixtures")]),
    ]
)
