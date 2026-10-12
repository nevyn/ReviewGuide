import Foundation
import Testing
@testable import ReviewGuideCore

private let url = URL(fileURLWithPath: "/tmp/story.md")

private func problems(_ text: String) -> [String] {
    do {
        _ = try StoryParser.parse(text, url: url)
        return []
    } catch {
        return error.problems.map(\.description)
    }
}

private func story(_ body: String) throws -> Story {
    try StoryParser.parse("---\ntitle: T\n---\n" + body, url: url)
}

@Suite struct StoryParserTests {
    @Test func documentedExample() throws {
        let story = try StoryParser.parse(try Fixture.text("stories/example.md"), url: url)
        #expect(story.url == url)
        #expect(story.title == "Station clock drift fix")
        #expect(story.meta == "GL-1234 · iOS 9.12")
        #expect(story.range == "origin/main...HEAD")
        #expect(story.head == "4af1844a")
        #expect(story.exclude == ["*.png", "*.pbxproj"])
        #expect(story.summary == "Two sentences that summarise the change. Rendered in the page header.")
        #expect(story.footnotes == ["crash": "412 crashes in 9.11, all in `Station.resync()`."])

        #expect(story.sections == [
            Section(id: "the-bug-in-one-example", kicker: "Prologue", title: "The bug in one example",
                    body: "Prose. A claim with a source.[^crash]", selectors: nil, line: 10),
            Section(id: "primitive", kicker: "Chapter 1", title: "The new primitive",
                    body: "Prose.\n\n> [!QUESTION]\n> Should a skew above 5 s also log?",
                    selectors: [
                        Selector(source: "Sources/Clock/Drift.swift", path: "Sources/Clock/Drift.swift"),
                        Selector(source: "Station.swift @ \"func resync(\"", path: "Station.swift", hunks: .anchor("func resync(")),
                        Selector(source: "Station.swift #3 lines 1-12", path: "Station.swift", hunks: .numbers([3]), lines: .range(1, 12)),
                        Selector(source: "Station.swift @ \"let skew\" to \"}\"", path: "Station.swift",
                                 lines: .anchored(from: "let skew", to: "}")),
                        Selector(source: "Sources/Clock/Station.swift #1 again", path: "Sources/Clock/Station.swift",
                                 hunks: .numbers([1]), again: true),
                    ],
                    line: 15),
        ])
        #expect(story.appendix == [
            Section(id: "backend-payload", title: "Backend payload",
                    body: "```json attachment \"GET /stations, anonymised\"\n{\"id\": 1, \"skew_ms\": 5200}\n```", line: 31),
        ])
    }

    @Test func selectorForms() throws {
        let s = try story("""
        ## S
        ```hunks
        "My File.swift" #2-4   # a comment
        a.swift #1,3,5
        a.swift #1,3-4 lines 2
        "quo\\"te\\\\.txt" @"x # y" again
        # whole-line comment

        b.swift#3
        ```
        """)
        let selectors = try #require(s.sections.first?.selectors)
        #expect(selectors.map(\.path) == ["My File.swift", "a.swift", "a.swift", "quo\"te\\.txt", "b.swift#3"])
        #expect(selectors[0].hunks == .numbers([2, 3, 4]) && selectors[0].source == "\"My File.swift\" #2-4")
        #expect(selectors[1].hunks == .numbers([1, 3, 5]))
        #expect(selectors[2].hunks == .numbers([1, 3, 4]) && selectors[2].lines == .range(2, 2))
        #expect(selectors[3].hunks == .anchor("x # y") && selectors[3].again)
    }

    @Test func sectionWithoutFenceHasNoSelectorsAndEmptyFenceHasNone() throws {
        let s = try story("## A\ntext\n## B\n```hunks\n```\n")
        #expect(s.sections[0].selectors == nil)
        #expect(s.sections[1].selectors == [])
    }

    @Test func slugs() throws {
        let s = try story("## Ch 2 · Où est   la Gare?!\n## __Dashes--and Spaces__\n### not a section\n")
        #expect(s.sections.map(\.id) == ["o-est-la-gare", "dashes-and-spaces"])
        #expect(s.sections[1].body == "### not a section")
    }

    @Test func closingHashesAreNotPartOfTheTitle() throws {
        let s = try story("## Title ##\n")
        #expect(s.sections[0].title == "Title")
    }

    @Test func fencesInsideCodeBlocksAreIgnored() throws {
        let s = try story("""
        ## Real
        ````markdown
        # Not a heading
        ## Not a section
        ```hunks
        not/a/selector.swift
        ```
        ````
        ~~~
        ## Still code
        ~~~
        """)
        #expect(s.sections.count == 1)
        #expect(s.sections[0].selectors == nil)
        #expect(s.sections[0].body.contains("## Not a section"))
        #expect(s.sections[0].body.contains("## Still code"))
    }

    @Test func footnotesWithContinuationLines() throws {
        let s = try story("""
        Summary.[^a]

        [^a]: First line
            second line

            after a blank
        Back in the summary.
        ## S
        Text.[^b]
        [^b]: B
        """)
        #expect(s.footnotes == ["a": "First line\nsecond line\n\nafter a blank", "b": "B"])
        #expect(s.summary == "Summary.[^a]\n\nBack in the summary.")
        #expect(s.sections[0].body == "Text.[^b]")
    }

    @Test func emptyExcludeList() throws {
        let s = try StoryParser.parse("---\ntitle: \"Quoted: \\\"T\\\"\"\nexclude: []\n---\n", url: url)
        #expect(s.title == "Quoted: \"T\"" && s.exclude == [])
    }

    @Test(arguments: [
        ("title: T\n", "line 1: a story starts with a '---' front matter block that sets 'title'"),
        ("---\ntitle: T\n", "line 1: the front matter is never closed with '---'"),
        ("---\nmeta: M\n---\n", "line 1: the front matter has no 'title'"),
        ("---\ntitle: T\ncolour: red\n---\n", "line 3: unknown front matter key 'colour'; the keys are title, meta, range, head and exclude"),
        ("---\ntitle: T\nexclude: *.png\n---\n", "line 3: 'exclude' must be a list of quoted globs, like [\"*.png\"]"),
        ("---\ntitle: T\ntitle: U\n---\n", "line 3: front matter key 'title' is set twice (also line 2)"),
        ("---\ntitle: T\n---\n# Intro\n", "line 4: '# Intro' is not allowed: the only level-1 heading is '# Appendix'"),
        ("---\ntitle: T\n---\n## A\n## A\n", "line 5: duplicate section id 'a' (also line 4); set another with {#id}"),
        ("---\ntitle: T\n---\n## A {#x y}\n", "line 4: section id 'x y' may only contain ASCII letters, digits, '-' and '_'"),
        ("---\ntitle: T\n---\n## Åäö\n", "line 4: title 'Åäö' has no ASCII letters or digits to make an id from; add {#id}"),
        ("---\ntitle: T\n---\n## A\n```hunks\n```\n```hunks\n```\n", "line 7: section 'a' has a second hunks fence (first at line 5)"),
        ("---\ntitle: T\n---\n# Appendix\n## A\n```hunks\nx\n```\n", "line 6: appendix sections place no code, so they cannot have a hunks fence"),
        ("---\ntitle: T\n---\n```hunks\nx\n```\n", "line 4: hunks fence before the first section"),
        ("---\ntitle: T\n---\n## A\n```swift\n", "line 5: code fence ``` is never closed"),
        ("---\ntitle: T\n---\n[^a]: x\n[^a]: y\n", "line 5: footnote [^a] is defined twice (also line 4)"),
    ])
    func syntaxProblem(text: String, expected: String) {
        #expect(problems(text) == [expected])
    }

    @Test(arguments: [
        ("x.swift #0", "'#0' is not a hunk list like #3, #2-4 or #1,3,5"),
        ("x.swift #3-2", "'#3-2' is not a hunk list like #3, #2-4 or #1,3,5"),
        ("x.swift @ nope", "'@' must be followed by a quoted anchor, like @ \"func resync(\""),
        ("x.swift @ \"\"", "the anchor is empty"),
        ("x.swift @ \"a\" to", "'to' must be followed by a quoted anchor"),
        ("x.swift @ \"a\" to \"b\" lines 1-2", "a selector has either 'lines' or '@ … to …', not both"),
        ("x.swift lines 3-1", "'lines' must be followed by a range like 5-12"),
        ("x.swift again #1", "unexpected '#1'; the form is <path> [#n | @ \"text\"] [lines a-b | to \"text\"] [again]"),
        ("\"x.swift", "unterminated quote in \"x.swift"),
        ("x.swift @ \"a\\n\"", "unknown escape '\\n' in \"a\\n\"; only \\\" and \\\\ are escapes"),
        ("@ \"a\"", "a selector starts with a path"),
    ])
    func selectorProblem(selector: String, expected: String) {
        let found = problems("---\ntitle: T\n---\n## S\n```hunks\n\(selector)\n```\n")
        #expect(found.count == 1)
        #expect(found.first?.hasPrefix("s: ") == true)
        #expect(found.first?.hasSuffix("line 6: \(expected)") == true, "\(found)")
    }

    @Test func allProblemsAreReported() {
        let found = problems("---\ntitle: T\n---\n# Bad\n## A\n```hunks\nx #0\ny @\n```\n## A\n")
        #expect(found.count == 4)
        #expect(found.map { $0.contains("line 4") || $0.contains("line 7") || $0.contains("line 8") || $0.contains("line 10") }.allSatisfy { $0 })
    }
}
