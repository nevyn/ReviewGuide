import Foundation
import Testing
import StoryGrafterCore
@testable import Render

private func prose(_ footnotes: [String: String] = [:], url: URL = storyURL, styler: any LineStyling = PlainStyler()) -> Prose {
    Prose(story: Story(url: url, title: "T", footnotes: footnotes), styler: styler)
}

private func scope(_ id: String) -> Prose.Scope { .init(anchor: id, sectionID: id) }

private var fixtures: URL { Bundle.module.url(forResource: "Fixtures", withExtension: nil)! }

@Test func gfmTablesStrikethroughAutolinksAndRawHTML() {
    let html = prose().render("""
        | a | b |
        |---|---|
        | 1 | 2 |

        ~~gone~~ https://example.com <kbd>K</kbd>
        """, in: scope("s"))
    #expect(html.contains("<table>"))
    #expect(html.contains("<del>gone</del>"))
    #expect(html.contains("<a href=\"https://example.com\">"))
    #expect(html.contains("<kbd>K</kbd>"))
}

@Test func footnotesNumberGloballyByFirstReference() {
    let p = prose(["a": "Note A.", "b": "Note *B*."])
    let first = p.render("Uses b[^b] then a[^a] then b[^b].", in: scope("one"))
    let second = p.render("Only a[^a].", in: scope("two"))
    #expect(p.problems.isEmpty)
    #expect(first.contains("<sup class=\"fnref\"><a href=\"#fn-one-1\" id=\"fnref-one-1\">1</a></sup>"))
    #expect(first.contains("id=\"fnref-one-1-2\""))
    #expect(first.contains("<li value=\"2\" id=\"fn-one-2\">Note A."))
    #expect(first.contains("<li value=\"1\" id=\"fn-one-1\">Note <em>B</em>."))
    #expect(first.count(of: "<li ") == 2)
    #expect(second.contains("<a href=\"#fn-two-2\" id=\"fnref-two-2\">2</a>"))
    #expect(second.contains("<li value=\"2\" id=\"fn-two-2\">Note A. <a href=\"#fnref-two-2\" class=\"fnback\""))
    #expect(second.count(of: "<li ") == 1)
}

@Test func footnoteReferenceInCodeIsNotAReference() {
    let p = prose()
    let html = p.render("Literal `[^x]` and\n\n```\n[^y]\n```", in: scope("s"))
    #expect(p.problems.isEmpty)
    #expect(html.contains("<code>[^x]</code>"))
    #expect(!html.contains("notes"))
}

@Test func undefinedFootnoteNamesIdAndSection() {
    let p = prose(["a": "A"])
    _ = p.render("See[^missing].", in: scope("chapter-2"))
    _ = p.render("Summary[^gone].", in: .init(anchor: "summary", sectionID: nil))
    #expect(p.problems == [
        StoryProblem(sectionID: "chapter-2", message: "footnote [^missing] is not defined"),
        StoryProblem(sectionID: nil, message: "summary: footnote [^gone] is not defined"),
    ])
}

@Test(arguments: [("NOTE", "note", "Note"), ("WARNING", "warning", "Warning"), ("QUESTION", "question", "Open question")])
func alerts(kind: String, css: String, label: String) {
    let html = prose().render("> [!\(kind)]\n> Body *text*.\n\nAfter.", in: scope("s"))
    #expect(html.contains("<div class=\"alert alert-\(css)\"><p class=\"alert-title\">\(label)</p>"))
    #expect(html.contains("<p>Body <em>text</em>.</p>\n</div>"))
    #expect(!html.contains("blockquote"))
    #expect(!html.contains("[!"))
}

@Test func otherBlockquotesStayBlockquotes() {
    let html = prose().render("> [!TIP]\n> Body.\n\n> Plain.", in: scope("s"))
    #expect(html.count(of: "<blockquote>") == 2)
    #expect(html.contains("[!TIP]"))
}

@Test func codeBlocksAreHighlighted() {
    let html = prose(styler: WordStyler()).render("```swift\nlet a = \"<b>\"\n```", in: scope("s"))
    #expect(html.contains("<pre class=\"snippet\"><code><span class=\"hl-keyword\">let</span> <span class=\"hl-keyword\">a</span> <span class=\"hl-keyword\">=</span> <span class=\"hl-keyword\">&quot;&lt;b&gt;&quot;</span></code></pre>"))
}

@Test func inlineAttachment() {
    let p = prose(styler: WordStyler())
    let html = p.render("```json attachment \"GET /stations <anon>\"\n{\"id\": 1}\n```", in: scope("s"))
    #expect(p.problems.isEmpty)
    #expect(html.contains("<details class=\"attachment\"><summary>GET /stations &lt;anon&gt;</summary><pre class=\"snippet\"><code><span class=\"hl-keyword\">{&quot;id&quot;:</span>"))
    #expect(!html.contains("<details class=\"attachment\" open"))
}

@Test func fileAttachmentResolvesAgainstStoryDirectory() {
    let p = prose(url: fixtures.appendingPathComponent("story.md"))
    let html = p.render("```attachment \"Payload\" file=payload.json\n```", in: scope("s"))
    #expect(p.problems.isEmpty)
    #expect(html.contains("<summary>Payload</summary><pre class=\"snippet\"><code>{&quot;id&quot;: 1, &quot;skew_ms&quot;: 5200}</code></pre></details>"))
}

@Test func fileAttachmentTakesLanguageFromExtension() throws {
    #expect(try FenceInfo("attachment \"P\" file=\"dir/my file.json\"") == FenceInfo(language: "json", attachment: .init(caption: "P", file: "dir/my file.json")))
    #expect(try FenceInfo(#"attachment "a \"b\" \\c""#).attachment?.caption == #"a "b" \c"#)
    #expect(try FenceInfo("swift") == FenceInfo(language: "swift", attachment: nil))
    #expect(try FenceInfo("") == FenceInfo(language: "", attachment: nil))
    #expect(throws: FenceInfoError.self) { try FenceInfo("json attachment") }
}

@Test func missingAttachmentFileNamesPathAndSection() {
    let p = prose(url: fixtures.appendingPathComponent("story.md"))
    _ = p.render("```attachment \"Crash\" file=logs/crash.txt\n```", in: scope("prologue"))
    #expect(p.problems.count == 1)
    #expect(p.problems.first?.sectionID == "prologue")
    #expect(p.problems.first?.message.contains("file=logs/crash.txt not found at \(fixtures.path)/logs/crash.txt") == true)
}

extension FenceInfo {
    init(language: String, attachment: Attachment?) {
        self = try! FenceInfo("")
        self.language = language
        self.attachment = attachment
    }
}
