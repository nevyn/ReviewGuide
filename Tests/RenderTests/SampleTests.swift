import Foundation
import Testing
import StoryGrafterCore
@testable import Render

/// A small Swift-ish lexer standing in for the tree-sitter highlighter.
struct SampleStyler: LineStyling {
    static let keywords: Set<String> = ["let", "var", "func", "return", "if", "guard", "else", "struct", "final", "class",
                                        "import", "private", "public", "static", "self", "true", "false", "nil", "await", "throws"]

    func styles(for file: DiffFile, hunk: Hunk) -> [StyledLine] {
        var result = hunk.lines.map { Self.lex($0.text) }
        // Mark tokens changed between the n-th deleted and n-th added line of each replacement.
        var i = 0
        while i < hunk.lines.count {
            var dels: [Int] = [], adds: [Int] = []
            while i < hunk.lines.count, hunk.lines[i].kind == .del { dels.append(i); i += 1 }
            while i < hunk.lines.count, hunk.lines[i].kind == .add { adds.append(i); i += 1 }
            for (d, a) in zip(dels, adds) {
                let old = Self.tokens(hunk.lines[d].text), new = Self.tokens(hunk.lines[a].text)
                result[d] = Self.lex(hunk.lines[d].text, changed: Set(old.map(\.text)).subtracting(new.map(\.text)))
                result[a] = Self.lex(hunk.lines[a].text, changed: Set(new.map(\.text)).subtracting(old.map(\.text)))
            }
            if dels.isEmpty && adds.isEmpty { i += 1 }
        }
        return result
    }

    func styles(source: String, language: String) -> [StyledLine] {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { Self.lex(String($0)) }
    }

    static func tokens(_ text: String) -> [(text: String, bytes: Range<Int>, capture: String?)] {
        let bytes = Array(text.utf8)
        var out: [(String, Range<Int>, String?)] = []
        var i = 0
        func isWord(_ b: UInt8) -> Bool { b == 95 || (b >= 48 && b <= 57) || (b | 0x20 >= 97 && b | 0x20 <= 122) || b >= 0x80 }
        while i < bytes.count {
            let start = i
            var capture: String?
            if bytes[i] == 47, i + 1 < bytes.count, bytes[i + 1] == 47 {
                i = bytes.count; capture = "comment"
            } else if bytes[i] == 34 {
                i += 1
                while i < bytes.count, bytes[i] != 34 { i += bytes[i] == 92 ? 2 : 1 }
                i = min(i + 1, bytes.count); capture = "string"
            } else if isWord(bytes[i]) {
                while i < bytes.count, isWord(bytes[i]) { i += 1 }
                let word = String(decoding: bytes[start..<i], as: UTF8.self)
                if keywords.contains(word) { capture = "keyword" }
                else if word.first!.isNumber { capture = "number" }
                else if word.first!.isUppercase { capture = "type" }
                else if i < bytes.count, bytes[i] == 40 { capture = "function.method" }
                else if start > 0, bytes[start - 1] == 46 { capture = "property" }
            } else if bytes[i] == 32 {
                while i < bytes.count, bytes[i] == 32 { i += 1 }
            } else {
                i += 1
                capture = "+-*/=<>!&|".utf8.contains(bytes[start]) ? "operator" : "punctuation"
            }
            out.append((String(decoding: bytes[start..<i], as: UTF8.self), start..<i, capture))
        }
        return out
    }

    static func lex(_ text: String, changed: Set<String> = []) -> StyledLine {
        tokens(text).map { StyledRun(bytes: $0.bytes, capture: $0.capture, changed: !$0.text.allSatisfy(\.isWhitespace) && changed.contains($0.text)) }
    }
}

