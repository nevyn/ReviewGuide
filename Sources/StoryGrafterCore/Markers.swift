import Foundation

/// A place in a section's code column: one line of one shown hunk, and a byte range in it.
public struct CodeTarget: Sendable, Hashable {
    /// Index into `ResolvedSection.code`.
    public var code: Int
    /// Index into the hunk's `lines`.
    public var line: Int
    /// UTF-8 byte range in the line's text.
    public var bytes: Range<Int>

    public init(code: Int, line: Int, bytes: Range<Int>) { self.code = code; self.line = line; self.bytes = bytes }
}

/// A `{@ "text"}` marker in a section's prose, resolved to the code it points at.
public struct Marker: Sendable, Equatable {
    /// 1-based, in reading order within the section.
    public var number: Int
    /// `nil` when the marker matched nothing or several places; `check` reports it, and `resolve` throws.
    public var target: CodeTarget?

    public init(number: Int, target: CodeTarget?) { self.number = number; self.target = target }
}

/// One `{@ …}` or inline code span found in story Markdown, outside code blocks.
public struct MarkerOccurrence: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// `{@ "text"}` or `{@ path "text"}`.
        case marker(path: String?, text: String)
        /// A malformed `{@ …}`; the message says what is wrong.
        case malformed(String)
        /// The content of an inline code span, for code links.
        case codeSpan(String)
    }

    public var kind: Kind
    /// The occurrence in the scanned Markdown, including its braces or backticks.
    public var range: Range<String.Index>
    /// As written, for error messages.
    public var source: String
}

/// Finds markers and inline code spans in story Markdown. `check` and the renderers share it, so that both agree on
/// which `{@ …}` is marker number n.
public enum MarkerSyntax {
    /// Every marker, malformed marker and inline code span in `markdown`, in order. Fenced code blocks are skipped,
    /// and so are markers inside code spans.
    public static func scan(_ markdown: String) -> [MarkerOccurrence] {
        var found: [MarkerOccurrence] = []
        var fence: (char: Character, count: Int)?
        var block: Range<String.Index>?  // consecutive prose lines, where a code span may continue across a line break
        func flush() {
            if let b = block { scanInline(markdown[b], into: &found) }
            block = nil
        }
        var lineStart = markdown.startIndex
        while lineStart < markdown.endIndex {
            let lineEnd = markdown[lineStart...].firstIndex(of: "\n") ?? markdown.endIndex
            let line = markdown[lineStart..<lineEnd]
            // Fences count at any indentation: inside list items cmark accepts them indented by the item's width.
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            if let f = fence {
                let run = trimmed.prefix { $0 == f.char }.count
                if run >= f.count, trimmed.dropFirst(run).allSatisfy(\.isWhitespace) { fence = nil }
            } else if let c = trimmed.first, c == "`" || c == "~", trimmed.prefix(while: { $0 == c }).count >= 3,
                      c == "~" || !trimmed.dropFirst(3).contains("`") {
                flush()
                fence = (c, trimmed.prefix { $0 == c }.count)
            } else if trimmed.isEmpty {
                flush()
            } else {
                block = (block?.lowerBound ?? lineStart)..<lineEnd
            }
            lineStart = lineEnd < markdown.endIndex ? markdown.index(after: lineEnd) : lineEnd
        }
        flush()
        return found
    }

    /// Code spans close on a backtick run of the same length, per CommonMark, and may cross line breaks within a block.
    private static func scanInline(_ line: Substring, into found: inout [MarkerOccurrence]) {
        var i = line.startIndex
        while i < line.endIndex {
            if line[i] == "`" {
                let run = line[i...].prefix { $0 == "`" }
                let afterOpen = run.endIndex
                var j = afterOpen
                var close: Range<String.Index>?
                while j < line.endIndex {
                    if line[j] == "`" {
                        let r = line[j...].prefix { $0 == "`" }
                        if r.count == run.count { close = j..<r.endIndex; break }
                        j = r.endIndex
                    } else {
                        j = line.index(after: j)
                    }
                }
                guard let close else { i = afterOpen; continue }
                var content = String(line[afterOpen..<close.lowerBound]).replacingOccurrences(of: "\n", with: " ")
                if content.count > 1, content.first == " ", content.last == " ", content.contains(where: { $0 != " " }) {
                    content = String(content.dropFirst().dropLast())
                }
                found.append(MarkerOccurrence(kind: .codeSpan(content), range: i..<close.upperBound,
                                              source: String(line[i..<close.upperBound])))
                i = close.upperBound
            } else if line[i] == "{", line[line.index(after: i)...].hasPrefix("@") {
                let (occurrence, end) = marker(in: line, at: i)
                found.append(occurrence)
                i = end
            } else {
                i = line.index(after: i)
            }
        }
    }

