import Foundation

/// Runs git in one repository.
public struct Git: Sendable {
    public var repo: URL
    public init(repo: URL) { self.repo = repo }

    /// Runs `git -C <repo> <args>` and returns stdout. Throws `GitError` naming the command and git's stderr on non-zero exit.
    public func run(_ args: [String]) throws -> String { fatalError("unimplemented") }

    /// The blob at `rev:path`, or `nil` when the path does not exist at that rev.
    public func show(rev: String, path: String) throws -> Data? { fatalError("unimplemented") }
}

/// Several problems at once; the CLI prints each `StoryProblem` on its own stderr line.
public struct StoryProblems: Error, Sendable, Equatable {
    public var problems: [StoryProblem]
    public init(_ problems: [StoryProblem]) { self.problems = problems }
}

public enum DiffLoader {
    /// Runs `git diff --find-renames --no-color --no-ext-diff <range> -- . :!<glob>…`, parses it and resolves `base` and `head`.
    public static func load(git: Git, range: String, exclude: [String]) throws -> Diff { fatalError("unimplemented") }
}

public enum DiffParser {
    /// Parses unified diff text as `git diff` prints it. Hunk numbers are assigned per file.
    public static func parse(_ text: String) -> [DiffFile] { fatalError("unimplemented") }
}

public enum StoryParser {
    /// Parses a story per docs/story-format.md. Throws every syntax problem found, not just the first.
    public static func parse(_ text: String, url: URL) throws(StoryProblems) -> Story { fatalError("unimplemented") }
}

public enum Resolver {
    /// Resolves every selector and checks coverage. Throws every selector and coverage problem found.
    public static func resolve(_ story: Story, against diff: Diff) throws(StoryProblems) -> ResolvedStory { fatalError("unimplemented") }
}
