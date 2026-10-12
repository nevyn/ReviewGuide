// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReviewGuide",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "reviewguide", targets: ["reviewguide"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "ReviewGuideCore"),
        .target(name: "Highlight", dependencies: ["ReviewGuideCore"]),
        .target(name: "Render", dependencies: ["ReviewGuideCore"]),
        .executableTarget(name: "reviewguide", dependencies: [
            "ReviewGuideCore", "Highlight", "Render",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .testTarget(name: "ReviewGuideCoreTests", dependencies: ["ReviewGuideCore"], resources: [.copy("../Fixtures")]),
        .testTarget(name: "HighlightTests", dependencies: ["Highlight"]),
        .testTarget(name: "RenderTests", dependencies: ["Render"]),
    ]
)
