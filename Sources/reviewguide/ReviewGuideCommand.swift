import ArgumentParser
import Foundation
import ReviewGuideCore

@main
struct ReviewGuideCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reviewguide",
        abstract: "Builds a review guide: a story about a change, told next to the diff lines it explains.",
        discussion: "Stories are Markdown; `reviewguide format` prints the specification. Exit status: 0 success, 1 the story does not satisfy the diff, 2 usage, git, IO or upload error.",
        version: reviewguideVersion,
        subcommands: [List.self, Check.self, Build.self, Upload.self, Paths.self, Format.self])

    static func main() {
        Foundation.exit(run(Array(CommandLine.arguments.dropFirst())))
    }

    /// Parses and runs one command line, writing through `Console.current`, and returns the exit status from docs/cli.md.
    static func run(_ arguments: [String]) -> Int32 {
        let console = Console.current
        do {
            var command = try parseAsRoot(arguments)
            try command.run()
            return 0
        } catch let problems as StoryProblems {
            for problem in problems.problems { console.err(problem.description) }
            return 1
        } catch let error as GitError {
            console.err("reviewguide: git failed: \(error)")
            return 2
        } catch let error as UsageError {
            console.err("reviewguide: \(error)")
            return 2
        } catch let error as UploadError {
            console.err("reviewguide: upload failed: \(error)")
            return 2
        } catch {
            let code = exitCode(for: error)
            if code == .success {
                console.out(fullMessage(for: error))
                return 0
            }
            if error is ExitCode { return code.rawValue }
            console.err(fullMessage(for: error))
            return 2
        }
    }
}

/// Where commands write. Tests swap it with `Console.$current.withValue`.
struct Console: Sendable {
    var out: @Sendable (String) -> Void
    var err: @Sendable (String) -> Void

    static let standard = Console(
        out: { print($0) },
        err: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })

    @TaskLocal static var current = Console.standard
}
