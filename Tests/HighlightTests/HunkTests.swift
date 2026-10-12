import Foundation
import Testing
import ReviewGuideCore
@testable import Highlight

private func hunk(_ lines: [DiffLine]) -> Hunk {
    Hunk(number: 1, header: "", oldStart: 1, oldCount: 0, newStart: 1, newCount: 0, lines: lines)
}

private func reader(_ blobs: [String: String]) -> Highlighter.BlobReader {
    { rev, path in blobs["\(rev):\(path)"].map { Data($0.utf8) } }
}

@Test func hunkInsideABlockCommentOpenedAboveItIsComment() {
    let new = "/* Opened above the hunk\n   let notCode = 1\n*/\nlet code = 2\n"
    let file = DiffFile(path: "A.swift", status: .modified, hunks: [])
    let shown = hunk([
        DiffLine(kind: .context, old: 2, new: 2, text: "   let notCode = 1"),
        DiffLine(kind: .add, old: nil, new: 4, text: "let code = 2"),
    ])
    let highlighter = Highlighter(diff: emptyDiff, readBlob: reader(["head:A.swift": new]))
    let lines = highlighter.styles(for: file, hunk: shown)
    #expect(lines[0] == [StyledRun(bytes: 0..<18, capture: "comment")])
    #expect(capture(of: "let", in: "let code = 2", lines: [lines[1]]) == "keyword")
}

@Test func deletedLineTakesStylingFromTheOldBlob() {
    let old = "let s = \"\"\"\nlet y = 1\n\"\"\"\n"
    let new = "let s = \"\"\nlet y = 1\n"
    let file = DiffFile(path: "B.swift", oldPath: "Old.swift", status: .renamed, hunks: [])
    let shown = hunk([
        DiffLine(kind: .del, old: 2, new: nil, text: "let y = 1"),
        DiffLine(kind: .add, old: nil, new: 2, text: "let y = 1"),
    ])
    let highlighter = Highlighter(diff: emptyDiff, readBlob: reader(["base:Old.swift": old, "head:B.swift": new]))
    let lines = highlighter.styles(for: file, hunk: shown)
    #expect(lines[0].map(\.capture) == ["string"])
    #expect(lines[1].first?.capture == "keyword")
}

@Test func addedAndDeletedFilesReadOnlyTheSideTheyHave() {
    let calls = Calls()
    let highlighter = Highlighter(diff: emptyDiff, readBlob: { rev, path in
        calls.append("\(rev):\(path)")
        return Data("let x = 1\n".utf8)
    })
    _ = highlighter.styles(for: DiffFile(path: "N.swift", status: .added, hunks: []),
                           hunk: hunk([DiffLine(kind: .add, old: nil, new: 1, text: "let x = 1")]))
    _ = highlighter.styles(for: DiffFile(path: "D.swift", status: .deleted, hunks: []),
                           hunk: hunk([DiffLine(kind: .del, old: 1, new: nil, text: "let x = 1"),
                                       DiffLine(kind: .del, old: 1, new: nil, text: "let x = 1")]))
    #expect(calls.values == ["head:N.swift", "base:D.swift"])
}

@Test func lineThatDoesNotMatchItsBlobIsUnstyled() {
    let file = DiffFile(path: "C.swift", status: .modified, hunks: [])
    let highlighter = Highlighter(diff: emptyDiff, readBlob: reader(["head:C.swift": "let x = 1\n"]))
    let lines = highlighter.styles(for: file, hunk: hunk([
        DiffLine(kind: .add, old: nil, new: 1, text: "var y = 2"),
        DiffLine(kind: .add, old: nil, new: 7, text: "beyond the blob"),
    ]))
    #expect(lines == [[StyledRun(bytes: 0..<9)], [StyledRun(bytes: 0..<15)]])
}

@Test func crlfLinesKeepTheirStyling() {
    let file = DiffFile(path: "W.swift", status: .modified, hunks: [])
    let highlighter = Highlighter(diff: emptyDiff, readBlob: reader(["head:W.swift": "let x = 1\r\n"]))
    let lines = highlighter.styles(for: file, hunk: hunk([DiffLine(kind: .add, old: nil, new: 1, text: "let x = 1")]))
    #expect(lines[0].first == StyledRun(bytes: 0..<3, capture: "keyword"))
    #expect(lines[0].last?.bytes.upperBound == 9)
}

@Test func unreadableAndBinaryBlobsAreUnstyled() {
    struct Boom: Error {}
    let file = DiffFile(path: "E.swift", status: .modified, hunks: [])
    let shown = hunk([DiffLine(kind: .add, old: nil, new: 1, text: "let x")])
    let failing = Highlighter(diff: emptyDiff, readBlob: { _, _ in throw Boom() })
    #expect(failing.styles(for: file, hunk: shown) == [[StyledRun(bytes: 0..<5)]])
    let binary = Highlighter(diff: emptyDiff, readBlob: { _, _ in Data([0x6C, 0xFF, 0xFE]) })
    #expect(binary.styles(for: file, hunk: shown) == [[StyledRun(bytes: 0..<5)]])
}

@Test func shebangSelectsTheGrammar() {
    let file = DiffFile(path: "scripts/release", status: .modified, hunks: [])
    let highlighter = Highlighter(diff: emptyDiff, readBlob: reader(["head:scripts/release": "#!/bin/bash\nif true; then :; fi\n"]))
    let lines = highlighter.styles(for: file, hunk: hunk([DiffLine(kind: .add, old: nil, new: 2, text: "if true; then :; fi")]))
    #expect(lines[0].first?.capture == "keyword")
}

final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [String] = []
    func append(_ value: String) { lock.lock(); list.append(value); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return list }
}
