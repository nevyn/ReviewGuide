import Foundation
import Testing
@testable import storygrafter
@testable import StoryGrafterCore

private final class Captured: @unchecked Sendable {
    private let lock = NSLock()
    private var out: [String] = [], err: [String] = []
    func appendOut(_ s: String) { lock.withLock { out.append(s) } }
    func appendErr(_ s: String) { lock.withLock { err.append(s) } }
    var stdout: String { lock.withLock { out.joined(separator: "\n") } }
    var stderrLines: [String] { lock.withLock { err.flatMap { $0.split(separator: "\n").map(String.init) } } }
}

private func run(_ arguments: [String]) -> (status: Int32, stdout: String, stderr: [String]) {
    let captured = Captured()
    let console = Console(out: { captured.appendOut($0) }, err: { captured.appendErr($0) })
    let status = Console.$current.withValue(console) { StoryGrafterCommand.run(arguments) }
    return (status, captured.stdout, captured.stderrLines)
}

private func writeStory(_ repo: TempRepo, _ text: String) throws -> String {
    let url = repo.url.appendingPathComponent("story.md")
    try Data(text.utf8).write(to: url)
    return url.path
}

/// Places everything in `TempRepo.standard()`'s `main...feature` except what `*.png` excludes.
private let completeStory = """
---
title: Feature
range: main...feature
exclude: ["*.png"]
---
Summary.

## Clock
```hunks
Station.swift
Drift.swift
```

## Rest
```hunks
Sources/Old.swift
"Guide Notes.md"
Moved.txt
logo.bin
```
"""

private struct JSONDocument: Decodable {
    struct File: Decodable {
        var path: String
        var oldPath: String?
        var status: String
        var placedIn: String?
        var hunks: [JSONHunk]
    }
    struct JSONHunk: Decodable {
        var number: Int, header: String, oldStart: Int, oldCount: Int, newStart: Int, newCount: Int
        var lines: [Line]
    }
    struct Line: Decodable {
        var kind: String
        var old: Int?
        var new: Int?
        var text: String
        var placedIn: String?
    }
    var range: String, base: String, head: String
    var excluded: [Exclusion]
    var files: [File]
}

@Suite struct CLITests {
    @Test func listJSONMatchesTheSchema() throws {
        let repo = try TempRepo.standard()
        let story = try writeStory(repo, completeStory.replacingOccurrences(of: "Drift.swift\n", with: ""))
        let result = run(["list", "--json", "--repo", repo.url.path, "--story", story])
        #expect(result.status == 0, "\(result.stderr)")

        let raw = try #require(try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any])
        let firstFile = try #require((raw["files"] as? [[String: Any]])?.first)
        #expect(firstFile.keys.contains("oldPath") && firstFile["oldPath"] is NSNull)
        #expect(firstFile.keys.contains("placedIn"))
        #expect(!result.stdout.contains("\\/"))

        let doc = try JSONDecoder().decode(JSONDocument.self, from: Data(result.stdout.utf8))
        #expect(doc.range == "main...feature" && doc.base.count == 40 && doc.head.count == 40)
        #expect(doc.excluded == [Exclusion(pattern: "*.png", files: ["Assets/icon.png"])])

        let station = try #require(doc.files.first { $0.path == "Sources/Clock/Station.swift" })
        #expect(station.status == "modified" && station.placedIn == nil && station.hunks.map(\.number) == [1, 2])
        #expect(station.hunks[0].lines.filter { $0.kind != "context" }.allSatisfy { $0.placedIn == "clock" })
        #expect(station.hunks[0].lines.filter { $0.kind == "context" }.allSatisfy { $0.placedIn == nil })
        let del = try #require(station.hunks[0].lines.first { $0.kind == "del" })
        #expect(del.old == 3 && del.new == nil && del.text == "let line3 = 3")

        let drift = try #require(doc.files.first { $0.path == "Sources/Clock/Drift.swift" })
        #expect(drift.status == "added" && drift.hunks[0].lines.allSatisfy { $0.placedIn == nil })

        let moved = try #require(doc.files.first { $0.path == "Moved.txt" })
        #expect(moved.status == "renamed" && moved.oldPath == "Moving.txt" && moved.placedIn == "rest" && moved.hunks.isEmpty)
    }

    @Test func listTextShowsPlacements() throws {
        let repo = try TempRepo.standard()
        let story = try writeStory(repo, completeStory.replacingOccurrences(of: "Drift.swift\n", with: "").replacingOccurrences(of: "logo.bin\n", with: ""))
        let result = run(["list", "--repo", repo.url.path, "--story", story])
        #expect(result.status == 0)
        let lines = result.stdout.split(separator: "\n").map(String.init)
        #expect(lines.contains("Sources/Clock/Station.swift  #1  → clock"))
        #expect(lines.contains("Sources/Clock/Drift.swift  #1  → UNPLACED (3 lines)"))
        #expect(lines.contains("Moved.txt  (renamed from Moving.txt)  → rest"))
        #expect(lines.contains("Assets/logo.bin  (binary)  → UNPLACED"))
    }

