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
    name: "StoryGrafter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "storygrafter", targets: ["storygrafter"]),
        // Tree-sitter highlighting for other apps (Dibs); styles(source:language:) and the grammar list.
        .library(name: "Highlight", targets: ["Highlight"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/swiftlang/swift-cmark", exact: "0.9.0"),
        // exact: a stray older tag 0.25.0 sorts above 0.10.0.
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", exact: "0.10.0"),
    ],
    targets: grammarTargets + [
        .target(name: "StoryGrafterCore"),
        .target(name: "Highlight",
                dependencies: ["StoryGrafterCore", .product(name: "SwiftTreeSitter", package: "swift-tree-sitter")]
                    + grammars.map { .target(name: "TSGrammar\($0.0)") },
                resources: [.copy("Resources")]),
        .target(name: "Render", dependencies: [
            "StoryGrafterCore",
            .product(name: "cmark-gfm", package: "swift-cmark"),
            .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
        ], resources: [.copy("Resources")]),
        .executableTarget(name: "storygrafter", dependencies: [
            "StoryGrafterCore", "Highlight", "Render",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ], resources: [.copy("Resources/story-format.md"), .copy("Resources/prompt.md")]),
        .testTarget(name: "StoryGrafterCoreTests", dependencies: ["StoryGrafterCore", "storygrafter"], resources: [.copy("../Fixtures")]),
        .testTarget(name: "HighlightTests", dependencies: ["Highlight"] + grammars.map { .target(name: "TSGrammar\($0.0)") }),
        .testTarget(name: "RenderTests", dependencies: ["Render"], resources: [.copy("Fixtures")]),
    ]
)
