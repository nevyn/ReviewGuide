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

    /// One escaped line with a `<span>` per styled run. Runs are UTF-8 byte ranges; bounds outside the line are
    /// clamped and bounds inside a multi-byte scalar move back to its first byte. Uncovered bytes render unstyled.
    static func line(_ text: String, runs: StyledLine) -> String {
        let bytes = Array(text.utf8)
        func boundary(_ i: Int) -> Int {
            var i = min(max(i, 0), bytes.count)
            while i > 0, i < bytes.count, bytes[i] & 0xC0 == 0x80 { i -= 1 }
            return i
        }
        func slice(_ r: Range<Int>) -> String { escape(String(decoding: bytes[r], as: UTF8.self)) }
        var out = ""
        var cursor = 0
        for run in runs {
            let start = max(boundary(run.bytes.lowerBound), cursor)
            let end = boundary(run.bytes.upperBound)
            guard end > start else { continue }
            if start > cursor { out += slice(cursor..<start) }
            if let cls = classes(capture: run.capture, changed: run.changed) {
                out += "<span class=\"\(escape(cls))\">\(slice(start..<end))</span>"
            } else {
                out += slice(start..<end)
            }
            cursor = end
        }
        if cursor < bytes.count { out += slice(cursor..<bytes.count) }
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
