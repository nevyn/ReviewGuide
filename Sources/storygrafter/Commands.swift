import ArgumentParser
import Foundation
import Highlight
import Render
import StoryGrafterCore

struct CommonOptions: ParsableArguments {
    @Option(help: "The git work tree to diff.")
    var repo: String = "."

    @Option(help: "The git diff range; overrides the story's 'range'. Default: origin/main...HEAD.")
    var range: String?

    @Option(help: "The story file. Default: <git-common-dir>/review-guides/<branch>.md.")
    var story: String?

    var git: Git { Git(repo: URL(fileURLWithPath: repo).standardizedFileURL) }

    func paths() throws -> GuidePaths {
        if let story { return GuidePaths.beside(story: URL(fileURLWithPath: story).standardizedFileURL) }
        return try GuidePaths.forCurrentBranch(git: git)
    }

    func loadStory() throws -> Story {
        let url = try paths().story
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw UsageError("no story at \(url.path); write one there or pass --story FILE")
        }
        return try readStory(url)
    }

    /// The story if one exists: an explicit `--story` must exist, the branch default may be absent.
    func loadStoryIfPresent() throws -> Story? {
        if story != nil { return try loadStory() }
        guard let url = try? GuidePaths.forCurrentBranch(git: git).story, FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try readStory(url)
    }

    private func readStory(_ url: URL) throws -> Story {
        let text: String
        do { text = try String(contentsOf: url, encoding: .utf8) }
        catch { throw UsageError("cannot read story \(url.path): \(error.localizedDescription)") }
        do { return try StoryParser.parse(text, url: url) }
        catch {
            throw StoryProblems(error.problems.map {
                StoryProblem(sectionID: $0.sectionID, selector: $0.selector, message: "\(url.lastPathComponent): \($0.message)")
            })
        }
    }

    func loadDiff(for story: Story?) throws -> Diff {
        let diff = try DiffLoader.load(git: git, range: range ?? story?.range ?? "origin/main...HEAD", exclude: story?.exclude ?? [])
        if let head = story?.head, !diff.head.hasPrefix(head.lowercased()) {
            Console.current.err("warning: the story was written against \(head), but the diff's head is \(diff.head)")
        }
        return diff
    }
}

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Prints the diff's files and hunks, and with a story, where each changed line is placed.")

    @OptionGroup var options: CommonOptions

    @Flag(help: "Print JSON per docs/cli.md.")
    var json = false

    func run() throws {
        let story = try options.loadStoryIfPresent()
        let diff = try options.loadDiff(for: story)
        let placements = story.map { Resolver.analyze($0, against: diff).placements }
        if json {
            Console.current.out(try ListJSON(diff: diff, placements: placements).encoded())
            return
        }
        for file in diff.files {
            if file.isFileChange {
                let placed = placements.map { p in p.sectionID(fileChange: file).map { "  → \($0)" } ?? "  → UNPLACED" } ?? ""
                Console.current.out("\(file.path)  (\(file.changeSummary))\(placed)")
                continue
            }
            for hunk in file.hunks {
                let header = hunk.header.isEmpty ? "" : "  \(hunk.header)"
                Console.current.out("\(file.path)  #\(hunk.number)\(header)\(placements.map { Self.placement(file, hunk, $0) } ?? "")")
            }
        }
    }

    /// `  → a`, `  → a, b`, `  → UNPLACED (3 lines)` or `  → a, UNPLACED (1 line)`.
    static func placement(_ file: DiffFile, _ hunk: Hunk, _ placements: Placements) -> String {
        var sections: [String] = []
        var unplaced = 0
        for (index, line) in hunk.lines.enumerated() where line.isChange {
            if let id = placements.sectionID(file: file, hunk: hunk, index: index) {
                if !sections.contains(id) { sections.append(id) }
            } else {
                unplaced += 1
            }
        }
        if unplaced > 0 { sections.append("UNPLACED (\(unplaced) line\(unplaced == 1 ? "" : "s"))") }
        return "  → " + sections.joined(separator: ", ")
    }
}

struct Check: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Resolves the story against the diff and reports every coverage and selector problem. Writes nothing.")

    @OptionGroup var options: CommonOptions

    func run() throws {
        let story = try options.loadStory()
        let resolved = try Resolver.resolve(story, against: try options.loadDiff(for: story))
        Console.current.out("ok: \(resolved.sections.count) sections cover \(resolved.diff.files.count) files")
    }
}

enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case html, md
}

struct Build: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Checks the story, then writes the review guide.")

    @OptionGroup var options: CommonOptions

    @Option(help: "html or md.")
    var format: OutputFormat = .html

    @Option(help: "The file to write. Default: next to the story, as .html or .guide.md.")
    var out: String?

    @Flag(help: "Run the upload command on the guide and print its URL as the last line of stdout.")
    var upload = false

    func run() throws {
        let story = try options.loadStory()
        let diff = try options.loadDiff(for: story)
        let resolved = try Resolver.resolve(story, against: diff)

        let defaults = GuidePaths.beside(story: story.url)
        let output = out.map { URL(fileURLWithPath: $0).standardizedFileURL } ?? (format == .html ? defaults.html : defaults.markdown)
        guard output.path != story.url.standardizedFileURL.path else {
            throw UsageError("the output \(output.path) is the story itself; pass another --out")
        }

        let page: String
        switch format {
        case .html: page = try HTMLRenderer(styler: Highlighter(git: options.git, diff: diff)).render(resolved)
        case .md: page = try MarkdownRenderer().render(resolved)
        }
        do {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(page.utf8).write(to: output)
        } catch {
            throw UsageError("cannot write \(output.path): \(error.localizedDescription)")
        }
        Console.current.out(output.path)
        if upload { Console.current.out(try uploadFile(output).absoluteString) }
    }
}

struct Upload: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Runs the upload command on FILE and prints the URL.")

    @Argument(help: "The file to upload.")
    var file: String

    func run() throws {
        Console.current.out(try uploadFile(URL(fileURLWithPath: file).standardizedFileURL).absoluteString)
    }
}

func uploadFile(_ file: URL) throws -> URL {
    guard let command = try Config.load().upload else {
        throw UsageError("no upload command: set STORYGRAFTER_UPLOAD or 'upload = …' in \(Config.defaultFile.path)")
    }
    return try Uploader(command: command).upload(file: file)
}

struct Paths: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Prints the default story and output paths for the current branch.")

    @OptionGroup var options: CommonOptions

    func run() throws {
        let paths = try options.paths()
        Console.current.out("story  \(paths.story.path)\nhtml   \(paths.html.path)\nmd     \(paths.markdown.path)")
    }
}

struct Format: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Prints the story format specification for this version.")

    func run() throws {
        let bundle = ResourceBundle.named("StoryGrafter_storygrafter") ?? Bundle.module
        guard let url = bundle.url(forResource: "story-format", withExtension: "md") else {
            throw UsageError("story-format.md is missing from the storygrafter resource bundle")
        }
        Console.current.out(try String(contentsOf: url, encoding: .utf8))
    }
}