    /// Parses `{@ [path] "text"}` starting at the `{`.
    private static func marker(in line: Substring, at start: String.Index) -> (MarkerOccurrence, String.Index) {
        var i = line.index(start, offsetBy: 2)
        func skipSpaces() { while i < line.endIndex, line[i] == " " { i = line.index(after: i) } }
        func quoted() -> String? {
            guard i < line.endIndex, line[i] == "\"" else { return nil }
            var out = ""
            i = line.index(after: i)
            while i < line.endIndex {
                let c = line[i]
                if c == "\\", line.index(after: i) < line.endIndex {
                    i = line.index(after: i); out.append(line[i])
                } else if c == "\"" {
                    i = line.index(after: i); return out
                } else {
                    out.append(c)
                }
                i = line.index(after: i)
            }
            return nil
        }
        func fail(_ message: String) -> (MarkerOccurrence, String.Index) {
            let end = line[start...].firstIndex(of: "}").map { line.index(after: $0) } ?? line.endIndex
            return (MarkerOccurrence(kind: .malformed(message), range: start..<end, source: String(line[start..<end])), end)
        }

        skipSpaces()
        var path: String?
        if i < line.endIndex, line[i] != "\"" {
            let word = line[i...].prefix { $0 != " " && $0 != "}" && $0 != "\n" }
            path = String(word)
            i = word.endIndex
            skipSpaces()
        }
        guard var text = quoted() else { return fail("a marker is {@ \"text\"} or {@ path \"text\"}") }
        skipSpaces()
        if path == nil, i < line.endIndex, line[i] == "\"" {
            // {@ "My File.swift" "text"}: the first quoted string was a path with spaces.
            guard let second = quoted() else { return fail("a marker is {@ \"text\"} or {@ path \"text\"}") }
            path = text
            text = second
        }
        if text.isEmpty { return fail("the marker's text is empty") }
        skipSpaces()
        guard i < line.endIndex, line[i] == "}" else { return fail("the marker has no closing }") }
        let end = line.index(after: i)
        return (MarkerOccurrence(kind: .marker(path: path, text: text), range: start..<end, source: String(line[start..<end])), end)
    }
}

extension Resolver {
    /// Resolves the markers and code links of one section against the code it shows.
    static func markers(for section: Section, code: [ShownCode]) -> (markers: [Marker], links: [String: CodeTarget], problems: [StoryProblem]) {
        let corpus = ShownLines(code)
        var markers: [Marker] = []
        var links: [String: CodeTarget] = [:]
        var problems: [StoryProblem] = []
        for occurrence in MarkerSyntax.scan(section.body) {
            switch occurrence.kind {
            case .malformed(let message):
                problems.append(StoryProblem(sectionID: section.id, selector: occurrence.source, message: message))
            case let .marker(path, text):
                let hits = corpus.matches(of: text, path: path, wholeWords: false)
                if hits.count == 1 {
                    markers.append(Marker(number: markers.count + 1, target: hits[0]))
                } else {
                    let place = path.map { "'\($0)' in " } ?? ""
                    let message = hits.isEmpty
                        ? "\"\(text)\" is in no \(place)code that this section shows"
                        : "\"\(text)\" is in \(hits.count) places in the \(place)code that this section shows (\(corpus.describe(hits))); give a path or more of the text"
                    problems.append(StoryProblem(sectionID: section.id, selector: occurrence.source, message: message))
                    markers.append(Marker(number: markers.count + 1, target: nil))
                }
            case .codeSpan(let text):
                guard links[text] == nil, text.count >= 3, text.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
                var hits = corpus.matches(of: text, path: nil, wholeWords: true)
                if hits.isEmpty, text.hasSuffix("()") { hits = corpus.matches(of: String(text.dropLast()), path: nil, wholeWords: true) }
                if hits.count == 1 { links[text] = hits[0] }
            }
        }
        return (markers, links, problems)
    }
}

/// A section's shown code lines, each encoded to UTF-8 once, for repeated searches.
struct ShownLines {
    struct Line {
        var target: (code: Int, line: Int)
        var path: String
        var kind: LineKind
        var bytes: [UInt8]
        var label: String
    }

    var lines: [Line] = []

    /// Hunks shown twice count once, at their first showing.
    init(_ code: [ShownCode]) {
        var seen = Set<String>()
        for (index, item) in code.enumerated() {
            guard case let .hunk(file, hunk, shown, _) = item else { continue }
            let name = (file.path as NSString).lastPathComponent
            for l in shown where hunk.lines.indices.contains(l) && seen.insert("\(file.path)#\(hunk.number):\(l)").inserted {
                let line = hunk.lines[l]
                let number = line.new.map(String.init) ?? "-\(line.old.map(String.init) ?? "?")"
                lines.append(Line(target: (index, l), path: file.path, kind: line.kind, bytes: Array(line.text.utf8), label: "\(name) \(number)"))
            }
        }
    }

    /// Distinct places where `text` occurs: on the new side (context and added lines) when it occurs there at all,
    /// else on deleted lines. With `wholeWords`, a match that starts or ends with an identifier character must not
    /// continue an identifier, so `clock` does not match inside `clockRate`.
    func matches(of text: String, path: String?, wholeWords: Bool) -> [CodeTarget] {
        let needle = Array(text.utf8)
        guard !needle.isEmpty else { return [] }
        func isWord(_ b: UInt8) -> Bool { b == UInt8(ascii: "_") || b >= 0x80 || (b >= 0x30 && b <= 0x39) || ((b | 0x20) >= 0x61 && (b | 0x20) <= 0x7A) }
        var newSide: [CodeTarget] = [], oldSide: [CodeTarget] = []
        for line in lines {
            if let path, line.path != path, !line.path.hasSuffix("/" + path) { continue }
            let bytes = line.bytes
            guard needle.count <= bytes.count else { continue }
            for start in 0...(bytes.count - needle.count) where bytes[start..<(start + needle.count)].elementsEqual(needle) {
                let end = start + needle.count
                if wholeWords {
                    if isWord(needle[0]), start > 0, isWord(bytes[start - 1]) { continue }
                    if isWord(needle[needle.count - 1]), end < bytes.count, isWord(bytes[end]) { continue }
                }
                let target = CodeTarget(code: line.target.code, line: line.target.line, bytes: start..<end)
                if line.kind == .del { oldSide.append(target) } else { newSide.append(target) }
            }
        }
        return newSide.isEmpty ? oldSide : newSide
    }

    func describe(_ hits: [CodeTarget]) -> String {
        hits.prefix(5).map { t in
            lines.first { $0.target.code == t.code && $0.target.line == t.line }?.label ?? "?"
        }.joined(separator: ", ") + (hits.count > 5 ? ", …" : "")
    }
}