@Test func renderRichSample() throws {
    let clock = DiffFile(path: "Sources/Clock/Station.swift", status: .modified, hunks: [
        makeHunk(1, header: "final class Station {", [
            ctx(40, 40, "    /// Resynchronises against the reference clock."),
            ctx(41, 41, "    func resync() async throws {"),
            del(42, "        let skew = try await reference.offset(timeout: 5)"),
            add(42, "        let skew = try await reference.offset(timeout: 2) // tighter, see GL-1234"),
            ctx(43, 43, "        guard abs(skew) > threshold else { return }"),
            del(44, "        clock.adjust(by: skew)"),
            add(44, "        clock.slew(by: skew, over: .seconds(30))"),
            add(45, "        log.info(\"Slewing \\(skew) ms; caf\u{E9} \u{20AC} \u{1F600}\")"),
            ctx(45, 46, "    }"),
            ctx(46, 47, "}"),
        ]),
        makeHunk(2, header: "extension Station", [
            ctx(80, 81, "extension Station {"),
            del(81, "    static let threshold = 100"),
            add(82, "    static let threshold = 250 // ms"),
            ctx(82, 83, "}"),
        ]),
    ])
    let drift = DiffFile(path: "Sources/Clock/Drift.swift", status: .added, hunks: [
        makeHunk(1, [
            add(1, "import Foundation"), add(2, ""),
            add(3, "/// Skew between two clocks, in milliseconds."),
            add(4, "public struct Drift: Equatable, Sendable {"),
            add(5, "    public var milliseconds: Int"),
            add(6, "    public var isLarge: Bool { abs(milliseconds) > 5_000 && true }"),
            add(7, "}"),
        ]),
    ])
    let logo = DiffFile(path: "Resources/logo.png", status: .binary, hunks: [])
    let moved = DiffFile(path: "Sources/Clock/Reference.swift", oldPath: "Sources/Time/Reference.swift", status: .renamed, hunks: [])
    let script = DiffFile(path: "scripts/release.sh", status: .mode, hunks: [])

    let sections = [
        section("prologue", kicker: "Prologue", title: "The bug in one example", body: """
            Stations drifted by up to **5 s** after a long sleep.[^crash] The old code jumped the clock
            in one step, which broke every timer that was armed across the jump.

            > [!NOTE]
            > Only devices that sleep longer than an hour are affected.

            | Build | Crashes |
            |---|---|
            | 9.11 | 412 |
            | 9.12 beta | ~~37~~ 0 |
            """, code: nil),
        section("primitive", kicker: "Chapter 1", title: "A drift value type", body: """
            `Drift` wraps the skew so that the threshold check lives in one place.[^units]

            ```swift
            let d = Drift(milliseconds: 5200)
            if d.isLarge { station.resync() } // escalate
            ```
            """, code: [.hunk(file: drift, hunk: drift.hunks[0], lines: 0..<7, again: false)]),
        section("resync", kicker: "Chapter 2", title: "Slew instead of jump", body: """
            `resync()` now slews over 30 s and uses a shorter timeout.[^crash]

            > [!WARNING]
            > A slew longer than the heartbeat interval can still trip the watchdog.

            > [!QUESTION]
            > Should a skew above 5 s also log at `error` level?

            ```json attachment "GET /stations/42/clock, anonymised"
            {"id": 42, "skew_ms": 5200, "source": "ntp"}
            ```
            """, code: [
                .hunk(file: clock, hunk: clock.hunks[0], lines: 1..<8, again: false),
                .hunk(file: clock, hunk: clock.hunks[1], lines: 0..<4, again: false),
            ]),
        section("files", kicker: "Chapter 3", title: "Housekeeping", body: "A new logo, a moved file and an executable script.",
                code: [.fileChange(file: logo, again: false), .fileChange(file: moved, again: false), .fileChange(file: script, again: false)]),
        section("epilogue", kicker: "Epilogue", title: "Back to the slew", body: "The heart of the change once more.",
                code: [.hunk(file: clock, hunk: clock.hunks[0], lines: 2..<4, again: true)]),
    ]
    let story = resolved(
        title: "Station clock drift fix",
        summary: "Stations now **slew** their clock instead of jumping it, and the skew threshold moves to `Drift`.",
        sections: sections,
        appendix: [Section(id: "payload", kicker: "Research", title: "Crash excerpt", body: """
            The crash from 9.11, symbolicated.[^units]

            ```attachment "Crash log excerpt" file=payload.json
            ```
            """, line: 80)],
        footnotes: ["crash": "412 crashes in 9.11, all in `Station.resync()`.", "units": "Milliseconds throughout, as the backend sends them."],
        files: [clock, drift, logo, moved, script],
        excluded: [Exclusion(pattern: "*.pbxproj", files: ["App.xcodeproj/project.pbxproj"]), Exclusion(pattern: "*.xcstrings", files: [])],
        url: Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent("story.md"))

    let html = try renderHTML(story, styler: SampleStyler())
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("storygrafter-sample.html")
    try html.write(to: url, atomically: true, encoding: .utf8)
    print("Sample review guide: \(url.path)")
    #expect(html.contains("hl-function hl-function-method"))
    #expect(html.contains("class=\"hl-number chg\""))
}
