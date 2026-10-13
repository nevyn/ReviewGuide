import Foundation
import StoryGrafterCore

/// Renders a resolved story as one self-contained HTML page: no external assets, fonts or scripts.
///
/// The page shows the header (title, meta, range, short stat, summary, exclusions), a sticky nav, one section per
/// story section with its prose beside its code, the appendix, and a footer. Only links that the author wrote point
/// elsewhere. Light and dark palettes follow `prefers-color-scheme`.
public struct HTMLRenderer {
    let styler: any LineStyling

    /// - Parameter styler: Styles every shown hunk line and every code block or attachment in the prose.
    public init(styler: any LineStyling) { self.styler = styler }

    /// The page as one HTML string.
    ///
    /// Throws `StoryProblems` listing every problem found: a footnote reference whose id has no definition, an
    /// attachment whose `file=` is missing or not UTF-8, or a malformed attachment info string. Each names its section.
    public func render(_ resolved: ResolvedStory) throws -> String {
        var page = Page(resolved: resolved, prose: Prose(story: resolved.story, styler: styler), styler: styler)
        let html = page.render()
        if !page.prose.problems.isEmpty { throw StoryProblems(page.prose.problems) }
        return html
    }
}

/// Builds the page; one instance per render.
struct Page {
    let resolved: ResolvedStory
    let prose: Prose
    let styler: any LineStyling

    var story: Story { resolved.story }
    var diff: Diff { resolved.diff }

    mutating func render() -> String {
        // Prose renders in page order so that footnotes number in order of first reference.
        let header = header()
        var body = resolved.sections.map(section).joined()
        if !story.appendix.isEmpty {
            body += "<div class=\"divider\" id=\"appendix\">Appendix</div>\n"
            body += story.appendix.map { appendixSection($0) }.joined()
        }
        return Template.fill([
            "TITLE": HTML.escape(story.title),
            "HEAD": HTML.escape(diff.head),
            "HEADER": header,
            "NAV": nav(),
            "BODY": body,
            "FOOTER": "Built from <code>\(HTML.escape(diff.range))</code> at <code>\(HTML.escape(Self.short(diff.head)))</code>",
        ])
    }

    static func short(_ sha: String) -> String { String(sha.prefix(8)) }

    /// "12 files, +340 −95".
    static func stat(_ diff: Diff) -> String {
        var adds = 0, dels = 0
        for file in diff.files { for hunk in file.hunks { for line in hunk.lines {
            if line.kind == .add { adds += 1 } else if line.kind == .del { dels += 1 }
        } } }
        let files = diff.files.count == 1 ? "1 file" : "\(diff.files.count) files"
        return "\(files), +\(adds) \u{2212}\(dels)"
    }

