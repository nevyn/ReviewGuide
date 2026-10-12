import Foundation

/// The change that a review guide explains: `git diff <range>` minus the story's exclusions.
public struct Diff: Sendable, Equatable {
    /// The range as given to git, e.g. `origin/main...HEAD`.
    public var range: String
    /// The sha that the old side of the diff was read from: the merge base for a `...` range, the left rev otherwise.
    public var base: String
    /// The sha that the new side of the diff was read from.
    public var head: String
    /// Files in `git diff` order.
    public var files: [DiffFile]
    /// One entry per exclusion glob, with the paths that it removed (possibly none).
    public var excluded: [Exclusion]

    public init(range: String, base: String, head: String, files: [DiffFile], excluded: [Exclusion]) {
        self.range = range; self.base = base; self.head = head; self.files = files; self.excluded = excluded
    }
}

public struct Exclusion: Sendable, Equatable, Codable {
    /// The pathspec glob as written in the story's front matter.
    public var pattern: String
    /// Repo-relative paths that the glob removed from the diff.
    public var files: [String]

    public init(pattern: String, files: [String]) { self.pattern = pattern; self.files = files }
}

public struct DiffFile: Sendable, Equatable {
    /// Repo-relative path on the new side; for a deleted file, the path it had.
    public var path: String
    /// The old path of a renamed or copied file; `nil` otherwise.
    public var oldPath: String?
    public var status: FileStatus
    /// Empty for a file change without hunks: binary, pure rename, mode change.
    public var hunks: [Hunk]

    public init(path: String, oldPath: String? = nil, status: FileStatus, hunks: [Hunk]) {
        self.path = path; self.oldPath = oldPath; self.status = status; self.hunks = hunks
    }

    /// A file without hunks is placed as a whole and counts once toward coverage.
    public var isFileChange: Bool { hunks.isEmpty }
}

public enum FileStatus: String, Sendable, Equatable, Codable {
    case added, deleted, modified, renamed, copied, binary, mode
}

public struct Hunk: Sendable, Equatable {
    /// 1-based position within its file, as `reviewguide list` prints it.
    public var number: Int
    /// The function context git prints after `@@ … @@`, trimmed; empty when git printed none.
    public var header: String
    public var oldStart: Int
    public var oldCount: Int
    public var newStart: Int
    public var newCount: Int
    /// The hunk body in order. `\ No newline at end of file` markers are dropped.
    public var lines: [DiffLine]

    public init(number: Int, header: String, oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, lines: [DiffLine]) {
        self.number = number; self.header = header
        self.oldStart = oldStart; self.oldCount = oldCount; self.newStart = newStart; self.newCount = newCount
        self.lines = lines
    }
}

public struct DiffLine: Sendable, Equatable {
    public var kind: LineKind
    /// Line number in the old file; `nil` for an added line.
    public var old: Int?
    /// Line number in the new file; `nil` for a deleted line.
    public var new: Int?
    /// The line without its leading `+`, `-` or space, and without a line terminator.
    public var text: String

    public init(kind: LineKind, old: Int?, new: Int?, text: String) {
        self.kind = kind; self.old = old; self.new = new; self.text = text
    }

    /// Added and deleted lines count toward coverage; context lines do not.
    public var isChange: Bool { kind != .context }

    /// Empty or whitespace only. Blank changed lines are shown when a range includes them but need no placement.
    public var isBlank: Bool { text.allSatisfy(\.isWhitespace) }
}

public enum LineKind: String, Sendable, Equatable, Codable {
    case context, add, del
}
