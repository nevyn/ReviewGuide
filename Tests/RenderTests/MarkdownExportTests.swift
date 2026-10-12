import Foundation
import Testing
import ReviewGuideCore
@testable import Render

private let file = DiffFile(path: "Sources/A.swift", status: .modified, hunks: [
    makeHunk(2, header: "func a() {", [ctx(1, 1, "one"), del(2, "two"), add(2, "TWO"), ctx(3, 3, "three"), ctx(4, 4, "four")]),
])

@Test func exportsHeaderSectionsAndDiffPrefixes() throws {
    let story = resolved(title: "Fix", summary: "Sum.", sections: [
        section("a", kicker: "Chapter 1", title: "First", body: "Body.", code: [.hunk(file: file, hunk: file.hunks[0], lines: 0..<5, again: false)]),
        section("b", title: "Partial", code: [
            .hunk(file: file, hunk: file.hunks[0], lines: 1..<3, again: true),
            .fileChange(file: DiffFile(path: "logo.png", status: .binary, hunks: []), again: false),
        ]),
    ], appendix: [Section(id: "x", title: "Extra", body: "More.", line: 5)],
       excluded: [Exclusion(pattern: "*.png", files: ["a.png", "b.png"]), Exclusion(pattern: "*.lock", files: [])])
    let md = try MarkdownRenderer().render(story)
    #expect(md.hasPrefix("# Fix\n\nGL-1 · iOS\n\n`origin/main...HEAD` · 2 files, +1 \u{2212}1\n\nSum.\n\nNot shown:\n\n- `*.png`: 2 files (`a.png`, `b.png`)\n- `*.lock`: 0 files\n\n"))
    #expect(md.contains("## Chapter 1 · First\n\nBody.\n\n`Sources/A.swift` #2\n\n```diff\n@@ -1,4 +1,4 @@ func a() {\n one\n-two\n+TWO\n three\n four\n```\n"))
    #expect(md.contains("## Partial\n\n`Sources/A.swift` #2 (again)\n\n```diff\n@@ -1,4 +1,4 @@ func a() {\n\u{22EF}\n-two\n+TWO\n\u{22EF}\n```\n\n`logo.png`: Binary file changed\n"))
    #expect(md.contains("# Appendix\n\n## Extra\n\nMore.\n"))
    #expect(md.hasSuffix("More.\n"))
}

@Test func fenceLengthEscalates() {
    #expect(MarkdownExport.fence(for: "plain") == "```")
    #expect(MarkdownExport.fence(for: "a ``` b") == "````")
    #expect(MarkdownExport.fence(for: "`````") == "``````")
    #expect(MarkdownExport.inlineCode("a`b") == "`` a`b ``")
}

@Test func diffBlockFenceOutgrowsBackticksInCode() throws {
    let f = DiffFile(path: "README.md", status: .added, hunks: [makeHunk(1, [add(1, "````swift")])])
    let md = try MarkdownRenderer().render(resolved(sections: [section("a", code: [.hunk(file: f, hunk: f.hunks[0], lines: 0..<1, again: false)])]))
    #expect(md.contains("`````diff\n@@ -0,0 +1,1 @@\n+````swift\n`````\n"))
}

@Test func footnoteDefinitionsAtTheEndInReferenceOrder() throws {
    let story = resolved(summary: "S[^z].", sections: [section("a", body: "A[^y] and `[^code]`."), section("b", body: "B[^z][^y].")],
                         footnotes: ["y": "Why.\nSecond line.", "z": "Zed.", "unused": "Never."])
    let md = try MarkdownRenderer().render(story)
    #expect(md.hasSuffix("B[^z][^y].\n\n[^z]: Zed.\n[^y]: Why.\n    Second line.\n"))
    #expect(!md.contains("Never."))
}

@Test func undefinedFootnoteFailsExport() {
    #expect(throws: StoryProblems([StoryProblem(sectionID: "a", message: "footnote [^nope] is not defined")])) {
        try MarkdownRenderer().render(resolved(sections: [section("a", body: "A[^nope].")]))
    }
}

@Test func attachmentsBecomeCaptionAndFence() throws {
    let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
    let story = resolved(sections: [section("a", body: """
        Before.

        ```md attachment "Inline"
        Has ```` inside.
        ```

        ```attachment "From file" file=payload.json
        ```

        After.
        """)], url: fixtures.appendingPathComponent("story.md"))
    let md = try MarkdownRenderer().render(story)
    #expect(md.contains("Before.\n\n**Inline**\n\n`````md\nHas ```` inside.\n`````\n\n**From file**\n\n```json\n{\"id\": 1, \"skew_ms\": 5200}\n```\n\nAfter."))
}