    private func header() -> String {
        var out = "<h1>\(HTML.escape(story.title))</h1>\n"
        if let meta = story.meta, !meta.isEmpty { out += "<div class=\"meta\">\(HTML.escape(meta))</div>\n" }
        out += "<div class=\"meta range\"><code>\(HTML.escape(diff.range))</code> \u{00B7} \(Self.stat(diff))</div>\n"
        if !story.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out += "<div class=\"summary prose\">\(prose.render(story.summary, in: .init(anchor: "summary", sectionID: nil)))</div>\n"
        }
        if !diff.excluded.isEmpty {
            let items = diff.excluded.map { ex in
                let count = ex.files.count == 1 ? "1 file" : "\(ex.files.count) files"
                let title = ex.files.isEmpty ? "" : " title=\"\(HTML.escape(ex.files.joined(separator: "\n")))\""
                return "<span class=\"excl\"\(title)><code>\(HTML.escape(ex.pattern))</code> \(count)</span>"
            }
            out += "<div class=\"meta excluded\">Not shown: \(items.joined(separator: ", "))</div>\n"
        }
        return out
    }

    private func nav() -> String {
        func link(_ s: Section) -> String {
            let kicker = s.kicker.map { "<span>\(HTML.escape($0))</span>" } ?? ""
            return "<a href=\"#\(HTML.escape(s.id))\" data-section=\"\(HTML.escape(s.id))\">\(kicker)\(HTML.escape(s.title))</a>"
        }
        var links = story.sections.map(link)
        if !story.appendix.isEmpty {
            links.append("<a href=\"#appendix\" class=\"nav-divider\">Appendix</a>")
            links += story.appendix.map(link)
        }
        return links.joined(separator: "\n")
    }

    /// Ids shared by each marker and code link in a section's prose and their targets in its code.
    static func ids(_ rs: ResolvedSection) -> (markers: [String], links: [String: String]) {
        let markers = rs.markers.map { "mk-\(rs.section.id)-\($0.number)" }
        let links = Dictionary(uniqueKeysWithValues: rs.codeLinks.keys.sorted().enumerated().map { ($1, "cl-\(rs.section.id)-\($0)") })
        return (markers, links)
    }

    /// The marks that a section lays over line `line` of its code item `code`.
    static func marks(_ rs: ResolvedSection, ids: (markers: [String], links: [String: String]), code: Int) -> [Int: [HTML.LineMark]] {
        var marks: [Int: [HTML.LineMark]] = [:]
        for (i, marker) in rs.markers.enumerated() {
            guard let t = marker.target, t.code == code else { continue }
            marks[t.line, default: []].append(.init(bytes: t.bytes, id: ids.markers[i], number: marker.number))
        }
        for (text, t) in rs.codeLinks where t.code == code {
            guard let id = ids.links[text] else { continue }
            marks[t.line, default: []].append(.init(bytes: t.bytes, id: id, number: nil))
        }
        return marks
    }

    private func storyColumn(_ s: Section, resolved rs: ResolvedSection? = nil) -> String {
        let id = HTML.escape(s.id)
        var out = "<div class=\"story\"><div class=\"sticky\">\n"
        if let kicker = s.kicker { out += "<div class=\"kicker\">\(HTML.escape(kicker))</div>\n" }
        out += "<h2><input type=\"checkbox\" class=\"reviewed\" data-section=\"\(id)\" title=\"Reviewed\" aria-label=\"Reviewed\">"
        out += "<a class=\"self\" href=\"#\(id)\">\(HTML.escape(s.title))</a></h2>\n"
        let ids = rs.map(Self.ids)
        let scope = Prose.Scope(anchor: s.id, sectionID: s.id, markerIDs: ids?.markers ?? [], linkIDs: ids?.links ?? [:])
        out += "<div class=\"prose\">\(prose.render(s.body, in: scope))</div>\n"
        return out + "</div></div>\n"
    }

    private func section(_ rs: ResolvedSection) -> String {
        let s = rs.section
        guard s.selectors != nil else {
            return "<section id=\"\(HTML.escape(s.id))\" class=\"full\">\n\(storyColumn(s, resolved: rs))</section>\n"
        }
        var out = "<section id=\"\(HTML.escape(s.id))\">\n\(storyColumn(s, resolved: rs))<div class=\"code\">\n"
        out += rs.code.isEmpty ? "<div class=\"empty\">No code selected.</div>\n"
            : rs.code.enumerated().map { [ids = Self.ids(rs)] in shownCode($1, marks: Self.marks(rs, ids: ids, code: $0)) }.joined()
        return out + "</div>\n</section>\n"
    }

    private func appendixSection(_ s: Section) -> String {
        "<section id=\"\(HTML.escape(s.id))\" class=\"full appendix\">\n\(storyColumn(s))</section>\n"
    }

    private func shownCode(_ code: ShownCode, marks: [Int: [HTML.LineMark]] = [:]) -> String {
        switch code {
        case let .hunk(file, hunk, lines, again):
            return hunkCard(file: file, hunk: hunk, lines: lines, again: again, marks: marks)
        case let .fileChange(file, again):
            var out = "<div class=\"hunk filechange\(again ? " again" : "")\">\n\(fileHeader(file, extra: again ? againNote(placedBy(fileChangeOf: file)) : ""))"
            out += "<div class=\"fc\">\(HTML.escape(Self.fileChangeText(file)))</div>\n"
            return out + "</div>\n"
        }
    }

    static func fileChangeText(_ file: DiffFile) -> String {
        switch file.status {
        case .binary: "Binary file changed"
        case .renamed: "Renamed from \(file.oldPath ?? "?")"
        case .copied: "Copied from \(file.oldPath ?? "?")"
        case .mode: "Mode changed"
        case .added: "Empty file added"
        case .deleted: "Empty file deleted"
        case .modified: "File changed"
        }
    }

    private func fileHeader(_ file: DiffFile, extra: String) -> String {
        let name = (file.path as NSString).lastPathComponent
        var out = "<div class=\"file\"><span class=\"fname\">\(HTML.escape(name))</span><span class=\"fpath\">\(HTML.escape(file.path))</span>"
        let badge: String? = switch file.status {
        case .added: "added"
        case .deleted: "deleted"
        case .renamed: "renamed from \(file.oldPath ?? "?")"
        case .copied: "copied from \(file.oldPath ?? "?")"
        case .mode: "mode changed"
        case .binary: "binary"
        case .modified: nil
        }
        if let badge { out += "<span class=\"badge badge-\(file.status.rawValue)\">\(HTML.escape(badge))</span>" }
        return out + extra + "</div>\n"
    }

    private func hunkCard(file: DiffFile, hunk: Hunk, lines: Range<Int>, again: Bool, marks: [Int: [HTML.LineMark]]) -> String {
        let shown = lines.clamped(to: hunk.lines.indices)
        let extra = again ? againNote(placedBy(file: file, hunk: hunk, lines: shown)) : ""
        var out = "<div class=\"hunk\(again ? " again" : "")\">\n\(fileHeader(file, extra: extra))"
        let git = "@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@"
        out += "<div class=\"ctx\">\(HTML.escape(hunk.header.isEmpty ? git : "\(git) \(hunk.header)"))</div>\n<table>\n"
        let styles = styler.styles(for: file, hunk: hunk)
        let gap = "<tr class=\"gap\"><td class=\"ln\"></td><td class=\"ln\"></td><td class=\"sg\"></td><td class=\"code\">\u{22EF}</td></tr>\n"
        if shown.lowerBound > 0 { out += gap }
        for i in shown {
            let line = hunk.lines[i]
            let code = HTML.line(line.text, runs: i < styles.count ? styles[i] : [], marks: marks[i] ?? [])
            let (cls, sign) = switch line.kind {
            case .add: (" class=\"add\"", "+")
            case .del: (" class=\"del\"", "\u{2212}")
            case .context: ("", "")
            }
            out += "<tr\(cls)><td class=\"ln\">\(line.old.map(String.init) ?? "")</td><td class=\"ln\">\(line.new.map(String.init) ?? "")</td>"
            out += "<td class=\"sg\">\(sign)</td><td class=\"code\">\(code)</td></tr>\n"
        }
        if shown.upperBound < hunk.lines.count { out += gap }
        return out + "</table>\n</div>\n"
    }

    private func againNote(_ placers: [Section]) -> String {
        let links = placers.map { s in
            let label = [s.kicker, s.title].compactMap { $0 }.joined(separator: " \u{00B7} ")
            return "<a href=\"#\(HTML.escape(s.id))\">\(HTML.escape(label))</a>"
        }
        return "<span class=\"again-note\">shown again" + (links.isEmpty ? "" : " \u{00B7} placed in " + links.joined(separator: ", ")) + "</span>"
    }

    /// Sections whose non-again selectors place a changed line among `lines` of the hunk.
    private func placedBy(file: DiffFile, hunk: Hunk, lines: Range<Int>) -> [Section] {
        let changed = Set(lines.filter { hunk.lines[$0].isChange })
        return resolved.sections.filter { rs in
            rs.code.contains { code in
                guard case let .hunk(f, h, l, again) = code, !again, f.path == file.path, h.number == hunk.number else { return false }
                return !changed.isDisjoint(with: l)
            }
        }.map(\.section)
    }

    private func placedBy(fileChangeOf file: DiffFile) -> [Section] {
        resolved.sections.filter { rs in
            rs.code.contains { code in
                guard case let .fileChange(f, again) = code else { return false }
                return !again && f.path == file.path
            }
        }.map(\.section)
    }
}

enum Template {
    static let html: String = {
        let bundle = ResourceBundle.named("StoryGrafter_Render") ?? Bundle.module
        guard let url = bundle.url(forResource: "template", withExtension: "html", subdirectory: "Resources"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("Resources/template.html is missing from \(bundle.bundlePath)")
        }
        return text
    }()

    /// Replaces each `{{NAME}}` in one pass, so that values containing `{{…}}` are left alone.
    static func fill(_ values: [String: String]) -> String {
        var out = ""
        var rest = Substring(html)
        while let open = rest.range(of: "{{") {
            out += rest[..<open.lowerBound]
            guard let close = rest[open.upperBound...].range(of: "}}"),
                  let value = values[String(rest[open.upperBound..<close.lowerBound])] else {
                out += "{{"
                rest = rest[open.upperBound...]
                continue
            }
            out += value
            rest = rest[close.upperBound...]
        }
        return out + rest
    }
}
