import Foundation
import StoryGrafterCore

/// Renders story Markdown to HTML: GFM, alerts, highlighted code blocks, attachments and story-global footnotes.
/// Problems are collected rather than thrown so that one render reports all of them.
final class Prose {
    let story: Story
    let styler: any LineStyling
    private(set) var problems: [StoryProblem] = []
    /// Global footnote numbers, assigned in order of first reference across all `render` calls.
    private var numbers: [String: Int] = [:]

    init(story: Story, styler: any LineStyling) {
        self.story = story
        self.styler = styler
    }

    /// A place in the story that prose comes from: the summary or a section.
    struct Scope {
        /// Unique per page; prefixes footnote anchors.
        var anchor: String
        /// `nil` for the summary.
        var sectionID: String?
        /// Marker n's id in the page is `markerIDs[n - 1]`; empty outside section prose.
        var markerIDs: [String] = []
        /// Code span text to the id shared with its target in the code.
        var linkIDs: [String: String] = [:]
    }

    /// Stands in for marker n while cmark renders, so that Markdown never touches `{@ …}`.
    private static func placeholder(_ n: Int) -> String { "\u{E000}\(n)\u{E001}" }

    /// The HTML of `markdown`, followed by a numbered list of the footnotes it references.
    func render(_ markdown: String, in scope: Scope) -> String {
        var source = markdown
        let markers = MarkerSyntax.scan(markdown).filter { if case .marker = $0.kind { true } else { false } }
        for (i, occurrence) in markers.enumerated().reversed() {
            source.replaceSubrange(occurrence.range, with: Self.placeholder(i + 1))
        }
        let doc = CMarkDocument(source, footnotes: true)
        renderBlocks(doc, in: scope)
        for node in doc.codeSpans() {
            let text = doc.literal(node)
            guard let id = scope.linkIDs[text] else { continue }
            doc.replace(node, withHTML: "<a class=\"cl\" href=\"#clt-\(HTML.escape(id))\" data-cl=\"\(HTML.escape(id))\"><code>\(HTML.escape(text))</code></a>", block: false)
        }
        var notes: [(number: Int, label: String)] = []
        var refCounts: [Int: Int] = [:]
        for (label, node) in doc.footnoteReferences {
            guard story.footnotes[label] != nil else {
                problem("footnote [^\(label)] is not defined", in: scope)
                doc.replace(node, withHTML: HTML.escape("[^\(label)]"), block: false)
                continue
            }
            let n = number(for: label)
            let count = refCounts[n, default: 0] + 1
            refCounts[n] = count
            if count == 1 { notes.append((n, label)) }
            let refID = "fnref-\(scope.anchor)-\(n)" + (count == 1 ? "" : "-\(count)")
            let html = "<sup class=\"fnref\"><a href=\"#fn-\(scope.anchor)-\(n)\" id=\"\(HTML.escape(refID))\">\(n)</a></sup>"
            doc.replace(node, withHTML: html, block: false)
        }
        var out = doc.html()
        for n in markers.indices.map({ $0 + 1 }) {
            let circle = n <= scope.markerIDs.count ? HTML.markerCircle(id: scope.markerIDs[n - 1], number: n, inCode: false) : "\(n)"
            out = out.replacingOccurrences(of: Self.placeholder(n), with: circle)
        }
        if !notes.isEmpty {
            out += "<ol class=\"notes\">\n"
            for (n, label) in notes {
                let def = definition(label, in: scope)
                let id = HTML.escape("\(scope.anchor)-\(n)")
                out += "<li value=\"\(n)\" id=\"fn-\(id)\">\(def) <a href=\"#fnref-\(id)\" class=\"fnback\" aria-label=\"Back to reference \(n)\">\u{21A9}\u{FE0E}</a></li>\n"
            }
            out += "</ol>\n"
        }
        return out
    }

    /// The global number of a footnote label, assigning the next one on first use.
    func number(for label: String) -> Int {
        if let n = numbers[label] { return n }
        let n = numbers.count + 1
        numbers[label] = n
        return n
    }

    /// A definition renders inline when it is one paragraph. References inside definitions stay literal text.
    private func definition(_ label: String, in scope: Scope) -> String {
        let doc = CMarkDocument(story.footnotes[label] ?? "", footnotes: false)
        renderBlocks(doc, in: scope)
        let html = doc.html().trimmingCharacters(in: .whitespacesAndNewlines)
        if html.hasPrefix("<p>"), html.hasSuffix("</p>"), html.components(separatedBy: "<p>").count == 2 {
            return String(html.dropFirst(3).dropLast(4))
        }
        return html
    }

    private func renderBlocks(_ doc: CMarkDocument, in scope: Scope) {
        doc.rewriteAlerts { kind in
            guard let alert = Alert(rawValue: kind) else { return nil }
            return ("<div class=\"alert alert-\(alert.cssName)\"><p class=\"alert-title\">\(alert.label)</p>", "</div>")
        }
        for node in doc.codeBlocks() {
            let html = codeBlock(info: doc.fenceInfo(node), literal: doc.literal(node), in: scope)
            doc.replace(node, withHTML: html, block: true)
        }
    }

    private func codeBlock(info: String, literal: String, in scope: Scope) -> String {
        var source = literal.hasSuffix("\n") ? String(literal.dropLast()) : literal
        let fence: FenceInfo
        do {
            fence = try FenceInfo(info)
        } catch {
            problem(error.message, in: scope)
            return "<pre class=\"snippet\"><code>\(HTML.escape(source))</code></pre>"
        }
        guard let attachment = fence.attachment else {
            return "<pre class=\"snippet\"><code>\(HTML.snippet(source, language: fence.language, styler: styler))</code></pre>"
        }
        if let file = attachment.file {
            let url = file.hasPrefix("/") ? URL(fileURLWithPath: file)
                : story.url.deletingLastPathComponent().appendingPathComponent(file)
            guard let data = FileManager.default.contents(atPath: url.path) else {
                problem("attachment \"\(attachment.caption)\": file=\(file) not found at \(url.path)", in: scope)
                return ""
            }
            guard let text = String(data: data, encoding: .utf8) else {
                problem("attachment \"\(attachment.caption)\": file=\(file) is not UTF-8 text", in: scope)
                return ""
            }
            source = text.hasSuffix("\n") ? String(text.dropLast()) : text
        }
        return "<details class=\"attachment\"><summary>\(HTML.escape(attachment.caption))</summary>"
            + "<pre class=\"snippet\"><code>\(HTML.snippet(source, language: fence.language, styler: styler))</code></pre></details>"
    }

    private func problem(_ message: String, in scope: Scope) {
        problems.append(StoryProblem(sectionID: scope.sectionID, message: scope.sectionID == nil ? "summary: \(message)" : message))
    }
}

enum Alert: String {
    case note = "NOTE", warning = "WARNING", question = "QUESTION"

    var label: String {
        switch self {
        case .note: "Note"
        case .warning: "Warning"
        case .question: "Open question"
        }
    }

    var cssName: String { rawValue.lowercased() }
}
