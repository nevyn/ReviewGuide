import Foundation
import ReviewGuideCore

/// Renders a resolved story as one self-contained HTML page: no external assets, fonts or scripts.
public struct HTMLRenderer {
    public init(styler: any LineStyling) { fatalError("unimplemented") }
    public func render(_ story: ResolvedStory) throws -> String { fatalError("unimplemented") }
}

/// Renders a resolved story as one Markdown document, with code as fenced `diff` blocks.
public struct MarkdownRenderer {
    public init() {}
    public func render(_ story: ResolvedStory) throws -> String { fatalError("unimplemented") }
}
