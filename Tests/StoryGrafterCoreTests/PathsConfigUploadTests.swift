import Foundation
import Testing
@testable import StoryGrafterCore

@Suite struct GuidePathsTests {
    @Test func branchPathsLiveInTheCommonDir() throws {
        let repo = try TempRepo.standard()
        _ = try repo.git.run(["checkout", "-q", "-b", "nevyn/clock-drift"])
        let paths = try GuidePaths.forCurrentBranch(git: repo.git)
        let dir = repo.url.appendingPathComponent(".git/review-guides/nevyn").resolvingSymlinksInPath().path
        #expect(paths.story.deletingLastPathComponent().resolvingSymlinksInPath().path == dir)
        #expect(paths.story.lastPathComponent == "clock-drift.md")
        #expect(paths.html.lastPathComponent == "clock-drift.html")
        #expect(paths.markdown.lastPathComponent == "clock-drift.guide.md")
    }

    @Test func worktreesShareTheCommonDir() throws {
        let repo = try TempRepo.standard()
        let worktree = repo.url.appendingPathComponent("wt")
        _ = try repo.git.run(["worktree", "add", "-q", "-b", "other", worktree.path])
        let paths = try GuidePaths.forCurrentBranch(git: Git(repo: worktree))
        #expect(paths.story.resolvingSymlinksInPath().path ==
                repo.url.appendingPathComponent(".git/review-guides/other.md").resolvingSymlinksInPath().path)
    }

    @Test func detachedHeadIsAUsageError() throws {
        let repo = try TempRepo.standard()
        _ = try repo.git.run(["checkout", "-q", "--detach"])
        #expect(throws: UsageError.self) { try GuidePaths.forCurrentBranch(git: repo.git) }
    }

    @Test func besideAStory() {
        let paths = GuidePaths.beside(story: URL(fileURLWithPath: "/x/y/story.md"))
        #expect(paths.html.path == "/x/y/story.html" && paths.markdown.path == "/x/y/story.guide.md")
    }
}

@Suite struct ConfigTests {
    let file = URL(fileURLWithPath: "/tmp/storygrafter-config")

    @Test func parsesUploadAndComments() throws {
        let config = try Config.parse("# comment\n\nupload = scp {file} host:/x/#frag # trailing\n", file: file)
        #expect(config.upload == "scp {file} host:/x/#frag")
    }

    @Test func malformedLinesNameFileAndLine() {
        #expect(throws: UsageError("/tmp/storygrafter-config:2: expected 'key = value', found 'upload'")) {
            try Config.parse("\nupload\n", file: file)
        }
        #expect(throws: UsageError("/tmp/storygrafter-config:1: unknown key 'uplaod'; the only key is 'upload'")) {
            try Config.parse("uplaod = x\n", file: file)
        }
    }

    @Test func environmentWins() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("StoryGrafterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = dir.appendingPathComponent("config")
        try Data("upload = from-file {file}\n".utf8).write(to: config)
        #expect(try Config.load(environment: [:], file: config).upload == "from-file {file}")
        #expect(try Config.load(environment: ["STORYGRAFTER_UPLOAD": "from-env {file}"], file: config).upload == "from-env {file}")
        #expect(try Config.load(environment: ["STORYGRAFTER_UPLOAD": ""], file: config).upload == "from-file {file}")
        #expect(try Config.load(environment: [:], file: dir.appendingPathComponent("absent")).upload == nil)
    }
}

@Suite struct UploaderTests {
    func guide() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("StoryGrafterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("it's a guide.html")
        try Data("<p>x</p>".utf8).write(to: file)
        return file
    }

    @Test func returnsTheLastURLLine() throws {
        let file = try guide()
        let uploader = Uploader(command: "test -f {file} && echo 'https://first' && echo noise && printf 'https://files.example/%s\\n' \"$(basename {file} | tr ' ' _)\"")
        #expect(try uploader.upload(file: file) == URL(string: "https://files.example/it's_a_guide.html"))
    }

    @Test func failures() throws {
        let file = try guide()
        #expect(throws: UploadError.self) { try Uploader(command: "echo https://x; exit 3 # {file}").upload(file: file) }
        #expect(throws: UploadError("the upload command `echo nope '\(file.path.replacingOccurrences(of: "'", with: "'\\''"))'` printed no http(s) URL on stdout; it printed:\nnope \(file.path)")) {
            try Uploader(command: "echo nope {file}").upload(file: file)
        }
        #expect(throws: UploadError("the upload command `echo https://x` has no {file} placeholder")) {
            try Uploader(command: "echo https://x").upload(file: file)
        }
        #expect(throws: UploadError.self) { try Uploader(command: "echo {file}").upload(file: URL(fileURLWithPath: "/nonexistent/guide.html")) }
    }
}
