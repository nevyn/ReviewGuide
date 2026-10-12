import Foundation
import Testing
@testable import ReviewGuideCore

@Suite struct DiffLoaderTests {
    @Test func mergeBaseRangeWithExclusion() throws {
        let repo = try TempRepo.standard()
        let diff = try DiffLoader.load(git: repo.git, range: "main...feature", exclude: ["*.png"])

        let mergeBase = try repo.git.run(["merge-base", "main", "feature"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let feature = try repo.git.run(["rev-parse", "feature"]).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(diff.range == "main...feature" && diff.base == mergeBase && diff.head == feature)

        let byPath = Dictionary(uniqueKeysWithValues: diff.files.map { ($0.path, $0) })
        #expect(Set(byPath.keys) == ["Sources/Clock/Station.swift", "Sources/Clock/Drift.swift", "Sources/Old.swift",
                                     "Docs/Guide Notes.md", "Moved.txt", "Assets/logo.bin"])
        #expect(byPath["Sources/Clock/Station.swift"]?.status == .modified)
        #expect(byPath["Sources/Clock/Station.swift"]?.hunks.map(\.number) == [1, 2])
        #expect(byPath["Sources/Clock/Drift.swift"]?.status == .added)
        #expect(byPath["Sources/Old.swift"]?.status == .deleted)
        #expect(byPath["Docs/Guide Notes.md"]?.status == .modified)
        #expect(byPath["Moved.txt"]?.status == .renamed && byPath["Moved.txt"]?.oldPath == "Moving.txt")
        #expect(byPath["Assets/logo.bin"]?.status == .binary)
        #expect(byPath["Unrelated.txt"] == nil)
        #expect(diff.excluded == [Exclusion(pattern: "*.png", files: ["Assets/icon.png"])])
    }

    @Test func twoDotRangeIncludesTheOtherSide() throws {
        let repo = try TempRepo.standard()
        let diff = try DiffLoader.load(git: repo.git, range: "main..feature", exclude: [])
        #expect(diff.base == (try repo.git.run(["rev-parse", "main"]).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(diff.files.contains { $0.path == "Unrelated.txt" && $0.status == .deleted })
        let spaced = try DiffLoader.load(git: repo.git, range: "main feature", exclude: [])
        #expect(spaced.files == diff.files)
    }

    @Test func singleRevIsAUsageError() throws {
        let repo = try TempRepo.standard()
        #expect(throws: UsageError.self) { try DiffLoader.load(git: repo.git, range: "main", exclude: []) }
    }

    @Test func unknownRevNamesTheRangeAndTheCommand() throws {
        let repo = try TempRepo.standard()
        do {
            _ = try DiffLoader.load(git: repo.git, range: "main..nope", exclude: [])
            Issue.record("expected a UsageError")
        } catch let error as UsageError {
            #expect(error.message.hasPrefix("range 'main..nope': 'nope' is not a commit in "))
            #expect(error.message.contains("rev-parse --verify nope^{commit}"))
        }
    }

    @Test func showReturnsNilForAMissingPathAndThrowsForABadRev() throws {
        let repo = try TempRepo.standard()
        #expect(try repo.git.show(rev: "feature", path: "Sources/Old.swift") == nil)
        #expect(try repo.git.show(rev: "main", path: "Sources/Old.swift") == Data("struct Old {}\n".utf8))
        #expect(throws: GitError.self) { try repo.git.show(rev: "no-such-rev", path: "x") }
    }
}
