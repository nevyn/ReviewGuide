import Foundation
import ReviewGuideCore

/// Tree-sitter syntax styling plus change styling within paired lines, per docs/architecture.md.
public struct Highlighter: LineStyling {
    /// `git` reads the old blobs at `diff.base` and the new blobs at `diff.head`, once per file.
    public init(git: Git, diff: Diff) { fatalError("unimplemented") }

    public func styles(for file: DiffFile, hunk: Hunk) -> [StyledLine] { fatalError("unimplemented") }
    public func styles(source: String, language: String) -> [StyledLine] { fatalError("unimplemented") }
}
