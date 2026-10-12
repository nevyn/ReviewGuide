import Foundation
import ReviewGuideCore
@testable import Render

/// Returns no styling at all.
struct PlainStyler: LineStyling {
    func styles(for file: DiffFile, hunk: Hunk) -> [StyledLine] { hunk.lines.map { _ in [] } }
    func styles(source: String, language: String) -> [StyledLine] { source.split(separator: "\n", omittingEmptySubsequences: false).map { _ in [] } }
}

/// Marks every word `keyword`; on added and deleted lines, every other token is also `changed`.
struct WordStyler: LineStyling {
    func styles(for file: DiffFile, hunk: Hunk) -> [StyledLine] {
        hunk.lines.map { Self.style($0.text, changes: $0.isChange) }
    }
    func styles(source: String, language: String) -> [StyledLine] {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { Self.style(String($0), changes: false) }
    }
    static func style(_ text: String, changes: Bool) -> StyledLine {
        var runs: StyledLine = []
        var offset = 0
        for token in text.split(separator: " ", omittingEmptySubsequences: false) {
            let n = token.utf8.count
            if n > 0 { runs.append(StyledRun(bytes: offset..<offset + n, capture: "keyword", changed: changes && runs.count % 2 == 1)) }
            offset += n + 1
        }
        return runs
    }
}

/// Returns the given runs for every line.
struct FixedStyler: LineStyling {
    var runs: StyledLine
    func styles(for file: DiffFile, hunk: Hunk) -> [StyledLine] { hunk.lines.map { _ in runs } }
    func styles(source: String, language: String) -> [StyledLine] { source.split(separator: "\n", omittingEmptySubsequences: false).map { _ in runs } }
}

func ctx(_ old: Int, _ new: Int, _ text: String) -> DiffLine { DiffLine(kind: .context, old: old, new: new, text: text) }
func add(_ new: Int, _ text: String) -> DiffLine { DiffLine(kind: .add, old: nil, new: new, text: text) }
func del(_ old: Int, _ text: String) -> DiffLine { DiffLine(kind: .del, old: old, new: nil, text: text) }

func makeHunk(_ number: Int, header: String = "", _ lines: [DiffLine]) -> Hunk {
    let oldStart = lines.compactMap(\.old).first ?? 0
    let newStart = lines.compactMap(\.new).first ?? 0
    return Hunk(number: number, header: header, oldStart: oldStart, oldCount: lines.filter { $0.kind != .add }.count,
                newStart: newStart, newCount: lines.filter { $0.kind != .del }.count, lines: lines)
}

let storyURL = URL(fileURLWithPath: "/tmp/reviewguide-tests/story.md")

func section(_ id: String, kicker: String? = nil, title: String? = nil, body: String = "", code: [ShownCode]? = []) -> ResolvedSection {
    ResolvedSection(
        section: Section(id: id, kicker: kicker, title: title ?? id.capitalized, body: body,
                         selectors: code.map { _ in [] }, line: 1),
        code: code ?? [])
}

func resolved(title: String = "Title", summary: String = "", sections: [ResolvedSection], appendix: [Section] = [],
              footnotes: [String: String] = [:], files: [DiffFile]? = nil, excluded: [Exclusion] = [],
              url: URL = storyURL) -> ResolvedStory {
    let story = Story(url: url, title: title, meta: "GL-1 · iOS", range: "origin/main...HEAD", head: "0123456789abcdef",
                      summary: summary, sections: sections.map(\.section), appendix: appendix, footnotes: footnotes)
    let allFiles = files ?? sections.flatMap { $0.code.map { code -> DiffFile in
        switch code { case let .hunk(f, _, _, _), let .fileChange(f, _): f }
    } }
    var seen = Set<String>()
    let diff = Diff(range: "origin/main...HEAD", base: "fedcba9876543210", head: "0123456789abcdef",
                    files: allFiles.filter { seen.insert($0.path).inserted }, excluded: excluded)
    return ResolvedStory(story: story, diff: diff, sections: sections)
}

func renderHTML(_ story: ResolvedStory, styler: any LineStyling = PlainStyler()) throws -> String {
    try HTMLRenderer(styler: styler).render(story)
}

extension String {
    func count(of needle: String) -> Int { components(separatedBy: needle).count - 1 }
}
