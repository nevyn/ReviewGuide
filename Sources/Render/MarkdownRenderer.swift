import Foundation
import ReviewGuideCore

/// Renders a resolved story as one GFM document, with code as fenced `diff` blocks.
///
/// The document has the title, meta, range and short stat, the summary and the exclusions; then each section as
/// `## Kicker · Title`, its prose, and each shown code item as a caption line plus a `diff` block of the shown lines
/// (`⋯` marks omitted lines); then the appendix under `# Appendix`. Footnote definitions follow at the end in order of
/// first reference. Attachments become a bold caption plus a fenced block. Fences are longer than any backtick run
/// inside them.
public struct MarkdownRenderer {
    public init() {}

    /// Throws `StoryProblems` listing every problem found: a footnote reference whose id has no definition, an
    /// attachment whose `file=` is missing or not UTF-8, or a malformed attachment info string. Each names its section.
    public func render(_ story: ResolvedStory) throws -> String {
        var export = MarkdownExport(resolved: story)
        let text = export.render()
        if !export.problems.isEmpty { throw StoryProblems(export.problems) }
        return text
    }
}

struct MarkdownExport {
    let resolved: ResolvedStory
    var problems: [StoryProblem] = []
    /// Footnote labels in order of first reference.
    private var labels: [String] = []

    init(resolved: ResolvedStory) { self.resolved = resolved }

    var story: Story { resolved.story }

    mutating func render() -> String {
        let diff = resolved.diff
        var out = "# \(story.title)\n\n"
        if let meta = story.meta, !meta.isEmpty { out += "\(meta)\n\n" }
        out += "\(Self.inlineCode(diff.range)) \u{00B7} \(Page.stat(diff))\n\n"
        if !story.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out += prose(story.summary, sectionID: nil) + "\n\n"
        }
        if !diff.excluded.isEmpty {
            out += "Not shown:\n\n"
            for ex in diff.excluded {
                let count = ex.files.count == 1 ? "1 file" : "\(ex.files.count) files"
                let paths = ex.files.isEmpty ? "" : " (" + ex.files.map(Self.inlineCode).joined(separator: ", ") + ")"
                out += "- \(Self.inlineCode(ex.pattern)): \(count)\(paths)\n"
            }
            out += "\n"
        }
        for rs in resolved.sections {
            out += heading(rs.section)
            let body = prose(rs.section.body, sectionID: rs.section.id)
            if !body.isEmpty { out += body + "\n\n" }
            for code in rs.code { out += shownCode(code) }
        }
        if !story.appendix.isEmpty {
            out += "# Appendix\n\n"
            for s in story.appendix {
                out += heading(s)
                let body = prose(s.body, sectionID: s.id)
                if !body.isEmpty { out += body + "\n\n" }
            }
        }
        for label in labels {
            let lines = (story.footnotes[label] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n", omittingEmptySubsequences: false)
            out += "[^\(label)]: " + lines.enumerated().map { i, l in i == 0 || l.isEmpty ? String(l) : "    " + l }
                .joined(separator: "\n") + "\n"
        }
        return out.hasSuffix("\n\n") ? String(out.dropLast()) : out
    }

    private func heading(_ s: Section) -> String {
        "## " + [s.kicker, s.title].compactMap { $0 }.joined(separator: " \u{00B7} ") + "\n\n"
    }

    /// The prose with attachments expanded; records footnote references and problems.
    private mutating func prose(_ markdown: String, sectionID: String?) -> String {
        let doc = CMarkDocument(markdown, footnotes: true)
        for (label, _) in doc.footnoteReferences {
            if story.footnotes[label] == nil {
                problem("footnote [^\(label)] is not defined", sectionID: sectionID)
            } else if !labels.contains(label) {
                labels.append(label)
            }
        }
        var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Attachments nested in lists or quotes keep their fence; rewriting them would break the container.
        let blocks = doc.codeBlocks().filter(doc.isTopLevel).reversed()
        for node in blocks {
            let fence: FenceInfo
            do { fence = try FenceInfo(doc.fenceInfo(node)) } catch {
                problem(error.message, sectionID: sectionID)
                continue
            }
            guard let attachment = fence.attachment else { continue }
            var source = doc.literal(node)
            if let file = attachment.file {
                let url = file.hasPrefix("/") ? URL(fileURLWithPath: file)
                    : story.url.deletingLastPathComponent().appendingPathComponent(file)
                guard let data = FileManager.default.contents(atPath: url.path) else {
                    problem("attachment \"\(attachment.caption)\": file=\(file) not found at \(url.path)", sectionID: sectionID)
                    continue
                }
                guard let text = String(data: data, encoding: .utf8) else {
                    problem("attachment \"\(attachment.caption)\": file=\(file) is not UTF-8 text", sectionID: sectionID)
                    continue
                }
                source = text
            }
            if source.hasSuffix("\n") { source.removeLast() }
            let range = doc.lines(of: node)
            let lower = range.lowerBound - 1, upper = min(range.upperBound, lines.count)
            guard lower >= 0, lower < upper else { continue }
            let fenceMarks = Self.fence(for: source)
            lines.replaceSubrange(lower..<upper, with: [
                "**\(attachment.caption)**", "", fenceMarks + fence.language, source, fenceMarks,
            ])
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shownCode(_ code: ShownCode) -> String {
        switch code {
        case let .fileChange(file, again):
            return "\(Self.inlineCode(file.path)): \(Page.fileChangeText(file))\(again ? " (again)" : "")\n\n"
        case let .hunk(file, hunk, lines, again):
            let shown = lines.clamped(to: hunk.lines.indices)
            var body = ["@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@" + (hunk.header.isEmpty ? "" : " \(hunk.header)")]
            if shown.lowerBound > 0 { body.append("\u{22EF}") }
            for line in hunk.lines[shown] {
                let sign = switch line.kind { case .add: "+"; case .del: "-"; case .context: " " }
                body.append(sign + line.text)
            }
            if shown.upperBound < hunk.lines.count { body.append("\u{22EF}") }
            let text = body.joined(separator: "\n")
            let fence = Self.fence(for: text)
            return "\(Self.inlineCode(file.path)) #\(hunk.number)\(again ? " (again)" : "")\n\n\(fence)diff\n\(text)\n\(fence)\n\n"
        }
    }

    private mutating func problem(_ message: String, sectionID: String?) {
        problems.append(StoryProblem(sectionID: sectionID, message: sectionID == nil ? "summary: \(message)" : message))
    }

    static func longestBacktickRun(_ s: String) -> Int {
        var longest = 0, current = 0
        for c in s.unicodeScalars {
            if c == "`" { current += 1; longest = max(longest, current) } else { current = 0 }
        }
        return longest
    }

    /// A backtick fence longer than any backtick run in `content`, and at least three.
    static func fence(for content: String) -> String {
        String(repeating: "`", count: max(3, longestBacktickRun(content) + 1))
    }

    /// A code span that survives backticks inside `s`.
    static func inlineCode(_ s: String) -> String {
        let run = longestBacktickRun(s)
        guard run > 0 else { return "`\(s)`" }
        let ticks = String(repeating: "`", count: run + 1)
        return "\(ticks) \(s) \(ticks)"
    }
}
