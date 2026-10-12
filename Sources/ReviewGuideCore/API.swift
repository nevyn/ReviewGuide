import Foundation

/// Several problems at once; the CLI prints each `StoryProblem` on its own stderr line.
public struct StoryProblems: Error, Sendable, Equatable {
    public var problems: [StoryProblem]
    public init(_ problems: [StoryProblem]) { self.problems = problems }
}
