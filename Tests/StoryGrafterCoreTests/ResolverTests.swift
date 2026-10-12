import Foundation
import Testing
@testable import StoryGrafterCore

/// Builds a hunk from `" x"`, `"+x"`, `"-x"` lines, numbering old and new lines from `start`.
private func hunk(_ number: Int, start: Int = 1, header: String = "", _ body: [String]) -> Hunk {
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
    return Hunk(number: number, header: header, oldStart: start, oldCount: old - start, newStart: start, newCount: new - start, lines: lines)
}

private let station = DiffFile(path: "Sources/Clock/Station.swift", status: .modified, hunks: [
    hunk(1, start: 10, [" final class Station {", "-    var old = 1", "+    var new = 2", " }"]),
    hunk(2, start: 40, [" func resync() {", "+    let skew = clock.skew", "+    apply(skew)", " }"]),
    hunk(3, start: 80, [" // tail", "-gone()"]),
])
private let drift = DiffFile(path: "Sources/Clock/Drift.swift", status: .added, hunks: [
    hunk(1, ["+struct Drift {}"]),
])
private let moved = DiffFile(path: "Docs/New Name.md", oldPath: "Docs/Old.md", status: .renamed, hunks: [])
private let diff = Diff(range: "a...b", base: "base", head: "head", files: [station, drift, moved],
                        excluded: [Exclusion(pattern: "*.png", files: ["Assets/icon.png"])])

private func story(_ sections: [String: [String]], order: [String]) throws -> Story {
    var text = "---\ntitle: T\n---\n"
    for id in order {
        text += "## \(id)\n"
        if let selectors = sections[id] { text += "```hunks\n" + selectors.joined(separator: "\n") + "\n```\n" }
    }
    return try StoryParser.parse(text, url: URL(fileURLWithPath: "/tmp/s.md"))
}

private func problems(_ sections: [String: [String]], order: [String]? = nil) throws -> [String] {
    let s = try story(sections, order: order ?? sections.keys.sorted())
    return Resolver.analyze(s, against: diff).problems.map(\.description)
}

private let everything = ["Station.swift", "Drift.swift", "\"Docs/New Name.md\""]

