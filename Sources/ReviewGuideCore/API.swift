import Foundation

/// Several problems at once; the CLI prints each `StoryProblem` on its own stderr line.
public struct StoryProblems: Error, Sendable, Equatable {
    public var problems: [StoryProblem]
    public init(_ problems: [StoryProblem]) { self.problems = problems }
}

public enum StoryParser {
    /// Parses a story per docs/story-format.md. Throws every syntax problem found, not just the first.
    public static func parse(_ text: String, url: URL) throws(StoryProblems) -> Story { fatalError("unimplemented") }
}

public enum Resolver {
    /// Resolves every selector and checks coverage. Throws every selector and coverage problem found.
    public static func resolve(_ story: Story, against diff: Diff) throws(StoryProblems) -> ResolvedStory { fatalError("unimplemented") }
}
