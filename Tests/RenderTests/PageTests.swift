import Foundation
import Testing
import ReviewGuideCore
@testable import Render

private let station = DiffFile(path: "Sources/Clock/Station<&>.swift", status: .modified, hunks: [
    makeHunk(1, header: "func resync() {", [
        ctx(10, 10, "let a = 1"), del(11, "let b = 2"), add(11, "let b = 3"), ctx(12, 12, "let c = 4"), ctx(13, 13, "let d = 5"),
    ]),
])
private var stationHunk: Hunk { station.hunks[0] }

@Test func pageIsSelfContainedAndEscapesTitles() throws {
    let story = resolved(title: "Fix <drift> & more", sections: [
        section("intro", kicker: "Prologue", title: "A <b> title", code: [.hunk(file: station, hunk: stationHunk, lines: 0..<5, again: false)]),
    ])
    let html = try renderHTML(story)
    #expect(html.hasPrefix("<!doctype html>"))
    #expect(html.contains("<title>Fix &lt;drift&gt; &amp; more</title>"))
    #expect(html.contains("<h1>Fix &lt;drift&gt; &amp; more</h1>"))
    #expect(html.contains("<a class=\"self\" href=\"#intro\">A &lt;b&gt; title</a>"))
    #expect(html.contains("<a href=\"#intro\" data-section=\"intro\"><span>Prologue</span>A &lt;b&gt; title</a>"))
    #expect(html.contains("<span class=\"fname\">Station&lt;&amp;&gt;.swift</span><span class=\"fpath\">Sources/Clock/Station&lt;&amp;&gt;.swift</span>"))
    #expect(!html.contains("{{"))
    #expect(!html.contains("src=\"http"))
    #expect(!html.contains("<link"))
}

@Test func headerShowsRangeStatAndMeta() throws {
    let html = try renderHTML(resolved(sections: [section("a", code: [.hunk(file: station, hunk: stationHunk, lines: 0..<5, again: false)])]))
    #expect(html.contains("<div class=\"meta\">GL-1 · iOS</div>"))
    #expect(html.contains("<code>origin/main...HEAD</code> · 1 file, +1 \u{2212}1"))
    #expect(html.contains("Built from <code>origin/main...HEAD</code> at <code>01234567</code>"))
    #expect(html.contains("<body data-head=\"0123456789abcdef\">"))
}

@Test func hunkRowsAndSpans() throws {
    let html = try renderHTML(resolved(sections: [section("a", code: [.hunk(file: station, hunk: stationHunk, lines: 0..<5, again: false)])]),
                              styler: WordStyler())
    #expect(html.contains("<div class=\"ctx\">@@ -10,4 +10,4 @@ func resync() {</div>"))
    #expect(html.contains("<tr class=\"del\"><td class=\"ln\">11</td><td class=\"ln\"></td><td class=\"sg\">\u{2212}</td><td class=\"code\"><span class=\"hl-keyword\">let</span> <span class=\"hl-keyword chg\">b</span>"))
    #expect(html.contains("<tr class=\"add\"><td class=\"ln\"></td><td class=\"ln\">11</td><td class=\"sg\">+</td>"))
    #expect(html.contains("<tr><td class=\"ln\">10</td><td class=\"ln\">10</td><td class=\"sg\"></td><td class=\"code\"><span class=\"hl-keyword\">let</span>"))
    #expect(!html.contains("tr class=\"gap\""))
}

@Test func escapesCode() throws {
    let file = DiffFile(path: "a.swift", status: .added, hunks: [makeHunk(1, [add(1, "if a < b && c > d {")])])
    let html = try renderHTML(resolved(sections: [section("a", code: [.hunk(file: file, hunk: file.hunks[0], lines: 0..<1, again: false)])]))
    #expect(html.contains("<td class=\"code\">if a &lt; b &amp;&amp; c &gt; d {</td>"))
    #expect(html.contains("<span class=\"badge badge-added\">added</span>"))
}

@Test func partialHunkGetsGapRows() throws {
    let html = try renderHTML(resolved(sections: [section("a", code: [.hunk(file: station, hunk: stationHunk, lines: 1..<3, again: false)])]))
    #expect(html.count(of: "<tr class=\"gap\">") == 2)
    #expect(!html.contains("let a = 1"))
    #expect(!html.contains("let c = 4"))
    let head = try renderHTML(resolved(sections: [section("a", code: [.hunk(file: station, hunk: stationHunk, lines: 0..<3, again: false)])]))
    #expect(head.count(of: "<tr class=\"gap\">") == 1)
    #expect(head.range(of: "let b = 3")!.lowerBound < head.range(of: "<tr class=\"gap\">")!.lowerBound)
}

@Test func againLinksToPlacingSection() throws {
    let html = try renderHTML(resolved(sections: [
        section("first", kicker: "Chapter 1", title: "Places", code: [.hunk(file: station, hunk: stationHunk, lines: 0..<5, again: false)]),
        section("second", title: "Revisits", code: [.hunk(file: station, hunk: stationHunk, lines: 1..<2, again: true)]),
    ]))
    #expect(html.contains("<div class=\"hunk again\">"))
    #expect(html.contains("<span class=\"again-note\">shown again · placed in <a href=\"#first\">Chapter 1 · Places</a></span>"))
}