@Suite struct ResolverTests {
    @Test func completeStoryResolves() throws {
        let s = try story(["a": ["Station.swift #2", "Drift.swift"], "b": ["Station.swift #1,3", "\"New Name.md\"", "Station.swift #2 again"], "c": []],
                          order: ["a", "b", "c"])
        let resolved = try Resolver.resolve(s, against: diff)
        #expect(resolved.sections.map(\.section.id) == ["a", "b", "c"])
        #expect(resolved.sections[0].code == [
            .hunk(file: station, hunk: station.hunks[1], lines: 0..<4, again: false),
            .hunk(file: drift, hunk: drift.hunks[0], lines: 0..<1, again: false),
        ])
        #expect(resolved.sections[1].code == [
            .hunk(file: station, hunk: station.hunks[0], lines: 0..<4, again: false),
            .hunk(file: station, hunk: station.hunks[2], lines: 0..<2, again: false),
            .fileChange(file: moved, again: false),
            .hunk(file: station, hunk: station.hunks[1], lines: 0..<4, again: true),
        ])
        #expect(resolved.sections[2].code == [])
    }

    @Test func anchorPicksEveryHunkContainingTheText() throws {
        let s = try story(["a": ["Station.swift @ \"}\"", "Station.swift #3", "Drift.swift", "\"New Name.md\""]], order: ["a"])
        let code = try Resolver.resolve(s, against: diff).sections[0].code
        #expect(code.prefix(2) == [
            .hunk(file: station, hunk: station.hunks[0], lines: 0..<4, again: false),
            .hunk(file: station, hunk: station.hunks[1], lines: 0..<4, again: false),
        ])
    }

    @Test func linePicksPlaceOnlyTheirLines() throws {
        let s = try story(["a": ["Station.swift #1 lines 2-3", "Station.swift @ \"let skew\" to \"apply\""],
                           "b": ["Station.swift #3", "Drift.swift", "\"New Name.md\""]],
                          order: ["a", "b"])
        let resolved = try Resolver.resolve(s, against: diff)
        #expect(resolved.sections[0].code == [
            .hunk(file: station, hunk: station.hunks[0], lines: 1..<3, again: false),
            .hunk(file: station, hunk: station.hunks[1], lines: 1..<3, again: false),
        ])
    }

    @Test func doublePlacementIsAProblemUnlessAgain() throws {
        #expect(try problems(["a": everything, "b": ["Station.swift #1"]]) ==
                ["b: Station.swift #1: 'Sources/Clock/Station.swift' #1: 2 changed lines already placed in section 'a'"])
        #expect(try problems(["a": everything, "b": ["Station.swift #1 again", "\"New Name.md\" again"]]) == [])
        #expect(try problems(["a": everything, "b": ["\"New Name.md\""]]) ==
                ["b: \"New Name.md\": 'Docs/New Name.md' (renamed from Docs/Old.md) is already placed in section 'a'"])
    }

    @Test func contextLinesMayBeShownTwice() throws {
        #expect(try problems(["a": everything, "b": ["Station.swift #1 lines 1-1", "Station.swift #1 lines 4-4"]]) == [])
    }

    @Test func unplacedLinesAndFileChangesInDiffOrder() throws {
        #expect(try problems(["a": ["Station.swift #1,2"]]) == [
            "unplaced: Sources/Clock/Station.swift #3 81/-: gone()",
            "unplaced: Sources/Clock/Drift.swift #1 -/1: struct Drift {}",
            "unplaced: Docs/New Name.md (renamed from Docs/Old.md)",
        ])
    }

    @Test func wholeUnplacedHunksAreSummarised() throws {
        let file = DiffFile(path: "New.swift", status: .added, hunks: [Hunk(
            number: 1, header: "", oldStart: 0, oldCount: 0, newStart: 1, newCount: 4,
            lines: (1...4).map { DiffLine(kind: .add, old: nil, new: $0, text: "line \($0)") })])
        let diff = Diff(range: "a..b", base: "a", head: "b", files: [file], excluded: [])
        let story = Story(url: URL(fileURLWithPath: "/s.md"), title: "T")
        #expect(Resolver.analyze(story, against: diff).problems.map(\.description)
            == ["unplaced: New.swift #1 (all of it: +4 -0)"])
    }

    @Test func sectionProblemsComeBeforeUnplacedInStoryOrder() throws {
        let found = try problems(["z": ["Nope.swift"], "a": ["Station.swift #9"]], order: ["z", "a"])
        #expect(found.prefix(2) == [
            "z: Nope.swift: matches no file in the diff",
            "a: Station.swift #9: 'Sources/Clock/Station.swift' has 3 hunks; there is no #9",
        ])
        #expect(found.dropFirst(2).allSatisfy { $0.hasPrefix("unplaced: ") })
    }

    @Test(arguments: [
        ("icon.png", "matches no file in the diff: 'Assets/icon.png' is excluded by '*.png'"),
        ("ation.swift", "matches no file in the diff"),
        ("Clock/Station.swift @ \"nothing\"", "no hunk of 'Sources/Clock/Station.swift' contains \"nothing\""),
        ("Station.swift lines 1-2", "'lines' needs exactly one hunk, but the selector picks 3"),
        ("Station.swift #2 lines 3-9", "lines 3-9 fall outside 'Sources/Clock/Station.swift' #2, which has 4 lines"),
        ("Station.swift @ \"skew\" to \"}\"", "\"skew\" is on 2 lines of the new side of 'Sources/Clock/Station.swift' (#2 -/41, #2 -/42); it must be unique"),
        ("Station.swift @ \"absent\" to \"}\"", "no line of 'Sources/Clock/Station.swift' contains \"absent\""),
        ("Station.swift @ \"apply(\" to \"tail\"", "no line from \"apply(\" (#2 -/42) to the end of 'Sources/Clock/Station.swift' #2 contains \"tail\""),
        ("\"New Name.md\" #1", "'Docs/New Name.md' is a file change without hunks (renamed from Docs/Old.md); select it by path alone"),
        ("Old.md", "matches no file in the diff"),
    ])
    func selectorProblem(selector: String, expected: String) throws {
        let found = try problems(["a": everything + [selector]])
        #expect(found == ["a: \(selector): \(expected)"])
    }

    @Test func ambiguousSuffix() throws {
        let other = DiffFile(path: "Legacy/Station.swift", status: .modified, hunks: [hunk(1, ["+x"])])
        let twoStations = Diff(range: "r", base: "b", head: "h", files: [station, other], excluded: [])
        let s = try story(["a": ["Station.swift", "Legacy/Station.swift", "Clock/Station.swift"]], order: ["a"])
        let found = Resolver.analyze(s, against: twoStations).problems.map(\.description)
        #expect(found == ["a: Station.swift: matches 2 files: Sources/Clock/Station.swift, Legacy/Station.swift; write more of the path"])
    }

    @Test func exactPathWinsOverSuffix() throws {
        let top = DiffFile(path: "Station.swift", status: .added, hunks: [hunk(1, ["+y"])])
        let d = Diff(range: "r", base: "b", head: "h", files: [station, top], excluded: [])
        let s = try story(["a": ["Station.swift", "Clock/Station.swift"]], order: ["a"])
        #expect(Resolver.analyze(s, against: d).problems == [])
    }

    @Test func placementsNameTheSection() throws {
        let s = try story(["a": ["Station.swift #2"], "b": ["\"New Name.md\""]], order: ["a", "b"])
        let placements = Resolver.analyze(s, against: diff).placements
        #expect(placements.sectionID(file: station, hunk: station.hunks[1], index: 1) == "a")
        #expect(placements.sectionID(file: station, hunk: station.hunks[1], index: 0) == nil)
        #expect(placements.sectionID(file: station, hunk: station.hunks[0], index: 1) == nil)
        #expect(placements.sectionID(fileChange: moved) == "b")
    }
}
