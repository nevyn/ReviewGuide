import Foundation
import Testing
@testable import ReviewGuideCore

private func hunk(start: Int, _ body: [String]) -> Hunk {
    var old = start, new = start
    var lines: [DiffLine] = []
    for raw in body {
        let text = String(raw.dropFirst())
        switch raw.first {
        case "+": lines.append(DiffLine(kind: .add, old: nil, new: new, text: text)); new += 1
        case "-": lines.append(DiffLine(kind: .del, old: old, new: nil, text: text)); old += 1
        default: lines.append(DiffLine(kind: .context, old: old, new: new, text: text)); old += 1; new += 1
        }
    }
    return Hunk(number: 1, header: "", oldStart: start, oldCount: old - start, newStart: start, newCount: new - start, lines: lines)
}

private let clock = DiffFile(path: "Sources/Clock.swift", status: .modified, hunks: [hunk(start: 10, [
    " struct Clock {",                              // 0
    "-    var threshold = 100",                     // 1
    "+    var threshold = 250",                     // 2
    "     let id: Int",                             // 3
    "-    // sync clock every hour",                // 4
    "-    sync(interval: 3600)",                    // 5
    "+    // sync clock every hour, with jitter",   // 6
    "+    sync(interval: 3600 + jitter)",           // 7
    "     func tick() {}",                          // 8
    "-    legacy()",                                // 9
    "-    legacyTwo()",                             // 10
])])
private let block = DiffFile(path: "Sources/Block.swift", status: .added, hunks: [hunk(start: 1, (1...6).map { "+line\($0)" })])
private let diff = Diff(range: "r", base: "b", head: "h", files: [clock, block], excluded: [])

private func analyze(_ sections: [(String, [String])]) throws -> Resolution {
    var text = "---\ntitle: T\n---\n"
    for (id, selectors) in sections { text += "## \(id)\n```hunks\n" + selectors.joined(separator: "\n") + "\n```\n" }
    return Resolver.analyze(try StoryParser.parse(text, url: URL(fileURLWithPath: "/tmp/s.md")), against: diff)
}

private func lines(_ resolution: Resolution, section: Int) -> [Range<Int>] {
    resolution.resolved.sections[section].code.compactMap {
        if case .hunk(let file, _, let lines, _) = $0, file.path == clock.path { lines } else { nil }
    }
}

@Suite struct AnchoredRangeTests {
    @Test func changedLineAnchorMatchesTheNewSideAndTakesItsDeletion() throws {
        let r = try analyze([("a", ["Clock.swift @ \"var threshold\" to \"let id\""])])
        #expect(lines(r, section: 0) == [1..<4])
        #expect(r.problems.filter { !$0.message.hasPrefix("unplaced") } == [])
    }

    @Test func toEndRunsToTheEndOfTheHunk() throws {
        let r = try analyze([
            ("a", ["Clock.swift @ \"struct Clock\" to \"let id\"", "Block.swift @ \"line1\" to \"line3\""]),
            ("b", ["Clock.swift @ \"clock every hour\" to end", "Block.swift @ \"line4\" to end"]),
        ])
        #expect(lines(r, section: 1) == [4..<11])
        #expect(r.problems == [])
    }

    @Test func blankLinesBetweenRangesNeedNoPlacement() throws {
        let spaced = DiffFile(path: "Spaced.swift", status: .added, hunks: [hunk(start: 1, ["+func a() {}", "+", "+   ", "+func b() {}"])])
        let story = try StoryParser.parse("---\ntitle: T\n---\n## a\n```hunks\nSpaced.swift @ \"func a\" to \"func a\"\n```\n## b\n```hunks\nSpaced.swift @ \"func b\" to end\n```\n",
                                          url: URL(fileURLWithPath: "/tmp/s.md"))
        let r = Resolver.analyze(story, against: Diff(range: "r", base: "b", head: "h", files: [spaced], excluded: []))
        #expect(r.problems == [])
    }

    @Test func untilStopsBeforeItsLineAndTheDeletionsAttachedToIt() throws {
        let r = try analyze([
            ("a", ["Clock.swift @ \"struct Clock\" until \"clock every hour\"", "Block.swift @ \"line1\" until \"line4\""]),
            ("b", ["Clock.swift @ \"clock every hour\" to end", "Block.swift @ \"line4\" to end"]),
        ])
        #expect(lines(r, section: 0) == [0..<4])
        #expect(r.problems == [])
    }

    @Test func toOnAReplacementTakesItsNewSideAndTheDeletionsBeforeIt() throws {
        let r = try analyze([
            ("a", ["Clock.swift @ \"var threshold\" to \"clock every hour\""]),
            ("b", ["Clock.swift @ \"3600 + jitter\" to \"tick\"", "Block.swift"]),
        ])
        #expect(lines(r, section: 0) == [1..<7])
        // The deletions that end the hunk travel with "func tick() {}", the line before them.
        #expect(lines(r, section: 1) == [7..<11])
        #expect(r.problems == [])
    }

    @Test func pureDeletionAnchorFallsBackToDeletedLines() throws {
        let r = try analyze([("a", ["Clock.swift @ \"legacy()\" to \"legacyTwo\""])])
        #expect(lines(r, section: 0) == [9..<11])
        #expect(r.problems.allSatisfy { $0.message.hasPrefix("unplaced") })
    }

    @Test func ambiguousAnchorsNameTheirLines() throws {
        let r = try analyze([("a", ["Clock.swift @ \"legacy\" to \"x\"", "Clock.swift @ \"sync\" to \"x\""])])
        #expect(r.problems.prefix(2).map(\.description) == [
            "a: Clock.swift @ \"legacy\" to \"x\": \"legacy\" is on 2 deleted lines of 'Sources/Clock.swift' (#1 16/-, #1 17/-); it must be unique",
            "a: Clock.swift @ \"sync\" to \"x\": \"sync\" is on 2 lines of the new side of 'Sources/Clock.swift' (#1 -/13, #1 -/14); it must be unique",
        ])
    }

    @Test func addedBlockSplitsAcrossSections() throws {
        let r = try analyze([
            ("a", ["Block.swift @ \"line1\" to \"line3\"", "Clock.swift"]),
            ("b", ["Block.swift @ \"line4\" to \"line6\""]),
        ])
        #expect(r.problems == [])
        #expect(r.resolved.sections[1].code == [.hunk(file: block, hunk: block.hunks[0], lines: 3..<6, again: false)])
    }
}