@Test func againOverContextOnlyHasNoLink() throws {
    let html = try renderHTML(resolved(sections: [
        section("first", code: [.hunk(file: station, hunk: stationHunk, lines: 0..<5, again: false)]),
        section("second", code: [.hunk(file: station, hunk: stationHunk, lines: 3..<5, again: true)]),
    ]))
    #expect(html.contains("<span class=\"again-note\">shown again</span>"))
}

@Test(arguments: [
    (DiffFile(path: "img/logo.png", status: .binary, hunks: []), "Binary file changed", "binary"),
    (DiffFile(path: "new/Name.swift", oldPath: "old/Name.swift", status: .renamed, hunks: []), "Renamed from old/Name.swift", "renamed from old/Name.swift"),
    (DiffFile(path: "run.sh", status: .mode, hunks: []), "Mode changed", "mode changed"),
])
func fileChangeCards(file: DiffFile, text: String, badge: String) throws {
    let html = try renderHTML(resolved(sections: [
        section("a", code: [.fileChange(file: file, again: false)]),
        section("b", title: "Again", code: [.fileChange(file: file, again: true)]),
    ]))
    #expect(html.count(of: "<div class=\"fc\">\(text)</div>") == 2)
    #expect(html.contains("<span class=\"badge badge-\(file.status.rawValue)\">\(badge)</span>"))
    #expect(html.contains("<div class=\"hunk filechange again\">"))
    #expect(html.contains("placed in <a href=\"#a\">A</a>"))
}

@Test func exclusionsAreListedWithTheirFiles() throws {
    let html = try renderHTML(resolved(sections: [section("a")], files: [], excluded: [
        Exclusion(pattern: "*.png", files: ["a.png", "b<1>.png"]),
        Exclusion(pattern: "*.pbxproj", files: []),
    ]))
    #expect(html.contains("Not shown: <span class=\"excl\" title=\"a.png\nb&lt;1&gt;.png\"><code>*.png</code> 2 files</span>, <span class=\"excl\"><code>*.pbxproj</code> 0 files</span>"))
    let none = try renderHTML(resolved(sections: [section("a")], files: []))
    #expect(!none.contains("Not shown"))
}

@Test func sectionsWithoutSelectorsAndAppendixAreFullWidth() throws {
    let html = try renderHTML(resolved(
        sections: [section("prose-only", code: nil), section("coded", code: [.hunk(file: station, hunk: stationHunk, lines: 0..<5, again: false)])],
        appendix: [Section(id: "payload", kicker: "Research", title: "Backend payload", body: "Text.", line: 30)]))
    #expect(html.contains("<section id=\"prose-only\" class=\"full\">"))
    #expect(html.contains("<section id=\"coded\">"))
    #expect(html.contains("<div class=\"divider\" id=\"appendix\">Appendix</div>\n<section id=\"payload\" class=\"full appendix\">"))
    #expect(html.contains("<a href=\"#payload\" data-section=\"payload\"><span>Research</span>Backend payload</a>"))
    #expect(html.count(of: "<div class=\"code\">") == 1)
}

@Test func reviewedCheckboxPerSection() throws {
    let html = try renderHTML(resolved(sections: [section("a"), section("b", code: nil)],
                                       appendix: [Section(id: "c", title: "C", body: "", line: 1)]))
    #expect(html.count(of: "<input type=\"checkbox\" class=\"reviewed\"") == 3)
    #expect(html.contains("data-section=\"b\" title=\"Reviewed\""))
    #expect(html.contains("\"reviewguide:\" + head + \":\""))
}

@Test func footnotesAcrossSummarySectionsAndAppendix() throws {
    let story = resolved(summary: "Summary[^s].", sections: [
        section("one", body: "One[^x][^s]."),
        section("two", body: "Two[^x]."),
    ], appendix: [Section(id: "app", title: "App", body: "App[^y].", line: 9)],
       footnotes: ["s": "S", "x": "X", "y": "Y"])
    let html = try renderHTML(story)
    #expect(html.contains("<li value=\"1\" id=\"fn-summary-1\">S"))
    #expect(html.contains("<li value=\"2\" id=\"fn-one-2\">X"))
    #expect(html.contains("<li value=\"1\" id=\"fn-one-1\">S"))
    #expect(html.contains("<li value=\"2\" id=\"fn-two-2\">X"))
    #expect(html.contains("<li value=\"3\" id=\"fn-app-3\">Y"))
}

@Test func renderProblemsAreThrownTogether() {
    let story = resolved(summary: "S[^nope].", sections: [section("one", body: "```attachment \"Log\" file=missing.log\n```\nA[^gone].")])
    #expect {
        try renderHTML(story)
    } throws: { error in
        guard let problems = error as? StoryProblems else { return false }
        return problems.problems.map(\.description) == [
            "summary: footnote [^nope] is not defined",
            "one: attachment \"Log\": file=missing.log not found at /tmp/reviewguide-tests/missing.log",
            "one: footnote [^gone] is not defined",
        ]
    }
}
