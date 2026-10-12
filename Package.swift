// swift-tools-version: 6.0
import PackageDescription

/// Vendored tree-sitter grammars (scripts/vendor-grammars.sh): (target suffix, path under Grammars/, has scanner.c).
let grammars: [(String, String, Bool)] = [
    ("Swift", "swift", true), ("C", "c", false), ("ObjC", "objc", false), ("Cpp", "cpp", true),
    ("Kotlin", "kotlin", true), ("Java", "java", false), ("JavaScript", "javascript", true),
    ("TypeScript", "typescript/typescript", true), ("TSX", "typescript/tsx", true), ("Python", "python", true),
    ("Ruby", "ruby", true), ("Go", "go", false), ("Rust", "rust", true), ("JSON", "json", false),
    ("YAML", "yaml", true), ("TOML", "toml", true), ("Bash", "bash", true), ("SQL", "sql", true),
    ("HTML", "html", true), ("CSS", "css", true), ("Markdown", "markdown/block", true),
    ("MarkdownInline", "markdown/inline", true),
]

let grammarTargets: [Target] = grammars.map { suffix, path, hasScanner in
    .target(name: "TSGrammar\(suffix)", path: "Grammars/\(path)",
            sources: hasScanner ? ["src/parser.c", "src/scanner.c"] : ["src/parser.c"],
            publicHeadersPath: "include", cSettings: [.headerSearchPath("src")])
}

let package = Package(
    name: "ReviewGuide",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "reviewguide", targets: ["reviewguide"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        // exact: a stray older tag 0.25.0 sorts above 0.10.0.
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", exact: "0.10.0"),
    ],
    targets: grammarTargets + [
        .target(name: "ReviewGuideCore"),
        .target(name: "Highlight",
                dependencies: ["ReviewGuideCore", .product(name: "SwiftTreeSitter", package: "swift-tree-sitter")]
                    + grammars.map { .target(name: "TSGrammar\($0.0)") },
                resources: [.copy("Resources")]),
        .target(name: "Render", dependencies: ["ReviewGuideCore"]),
        .executableTarget(name: "reviewguide", dependencies: [
            "ReviewGuideCore", "Highlight", "Render",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .testTarget(name: "ReviewGuideCoreTests", dependencies: ["ReviewGuideCore"]),
        .testTarget(name: "HighlightTests", dependencies: ["Highlight"] + grammars.map { .target(name: "TSGrammar\($0.0)") }),
        .testTarget(name: "RenderTests", dependencies: ["Render"]),
    ]
)
