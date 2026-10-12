import Foundation

/// A story whose selectors have been resolved against a diff and whose coverage holds.
public struct ResolvedStory: Sendable, Equatable {
    public var story: Story
    public var diff: Diff
    /// Parallel to `story.sections`.
    public var sections: [ResolvedSection]

    public init(story: Story, diff: Diff, sections: [ResolvedSection]) {
        self.story = story; self.diff = diff; self.sections = sections
    }
}

public struct ResolvedSection: Sendable, Equatable {
    public var section: Section
    /// The code column in selector order; empty when the section has no `hunks` fence.
    public var code: [ShownCode]

    public init(section: Section, code: [ShownCode]) { self.section = section; self.code = code }
}

public enum ShownCode: Sendable, Equatable {
    /// `lines` are 0-based indices into `hunk.lines`; the whole hunk when the selector had no line pick.
    case hunk(file: DiffFile, hunk: Hunk, lines: Range<Int>, again: Bool)
    /// A file without hunks: binary, pure rename, mode change.
    case fileChange(file: DiffFile, again: Bool)
}

/// One reason a story does not satisfy its diff. `check` collects all of them before failing.
public struct StoryProblem: Error, Sendable, Equatable, CustomStringConvertible {
    /// `nil` for problems that belong to no section, such as an unplaced line.
    public var sectionID: String?
    /// The selector as written, when the problem is about one.
    public var selector: String?
    /// What is wrong, naming the input: the path, the hunk number, the line text.
    public var message: String

    public init(sectionID: String? = nil, selector: String? = nil, message: String) {
        self.sectionID = sectionID; self.selector = selector; self.message = message
    }

    /// The stderr form from docs/cli.md: `<section id>: <selector>: <problem>`.
    public var description: String {
        [sectionID, selector, message].compactMap { $0 }.joined(separator: ": ")
    }
}

/// Styling of one shown line: non-overlapping runs that cover the line's UTF-8 bytes in order.
public typealias StyledLine = [StyledRun]

public struct StyledRun: Sendable, Equatable {
    /// UTF-8 byte offsets into `DiffLine.text`.
    public var bytes: Range<Int>
    /// A tree-sitter highlight capture name such as `keyword` or `string.special`; `nil` for unstyled text.
    public var capture: String?
    /// The token differs from its paired line in the same hunk.
    public var changed: Bool

    public init(bytes: Range<Int>, capture: String? = nil, changed: Bool = false) {
        self.bytes = bytes; self.capture = capture; self.changed = changed
    }
}

/// Supplies syntax and change styling to the renderers. `Highlight` implements it; tests use plain stubs.
public protocol LineStyling: Sendable {
    /// One `StyledLine` per entry of `hunk.lines`, in order.
    func styles(for file: DiffFile, hunk: Hunk) -> [StyledLine]
    /// Styling for a standalone snippet such as an attachment, one entry per `\n`-separated line.
    /// `language` is a Markdown info-string language or a file extension; unknown languages come back unstyled.
    func styles(source: String, language: String) -> [StyledLine]
}
