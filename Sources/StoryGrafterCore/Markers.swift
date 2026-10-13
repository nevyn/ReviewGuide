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
        var lineStart = markdown.startIndex
        while lineStart < markdown.endIndex {
            let lineEnd = markdown[lineStart...].firstIndex(of: "\n") ?? markdown.endIndex
            let line = markdown[lineStart..<lineEnd]
            let trimmed = line.drop { $0 == " " }
            if let f = fence {
                let run = trimmed.prefix { $0 == f.char }.count
                if run >= f.count, trimmed.dropFirst(run).allSatisfy(\.isWhitespace) { fence = nil }
            } else if let c = trimmed.first, c == "`" || c == "~", line.count - trimmed.count < 4 {
                let run = trimmed.prefix { $0 == c }.count
                if run >= 3 { fence = (c, run) } else { scanInline(line, into: &found) }
            } else {
                scanInline(line, into: &found)
            }
            lineStart = lineEnd < markdown.endIndex ? markdown.index(after: lineEnd) : lineEnd
        }
        return found
    }

    /// Code spans close on a backtick run of the same length, per CommonMark; spans don't cross lines here.
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
                var content = String(line[afterOpen..<close.lowerBound])
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
            let word = line[i...].prefix { $0 != " " && $0 != "}" }
            path = String(word)
            i = word.endIndex
            skipSpaces()
        }
        guard let text = quoted() else { return fail("a marker is {@ \"text\"} or {@ path \"text\"}") }
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
        var markers: [Marker] = []
        var links: [String: CodeTarget] = [:]
        var problems: [StoryProblem] = []
        for occurrence in MarkerSyntax.scan(section.body) {
            switch occurrence.kind {
            case .malformed(let message):
                problems.append(StoryProblem(sectionID: section.id, selector: occurrence.source, message: message))
            case let .marker(path, text):
                let hits = matches(of: text, path: path, in: code)
                if hits.count == 1 {
                    markers.append(Marker(number: markers.count + 1, target: hits[0]))
                } else {
                    let place = path.map { "'\($0)' in " } ?? ""
                    let message = hits.isEmpty
                        ? "\"\(text)\" is in no \(place)code that this section shows"
                        : "\"\(text)\" is in \(hits.count) places in the \(place)code that this section shows (\(describe(hits, in: code))); give a path or more of the text"
                    problems.append(StoryProblem(sectionID: section.id, selector: occurrence.source, message: message))
                    markers.append(Marker(number: markers.count + 1, target: nil))
                }
            case .codeSpan(let text):
                guard links[text] == nil, text.count >= 3, text.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
                var hits = matches(of: text, path: nil, in: code)
                if hits.isEmpty, text.hasSuffix("()") { hits = matches(of: String(text.dropLast()), path: nil, in: code) }
                if hits.count == 1 { links[text] = hits[0] }
            }
        }
        return (markers, links, problems)
    }

    /// Distinct places where `text` occurs in the shown code: the new side (context and added lines) when it occurs
    /// there at all, else deleted lines. Hunks shown twice count once, at their first showing.
    static func matches(of text: String, path: String?, in code: [ShownCode]) -> [CodeTarget] {
        var newSide: [CodeTarget] = [], oldSide: [CodeTarget] = []
        var seen = Set<String>()
        for (index, item) in code.enumerated() {
            guard case let .hunk(file, hunk, lines, _) = item else { continue }
            if let path, file.path != path, !file.path.hasSuffix("/" + path) { continue }
            for l in lines where hunk.lines.indices.contains(l) {
                let line = hunk.lines[l]
                let bytes = Array(line.text.utf8), needle = Array(text.utf8)
                guard needle.count <= bytes.count else { continue }
                for start in 0...(bytes.count - needle.count) where bytes[start..<(start + needle.count)].elementsEqual(needle) {
                    guard seen.insert("\(file.path)#\(hunk.number):\(l):\(start)").inserted else { continue }
                    let target = CodeTarget(code: index, line: l, bytes: start..<(start + needle.count))
                    if line.kind == .del { oldSide.append(target) } else { newSide.append(target) }
                }
            }
        }
        return newSide.isEmpty ? oldSide : newSide
    }

    private static func describe(_ hits: [CodeTarget], in code: [ShownCode]) -> String {
        hits.prefix(5).map { t in
            guard case let .hunk(file, hunk, _, _) = code[t.code] else { return "?" }
            let line = hunk.lines[t.line]
            let name = (file.path as NSString).lastPathComponent
            return "\(name) \(line.new.map(String.init) ?? "-\(line.old.map(String.init) ?? "?")")"
        }.joined(separator: ", ") + (hits.count > 5 ? ", …" : "")
    }
}
