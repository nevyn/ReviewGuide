import Foundation
import StoryGrafterCore

enum HTML {
    /// Escapes for both text content and double-quoted attribute values.
    static func escape(_ s: some StringProtocol) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for c in s.unicodeScalars {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.unicodeScalars.append(c)
            }
        }
        return out
    }

    /// `keyword` -> `hl-keyword`; `a.b.c` -> `hl-a hl-a-b hl-a-b-c`; plus `chg` when changed. `nil` when neither applies.
    static func classes(capture: String?, changed: Bool) -> String? {
        var classes: [String] = []
        if let capture, !capture.isEmpty {
            var prefix = "hl"
            for part in capture.split(separator: ".") {
                prefix += "-" + part
                classes.append(prefix)
            }
        }
        if changed { classes.append("chg") }
        return classes.isEmpty ? nil : classes.joined(separator: " ")
    }

    /// A highlight laid over part of a code line: a marker's token, or the target of a code link.
    struct LineMark {
        /// UTF-8 byte range in the line.
        var bytes: Range<Int>
        /// Shared with the partner in the prose, such as `mk-a-2` or `cl-a-0`.
        var id: String
        /// A marker's number, which draws its circle before the token; `nil` for a code link's target.
        var number: Int?
    }

    /// The colour class of marker `number`; six colours cycle.
    static func markerColor(_ number: Int) -> String { "mk-c\((number - 1) % 6)" }

    /// The numbered circle that pairs a marker in the prose with its token in the code. Each links to the other.
    static func markerCircle(id: String, number: Int, inCode: Bool) -> String {
        let (own, other) = inCode ? ("mkt-", "mkp-") : ("mkp-", "mkt-")
        return "<a class=\"mk \(markerColor(number))\" id=\"\(own)\(escape(id))\" href=\"#\(other)\(escape(id))\" data-mk=\"\(escape(id))\">\(number)</a>"
    }

    /// One escaped line with a `<span>` per styled run, and marks laid over it. Runs and marks are UTF-8 byte ranges;
    /// bounds outside the line are clamped and bounds inside a multi-byte scalar move back to its first byte. The line
    /// is cut at every run and mark boundary, so spans never nest. Uncovered bytes render unstyled.
    static func line(_ text: String, runs: StyledLine, marks: [LineMark] = []) -> String {
        let bytes = Array(text.utf8)
        func boundary(_ i: Int) -> Int {
            var i = min(max(i, 0), bytes.count)
            while i > 0, i < bytes.count, bytes[i] & 0xC0 == 0x80 { i -= 1 }
            return i
        }
        func slice(_ r: Range<Int>) -> String { escape(String(decoding: bytes[r], as: UTF8.self)) }
        let clampedRuns = runs.map { (start: boundary($0.bytes.lowerBound), end: boundary($0.bytes.upperBound), run: $0) }
        let clampedMarks = marks.map { (start: boundary($0.bytes.lowerBound), end: boundary($0.bytes.upperBound), mark: $0) }
            .filter { $0.end > $0.start }
        var cuts = Set([0, bytes.count])
        for r in clampedRuns { cuts.insert(r.start); cuts.insert(r.end) }
        for m in clampedMarks { cuts.insert(m.start); cuts.insert(m.end) }
        let points = cuts.sorted()

        var out = ""
        for (start, end) in zip(points, points.dropFirst()) where end > start {
            for m in clampedMarks where m.start == start {
                if let n = m.mark.number { out += markerCircle(id: m.mark.id, number: n, inCode: true) }
            }
            let run = clampedRuns.last { $0.start <= start && end <= $0.end && $0.end > $0.start }?.run
            var classes = run.flatMap { classes(capture: $0.capture, changed: $0.changed) }.map { [$0] } ?? []
            var attributes = ""
            if let m = clampedMarks.first(where: { $0.start <= start && end <= $0.end }) {
                if let n = m.mark.number {
                    classes += ["mkt", markerColor(n)]
                    attributes = " data-mk=\"\(escape(m.mark.id))\""
                } else {
                    classes.append("clt")
                    attributes = " data-cl=\"\(escape(m.mark.id))\"" + (m.start == start ? " id=\"clt-\(escape(m.mark.id))\"" : "")
                }
            }
            if classes.isEmpty && attributes.isEmpty {
                out += slice(start..<end)
            } else {
                out += "<span class=\"\(escape(classes.joined(separator: " ")))\"\(attributes)>\(slice(start..<end))</span>"
            }
        }
        return out
    }

    /// Highlighted lines of a snippet, joined with newlines for a `<pre>`.
    static func snippet(_ source: String, language: String, styler: any LineStyling) -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let styles = styler.styles(source: source, language: language)
        return lines.enumerated().map { i, text in
            line(text, runs: i < styles.count ? styles[i] : [])
        }.joined(separator: "\n")
    }
}
