import Foundation

/// A parsed story, as specified in docs/story-format.md. Prose stays Markdown; `Render` turns it into HTML.
public struct Story: Sendable, Equatable {
    /// The story file; attachments with `file=` resolve relative to its directory.
    public var url: URL
    public var title: String
    public var meta: String?
    public var range: String?
    /// The HEAD sha that the story was written against.
    public var head: String?
    public var exclude: [String]
    /// Markdown between the front matter and the first heading.
    public var summary: String
    /// Sections before `# Appendix`, in story order.
    public var sections: [Section]
    /// Sections after `# Appendix`; they never have selectors.
    public var appendix: [Section]
    /// Footnote definitions from anywhere in the story, keyed by id without `^`, values as Markdown.
    /// The definitions are removed from the section bodies.
    public var footnotes: [String: String]

    public init(url: URL, title: String, meta: String? = nil, range: String? = nil, head: String? = nil,
                exclude: [String] = [], summary: String = "", sections: [Section] = [], appendix: [Section] = [],
                footnotes: [String: String] = [:]) {
        self.url = url; self.title = title; self.meta = meta; self.range = range; self.head = head
        self.exclude = exclude; self.summary = summary; self.sections = sections; self.appendix = appendix
        self.footnotes = footnotes
    }
}

public struct Section: Sendable, Equatable {
    /// Unique across the story: from `{#id}`, else the title slug.
    public var id: String
    public var kicker: String?
    public var title: String
    /// The section's Markdown without its heading, its `hunks` fence and footnote definitions.
    public var body: String
    /// `nil` when the section has no `hunks` fence and so no code column.
    public var selectors: [Selector]?
    /// 1-based line in the story file where the heading is, for error messages.
    public var line: Int

    public init(id: String, kicker: String? = nil, title: String, body: String, selectors: [Selector]? = nil, line: Int) {
        self.id = id; self.kicker = kicker; self.title = title; self.body = body; self.selectors = selectors; self.line = line
    }
}

/// One line of a `hunks` fence.
public struct Selector: Sendable, Equatable {
    /// The selector line as written, without its comment; quoted in error messages.
    public var source: String
    /// A repo-relative path or a suffix of one that starts after a `/`.
    public var path: String
    public var hunks: HunkPick
    public var lines: LinePick?
    /// Show without placing.
    public var again: Bool

    public init(source: String, path: String, hunks: HunkPick = .all, lines: LinePick? = nil, again: Bool = false) {
        self.source = source; self.path = path; self.hunks = hunks; self.lines = lines; self.again = again
    }
}

public enum HunkPick: Sendable, Equatable {
    /// Every hunk, or the file change of a file without hunks.
    case all
    /// 1-based hunk numbers in the order written; ranges are already expanded.
    case numbers([Int])
    /// Every hunk with a line containing the text.
    case anchor(String)
}

public enum LinePick: Sendable, Equatable {
    /// 1-based, inclusive positions in the hunk body.
    case range(Int, Int)
    /// From the one line containing `from` through the first line at or after it containing `to`, in the same hunk.
    /// Both anchors match context and added lines, and deleted lines only when no such line contains the text.
    /// Deleted lines travel with the next non-deleted line in their hunk (the previous one when they end it), so the
    /// range also covers the deletions just before `from`. A `nil` `to` (written `to end`) runs to the end of the hunk.
    /// `hunks` is `.all` alongside this pick.
    case anchored(from: String, to: String?)
}
