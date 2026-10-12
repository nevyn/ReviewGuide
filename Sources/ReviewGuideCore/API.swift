import Foundation

/// Several problems at once; the CLI prints each `StoryProblem` on its own stderr line.
public struct StoryProblems: Error, Sendable, Equatable {
    public var problems: [StoryProblem]
    public init(_ problems: [StoryProblem]) { self.problems = problems }
}

public enum DiffLoader {
    /// Runs `git diff --find-renames --no-color --no-ext-diff <range> -- . :!<glob>…`, parses it and resolves `base` and `head`.
    public static func load(git: Git, range: String, exclude: [String]) throws -> Diff { fatalError("unimplemented") }
}

public enum StoryParser {
    /// Parses a story per docs/story-format.md. Throws every syntax problem found, not just the first.
    public static func parse(_ text: String, url: URL) throws(StoryProblems) -> Story { fatalError("unimplemented") }
}

public enum Resolver {
    /// Resolves every selector and checks coverage. Throws every selector and coverage problem found.
    public static func resolve(_ story: Story, against diff: Diff) throws(StoryProblems) -> ResolvedStory { fatalError("unimplemented") }
}
