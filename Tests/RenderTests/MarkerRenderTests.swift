import Foundation
import Testing
import StoryGrafterCore
@testable import Render

private let file = DiffFile(path: "Sources/Clock.swift", status: .modified, hunks: [makeHunk(1, [
    ctx(10, 10, "func resync() {"),
    del(11, "    let skew = offset(timeout: 5)"),
    add(11, "    let skew = offset(timeout: 2)"),
    ctx(12, 12, "}"),
])])

private func markedSection() -> ResolvedSection {
    var rs = section("a", body: "Shorter {@ \"timeout: 2\"} for `resync()`, in `code` too.",
                     code: [.hunk(file: file, hunk: file.hunks[0], lines: 0..<4, again: false)])
    rs.markers = [Marker(number: 1, target: CodeTarget(code: 0, line: 2, bytes: 22..<32))]
    rs.codeLinks = ["resync()": CodeTarget(code: 0, line: 0, bytes: 5..<11)]
    return rs
}

@Suite struct MarkerRenderTests {
    @Test func markerCirclesPairProseAndCode() throws {
        let html = try HTMLRenderer(styler: PlainStyler()).render(resolved(sections: [markedSection()], files: [file]))
        #expect(html.contains("<a class=\"mk mk-c0\" id=\"mkp-mk-a-1\" href=\"#mkt-mk-a-1\" data-mk=\"mk-a-1\">1</a>"))
        #expect(html.contains("<a class=\"mk mk-c0\" id=\"mkt-mk-a-1\" href=\"#mkp-mk-a-1\" data-mk=\"mk-a-1\">1</a><span class=\"mkt mk-c0\" data-mk=\"mk-a-1\">timeout: 2</span>"))
        #expect(!html.contains("{@"))
    }

    @Test func uniqueCodeSpansLinkToTheirTarget() throws {
        let html = try HTMLRenderer(styler: PlainStyler()).render(resolved(sections: [markedSection()], files: [file]))
        #expect(html.contains("<a class=\"cl\" href=\"#clt-cl-a-0\" data-cl=\"cl-a-0\"><code>resync()</code></a>"))
        #expect(html.contains("<span class=\"clt\" data-cl=\"cl-a-0\" id=\"clt-cl-a-0\">resync</span>"))
        #expect(html.contains("<code>code</code>"))
    }

    @Test func marksSplitStyledRunsWithoutNesting() {
        let runs: StyledLine = [StyledRun(bytes: 0..<3, capture: "keyword"), StyledRun(bytes: 4..<8, capture: "variable.builtin", changed: true)]
        let html = HTML.line("let skew", runs: runs, marks: [HTML.LineMark(bytes: 2..<6, id: "m", number: 2)])
        #expect(html == "<span class=\"hl-keyword\">le</span>"
            + "<a class=\"mk mk-c1\" id=\"mkt-m\" href=\"#mkp-m\" data-mk=\"m\">2</a>"
            + "<span class=\"hl-keyword mkt mk-c1\" data-mk=\"m\">t</span><span class=\"mkt mk-c1\" data-mk=\"m\"> </span>"
            + "<span class=\"hl-variable hl-variable-builtin chg mkt mk-c1\" data-mk=\"m\">sk</span>"
            + "<span class=\"hl-variable hl-variable-builtin chg\">ew</span>")
    }

    @Test func markdownExportCirclesMarkers() throws {
        let md = try MarkdownRenderer().render(resolved(sections: [markedSection()], files: [file]))
        #expect(md.contains("Shorter \u{2460} for `resync()`"))
        #expect(md.contains("+    let skew = offset(timeout: 2)  \u{2190} \u{2460}"))
    }

    @Test func codeSpansInsideLinksStayPlain() throws {
        var rs = markedSection()
        rs.section.body = "See [`resync()`](https://example.com/docs)."
        rs.markers = []
        let html = try HTMLRenderer(styler: PlainStyler()).render(resolved(sections: [rs], files: [file]))
        #expect(html.contains("<a href=\"https://example.com/docs\"><code>resync()</code></a>"))
        #expect(!html.contains("class=\"cl\""))
    }

    @Test func overlappingMarkerAndLinkKeepBothIds() {
        let html = HTML.line("let skew", runs: [], marks: [
            HTML.LineMark(bytes: 0..<8, id: "m", number: 1), HTML.LineMark(bytes: 4..<8, id: "c", number: nil),
        ])
        #expect(html.contains("<span class=\"mkt mk-c0 clt\" data-mk=\"m\" data-cl=\"c\" id=\"clt-c\">skew</span>"))
    }
}

