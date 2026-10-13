import Foundation
import Testing
@testable import StoryGrafterCore

private func hunk(number: Int = 1, start: Int, _ body: [String]) -> Hunk {
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
    return Hunk(number: number, header: "", oldStart: start, oldCount: old - start, newStart: start, newCount: new - start, lines: lines)
}

private let station = DiffFile(path: "Sources/Station.swift", status: .modified, hunks: [hunk(start: 10, [
    " func resync() {",
    "-    let skew = clock.offset(timeout: 5)",
    "+    let skew = clock.offset(timeout: 2)",
    "+    log(skew)",
    " }",
])])
private let drift = DiffFile(path: "Sources/Drift.swift", status: .added, hunks: [hunk(start: 1, ["+struct Drift { var skew = 0 }"])])
private let diff = Diff(range: "r", base: "b", head: "h", files: [station, drift], excluded: [])

private func analyze(_ body: String, selectors: [String] = ["Station.swift", "Drift.swift"]) throws -> Resolution {
    let text = "---\ntitle: T\n---\n## A\n\(body)\n```hunks\n\(selectors.joined(separator: "\n"))\n```\n"
    return Resolver.analyze(try StoryParser.parse(text, url: URL(fileURLWithPath: "/tmp/s.md")), against: diff)
}

@Suite struct MarkerTests {
    @Test func scanFindsMarkersAndCodeSpansOutsideCodeBlocks() {
        let found = MarkerSyntax.scan("""
        Reads {@ "let skew"} then `log` and {@ Drift.swift "skew = 0"}.
        `{@ "not a marker"}`
        ```
        {@ "inside a fence"}
        ```
        A {@ bad} one.
        """)
        let kinds = found.map(\.kind)
        #expect(kinds == [
            .marker(path: nil, text: "let skew"), .codeSpan("log"), .marker(path: "Drift.swift", text: "skew = 0"),
            .codeSpan("{@ \"not a marker\"}"), .malformed("a marker is {@ \"text\"} or {@ path \"text\"}"),
        ])
    }

    @Test func markersResolveToTheNewSideAndNumberInReadingOrder() throws {
        let r = try analyze("Shorter {@ \"timeout: 2\"} and logged {@ \"log(skew)\"}.")
        #expect(r.problems == [])
        let markers = r.resolved.sections[0].markers
        #expect(markers.map(\.number) == [1, 2])
        #expect(markers[0].target == CodeTarget(code: 0, line: 2, bytes: 28..<38))
        #expect(markers[1].target?.line == 3)
    }

    @Test func aChangedLineResolvesToItsNewSide() throws {
        let r = try analyze("The skew {@ \"let skew\"}.")
        #expect(r.problems == [])
        #expect(r.resolved.sections[0].markers[0].target?.line == 2)
    }

    @Test func ambiguityAndMissesAreProblemsAndAPathNarrows() throws {
        let ambiguous = try analyze("{@ \"skew\"}")
        #expect(ambiguous.problems.first?.message.contains("is in 3 places") == true)
        let missing = try analyze("{@ \"nope\"}")
        #expect(missing.problems.first?.message == "\"nope\" is in no code that this section shows")
        let narrowed = try analyze("{@ Drift.swift \"skew\"}")
        #expect(narrowed.problems == [])
        #expect(narrowed.resolved.sections[0].markers[0].target?.code == 1)
    }

    @Test func codeSpansLinkOnlyWhenUnique() throws {
        let r = try analyze("`resync()` and `skew` and `Drift` and `x`.")
        let links = r.resolved.sections[0].codeLinks
        #expect(links["resync()"]?.line == 0)
        #expect(links["Drift"]?.code == 1)
        #expect(links["skew"] == nil && links["x"] == nil)
    }

    @Test func markersOutsideSectionProseAreProblems() throws {
        let text = "---\ntitle: T\n---\nSummary {@ \"skew\"}.\n## A\n```hunks\nStation.swift\nDrift.swift\n```\n# Appendix\n## Notes\nSee {@ \"skew\"}.\n"
        let r = Resolver.analyze(try StoryParser.parse(text, url: URL(fileURLWithPath: "/tmp/s.md")), against: diff)
        #expect(r.problems.map(\.sectionID) == ["summary", "notes"])
    }
}
