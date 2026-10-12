import Testing
import StoryGrafterCore
@testable import Render

@Test func escapesMarkup() {
    #expect(HTML.escape("a<b>&\"c\"") == "a&lt;b&gt;&amp;&quot;c&quot;")
    #expect(HTML.line("if a < b && c > d", runs: []) == "if a &lt; b &amp;&amp; c &gt; d")
}

@Test func nestedCaptureClassesAndChanged() {
    #expect(HTML.classes(capture: "string.special.url", changed: true) == "hl-string hl-string-special hl-string-special-url chg")
    #expect(HTML.classes(capture: nil, changed: true) == "chg")
    #expect(HTML.classes(capture: nil, changed: false) == nil)
    let line = HTML.line("let x", runs: [StyledRun(bytes: 0..<3, capture: "keyword"), StyledRun(bytes: 3..<4), StyledRun(bytes: 4..<5, changed: true)])
    #expect(line == "<span class=\"hl-keyword\">let</span> <span class=\"chg\">x</span>")
}

@Test func slicesByUTF8() {
    // å is 2 bytes, € is 3, 😀 is 4.
    let text = "å€😀"
    let runs = [StyledRun(bytes: 0..<2, capture: "a"), StyledRun(bytes: 2..<5, capture: "b"), StyledRun(bytes: 5..<9, capture: "c")]
    #expect(HTML.line(text, runs: runs) == "<span class=\"hl-a\">å</span><span class=\"hl-b\">€</span><span class=\"hl-c\">😀</span>")
}

@Test func runBoundaryInsideAScalarMovesToItsStart() {
    let text = "å€😀"
    let runs = [StyledRun(bytes: 0..<3, capture: "a"), StyledRun(bytes: 3..<7, capture: "b"), StyledRun(bytes: 7..<40, capture: "c")]
    #expect(HTML.line(text, runs: runs) == "<span class=\"hl-a\">å</span><span class=\"hl-b\">€</span><span class=\"hl-c\">😀</span>")
}

@Test func uncoveredBytesRenderPlain() {
    #expect(HTML.line("a<b c", runs: [StyledRun(bytes: 2..<3, capture: "x")]) == "a&lt;<span class=\"hl-x\">b</span> c")
    #expect(HTML.line("", runs: [StyledRun(bytes: 0..<4, capture: "x")]) == "")
}