    @Test func listWithoutAStory() throws {
        let repo = try TempRepo.standard()
        let result = run(["list", "--repo", repo.url.path, "--range", "main...feature"])
        #expect(result.status == 0)
        #expect(result.stdout.split(separator: "\n").contains("Moved.txt  (renamed from Moving.txt)"))
        #expect(result.stdout.contains("Assets/icon.png  (binary)"))
    }

    @Test func checkPassesOnACompleteStory() throws {
        let repo = try TempRepo.standard()
        let story = try writeStory(repo, completeStory)
        let result = run(["check", "--repo", repo.url.path, "--story", story])
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stderr.isEmpty)
    }

    @Test func checkListsEveryProblemAndExitsOne() throws {
        let repo = try TempRepo.standard()
        let broken = completeStory
            .replacingOccurrences(of: "Drift.swift\n", with: "Nope.swift\nStation.swift #1 again\n")
            .replacingOccurrences(of: "logo.bin\n", with: "Station.swift #2\n")
        let result = run(["check", "--repo", repo.url.path, "--story", try writeStory(repo, broken)])
        #expect(result.status == 1)
        #expect(result.stderr == [
            "clock: Nope.swift: matches no file in the diff",
            "rest: Station.swift #2: 'Sources/Clock/Station.swift' #2: 2 changed lines already placed in section 'clock'",
            "unplaced: Assets/logo.bin (binary)",
            "unplaced: Sources/Clock/Drift.swift #1 -/1: struct Drift {",
            "unplaced: Sources/Clock/Drift.swift #1 -/2:     var skew = 0",
            "unplaced: Sources/Clock/Drift.swift #1 -/3: }",
        ])
    }

    @Test func storySyntaxProblemsExitOneWithLineNumbers() throws {
        let repo = try TempRepo.standard()
        let result = run(["check", "--repo", repo.url.path, "--story", try writeStory(repo, "---\ntitle: T\n---\n# Bad\n")])
        #expect(result.status == 1)
        #expect(result.stderr == ["story.md: line 4: '# Bad' is not allowed: the only level-1 heading is '# Appendix'"])
    }

    @Test func headMismatchWarns() throws {
        let repo = try TempRepo.standard()
        let story = try writeStory(repo, completeStory.replacingOccurrences(of: "range: main...feature\n", with: "range: main...feature\nhead: 0000000\n"))
        let result = run(["check", "--repo", repo.url.path, "--story", story])
        #expect(result.status == 0)
        #expect(result.stderr.count == 1 && result.stderr[0].hasPrefix("warning: the story was written against 0000000, but the diff's head is "))
    }

    @Test(arguments: [["--range", "main"], ["--range", "main..nope"]])
    func badRangeExitsTwo(range: [String]) throws {
        let repo = try TempRepo.standard()
        let result = run(["list", "--repo", repo.url.path] + range)
        #expect(result.status == 2)
        #expect(result.stderr.first?.contains(range[1]) == true, "\(result.stderr)")
    }

    @Test func missingStoryAndUnknownOptionExitTwo() throws {
        let repo = try TempRepo.standard()
        let missing = run(["check", "--repo", repo.url.path])
        #expect(missing.status == 2)
        #expect(missing.stderr.first?.contains("review-guides/feature.md") == true)
        #expect(run(["list", "--bogus"]).status == 2)
        #expect(run(["--help"]).status == 0)
    }

    @Test func buildStopsAtCoverageProblems() throws {
        let repo = try TempRepo.standard()
        let story = try writeStory(repo, completeStory.replacingOccurrences(of: "logo.bin\n", with: ""))
        let result = run(["build", "--repo", repo.url.path, "--story", story])
        #expect(result.status == 1)
        #expect(result.stderr == ["unplaced: Assets/logo.bin (binary)"])
    }

    @Test func buildRefusesToOverwriteTheStory() throws {
        let repo = try TempRepo.standard()
        let story = try writeStory(repo, completeStory)
        let result = run(["build", "--format", "md", "--repo", repo.url.path, "--story", story, "--out", story])
        #expect(result.status == 2)
        #expect(result.stderr.first?.contains("is the story itself") == true)
    }

    @Test func pathsFollowTheBranch() throws {
        let repo = try TempRepo.standard()
        let result = run(["paths", "--repo", repo.url.path])
        #expect(result.status == 0)
        #expect(result.stdout.hasPrefix("story  ") && result.stdout.contains("/.git/review-guides/feature.md"))
        #expect(result.stdout.contains("/.git/review-guides/feature.guide.md"))
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent(".git/review-guides").path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }
}
