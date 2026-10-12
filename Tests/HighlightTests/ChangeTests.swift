import Foundation
import Testing
import StoryGrafterCore
@testable import Highlight

private func del(_ text: String) -> DiffLine { DiffLine(kind: .del, old: 1, new: nil, text: text) }
private func add(_ text: String) -> DiffLine { DiffLine(kind: .add, old: nil, new: 1, text: text) }
private func context(_ text: String) -> DiffLine { DiffLine(kind: .context, old: 1, new: 1, text: text) }

/// The changed text of each line, `nil` for an unpaired line.
private func changedText(_ lines: [DiffLine]) -> [[String]?] {
    let ranges = ChangeStyler.changedRanges(in: lines)
    return lines.indices.map { index in
        ranges[index].map { $0.map { String(decoding: Array(lines[index].text.utf8)[$0], as: UTF8.self) } }
    }
}

@Test func renamedIdentifierIsTheOnlyChange() {
    #expect(changedText([del("let count = 1"), add("let code = 1")]) == [["count"], ["code"]])
}

@Test func dissimilarLinesStayUnpaired() {
    #expect(changedText([del("let count = 1"), add("return view.frame.height")]) == [nil, nil])
}

@Test func pairsInOrderWithoutCrossing() {
    let lines = [
        context("{"),
        del("let width = frame.width"),
        del("let height = frame.height"),
        add("print(\"debug\")"),
        add("let width = bounds.width"),
        add("let height = bounds.height"),
        context("}"),
    ]
    #expect(changedText(lines) == [nil, ["frame"], ["frame"], nil, ["bounds"], ["bounds"], nil])
}

@Test func laterDeletedLinesNeverPairWithEarlierAdds() {
    let lines = [del("alpha beta gamma"), del("one two three"), add("one two four"), add("alpha beta delta")]
    #expect(changedText(lines) == [["gamma"], nil, nil, ["delta"]])
}

@Test func onlyDeletionsFollowedByAdditionsAreReplacements() {
    #expect(changedText([add("let a = 1"), del("let a = 2")]) == [nil, nil])
    #expect(changedText([del("let a = 1"), context("x"), add("let a = 2")]) == [nil, nil, nil])
}

@Test func whitespaceOnlyChangeIsMarked() {
    #expect(changedText([del("foo(a,  b)"), add("foo(a, b)")]) == [["  "], [" "]])
}

@Test func lineWithEveryWordChangedStaysUnpaired() {
    #expect(changedText([del("a = b"), add("x = y")]) == [nil, nil])
    #expect(changedText([del("alpha beta"), add("gamma delta")]) == [nil, nil])
}

@Test func multiByteTextKeepsScalarBoundaries() {
    let lines = [del("let s = \"åäö 😀\""), add("let s = \"åäõ 😀👍\"")]
    let ranges = ChangeStyler.changedRanges(in: lines)
    for (index, line) in lines.enumerated() {
        for range in ranges[index] ?? [] {
            #expect(String(bytes: Array(line.text.utf8)[range], encoding: .utf8) != nil)
        }
    }
    #expect(changedText(lines) == [["åäö"], ["åäõ", "👍"]])
}

@Test func tokenizerSplitsWordsSpacesAndPunctuation() {
    #expect(ChangeStyler.tokenize("a_b1  (x)é").map(\.text) == ["a_b1", "  ", "(", "x", ")", "é"].map { Substring($0) })
}

@Test func mergeSplitsSyntaxRunsAtChanges() {
    let runs = [StyledRun(bytes: 0..<3, capture: "keyword"), StyledRun(bytes: 3..<13)]
    let merged = ChangeStyler.merge(runs, changed: [4..<9])
    #expect(merged == [
        StyledRun(bytes: 0..<3, capture: "keyword"),
        StyledRun(bytes: 3..<4),
        StyledRun(bytes: 4..<9, changed: true),
        StyledRun(bytes: 9..<13),
    ])
}

@Test func hunkStylesCarryBothLayers() {
    let file = DiffFile(path: "A.swift", status: .modified, hunks: [])
    let shown = Hunk(number: 1, header: "", oldStart: 1, oldCount: 1, newStart: 1, newCount: 1, lines: [
        DiffLine(kind: .del, old: 1, new: nil, text: "let count = 1"),
        DiffLine(kind: .add, old: nil, new: 1, text: "let code = 1"),
    ])
    let highlighter = Highlighter(diff: emptyDiff, readBlob: { rev, _ in
        Data((rev == "base" ? "let count = 1\n" : "let code = 1\n").utf8)
    })
    let lines = highlighter.styles(for: file, hunk: shown)
    #expect(lines[0] == [
        StyledRun(bytes: 0..<3, capture: "keyword"), StyledRun(bytes: 3..<4),
        StyledRun(bytes: 4..<9, changed: true), StyledRun(bytes: 9..<10),
        StyledRun(bytes: 10..<11, capture: "operator"), StyledRun(bytes: 11..<12),
        StyledRun(bytes: 12..<13, capture: "number"),
    ])
    #expect(lines[1].filter(\.changed) == [StyledRun(bytes: 4..<8, changed: true)])
}
