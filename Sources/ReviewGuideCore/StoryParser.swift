import Foundation

public enum StoryParser {
    /// Parses a story per docs/story-format.md. Throws every syntax problem found, not just the first.
    ///
    /// Each problem's message starts with `line N:`, the 1-based line in `text`. Selector problems also carry
    /// the section id and the selector source. Headings and fences inside other fenced code blocks are ignored.
    /// - Parameter url: The story file, kept in `Story.url`; nothing is read from it.
    public static func parse(_ text: String, url: URL) throws(StoryProblems) -> Story {
        var parser = Parser(text: text, url: url)
        let story = parser.run()
        if !parser.problems.isEmpty { throw StoryProblems(parser.problems) }
        return story!
    }
}

private struct Line {
    var number: Int
    var text: String
}

private struct Fence {
    var char: Character
    var length: Int
    var info: String
    var line: Int
    var isHunks: Bool { info.split(whereSeparator: \.isWhitespace).first == "hunks" }

    /// An opening fence: up to three spaces, then three or more backticks or tildes.
    init?(_ text: String, line: Int) {
        let indent = text.prefix { $0 == " " }.count
        guard indent <= 3 else { return nil }
        let rest = text.dropFirst(indent)
        guard let c = rest.first, c == "`" || c == "~" else { return nil }
        let run = rest.prefix { $0 == c }.count
        guard run >= 3 else { return nil }
        let info = rest.dropFirst(run).trimmingCharacters(in: .whitespaces)
        if c == "`", info.contains("`") { return nil }
        char = c; length = run; self.info = info; self.line = line
    }

    func closes(_ text: String) -> Bool {
        let indent = text.prefix { $0 == " " }.count
        guard indent <= 3 else { return false }
        let rest = text.dropFirst(indent)
        let run = rest.prefix { $0 == char }.count
        return run >= length && rest.dropFirst(run).allSatisfy { $0 == " " || $0 == "\t" }
    }
}

private struct Block {
    var heading: Line?
    var level = 0
    var id = ""
    var kicker: String?
    var title = ""
    var body: [String] = []
    var hunks: [Line]?
    var hunksLine = 0
}

private struct Parser {
    let url: URL
    let lines: [Line]
    var problems: [StoryProblem] = []

    init(text: String, url: URL) {
        self.url = url
        lines = text.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false).enumerated().map { i, raw in
            var s = String(decoding: raw, as: UTF8.self)
            if s.hasSuffix("\r") { s.removeLast() }
            return Line(number: i + 1, text: s)
        }
    }

    mutating func problem(_ line: Int, _ message: String, section: String? = nil, selector: String? = nil) {
        problems.append(StoryProblem(sectionID: section, selector: selector, message: "line \(line): \(message)"))
    }

    mutating func run() -> Story? {
        var front = FrontMatter()
        let bodyStart = parseFrontMatter(into: &front)

        var summary = Block()
        var sections: [Block] = []
        var appendix: [Block] = []
        var inAppendix = false
        var appendixLine: Int?
        var footnotes: [String: String] = [:]
        var footnoteLines: [String: Int] = [:]

        var fence: Fence?
        var collectingHunks = false
        var footnote: (id: String, line: Int, text: [String], pendingBlanks: Int)?

        func lastBodyLineIsBlank() -> Bool {
            let body = inAppendix ? appendix.last?.body : (sections.last?.body ?? summary.body)
            return body?.last.map { $0.trimmingCharacters(in: .whitespaces).isEmpty } ?? true
        }
        func appendBody(_ s: String) {
            if inAppendix, !appendix.isEmpty { appendix[appendix.count - 1].body.append(s) }
            else if !inAppendix, !sections.isEmpty { sections[sections.count - 1].body.append(s) }
            else { summary.body.append(s) }
        }

        var index = bodyStart
        while index < lines.count {
            let line = lines[index]
            index += 1

            if let open = fence {
                if open.closes(line.text) {
                    fence = nil
                    if !open.isHunks { appendBody(line.text) }
                    // Keep one blank line, not two, where a hunks fence stood between paragraphs.
                    if open.isHunks, index < lines.count, lines[index].text.trimmingCharacters(in: .whitespaces).isEmpty,
                       lastBodyLineIsBlank() { index += 1 }
                } else if open.isHunks {
                    if collectingHunks { sections[sections.count - 1].hunks!.append(line) }
                } else {
                    appendBody(line.text)
                }
                continue
            }

            if var note = footnote {
                if line.text.trimmingCharacters(in: .whitespaces).isEmpty {
                    note.pendingBlanks += 1
                    footnote = note
                    continue
                }
                if line.text.hasPrefix("    ") || line.text.hasPrefix("\t") {
                    note.text += Array(repeating: "", count: note.pendingBlanks)
                    note.text.append(line.text.hasPrefix("\t") ? String(line.text.dropFirst()) : String(line.text.dropFirst(4)))
                    note.pendingBlanks = 0
                    footnote = note
                    continue
                }
                footnotes[note.id] = note.text.joined(separator: "\n")
                for _ in 0..<note.pendingBlanks { appendBody("") }
                footnote = nil
            }

            if let open = Fence(line.text, line: line.number) {
                fence = open
                if open.isHunks {
                    collectingHunks = startHunks(at: line.number, sections: &sections, inAppendix: inAppendix)
                } else {
                    appendBody(line.text)
                }
                continue
            }

            if let (id, first) = Self.footnoteDefinition(line.text) {
                if let previous = footnoteLines[id] {
                    problem(line.number, "footnote [^\(id)] is defined twice (also line \(previous))")
                }
                footnoteLines[id] = line.number
                footnote = (id, line.number, [first], 0)
                continue
            }

            if let (level, text) = Self.atxHeading(line.text), level <= 2 {
                if level == 1 {
                    if text == "Appendix" {
                        if let first = appendixLine { problem(line.number, "second '# Appendix' (first at line \(first))") }
                        appendixLine = appendixLine ?? line.number
                        inAppendix = true
                    } else {
                        problem(line.number, "'# \(text)' is not allowed: the only level-1 heading is '# Appendix'")
                    }
                    continue
                }
                let block = section(heading: line, text: text)
                if inAppendix { appendix.append(block) } else { sections.append(block) }
                continue
            }

            appendBody(line.text)
        }

        if let open = fence {
            problem(open.line, "code fence \(String(repeating: open.char, count: open.length)) is never closed")
        }
        if let note = footnote {
            footnotes[note.id] = note.text.joined(separator: "\n")
        }

        checkIDs(sections + appendix)
        var parsedSections: [Section] = []
        for block in sections { parsedSections.append(parseSelectors(block)) }
        guard let title = front.title else { return nil }
        return Story(
            url: url, title: title, meta: front.meta, range: front.range, head: front.head, exclude: front.exclude,
            summary: Self.trimBlankLines(summary.body),
            sections: parsedSections,
            appendix: appendix.map { Section(id: $0.id, kicker: $0.kicker, title: $0.title, body: Self.trimBlankLines($0.body), line: $0.heading!.number) },
            footnotes: footnotes)
    }

    // MARK: Front matter

    struct FrontMatter {
        var title: String?, meta: String?, range: String?, head: String?
        var exclude: [String] = []
    }

    /// Returns the index of the first line after the front matter.
    mutating func parseFrontMatter(into front: inout FrontMatter) -> Int {
        guard lines.first?.text == "---" else {
            problem(1, "a story starts with a '---' front matter block that sets 'title'")
            return 0
        }
        guard let close = lines.dropFirst().firstIndex(where: { $0.text == "---" }) else {
            problem(1, "the front matter is never closed with '---'")
            return lines.count
        }
        var seen: [String: Int] = [:]
        for line in lines[1..<close] where !line.text.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let colon = line.text.firstIndex(of: ":") else {
                problem(line.number, "front matter line '\(line.text)' is not 'key: value'")
                continue
            }
            let key = line.text[..<colon].trimmingCharacters(in: .whitespaces)
            let raw = line.text[line.text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if let previous = seen[key] { problem(line.number, "front matter key '\(key)' is set twice (also line \(previous))") }
            seen[key] = line.number
            switch key {
            case "title", "meta", "range", "head":
                guard let value = scalar(raw, line: line.number, key: key) else { continue }
                switch key {
                case "title": front.title = value
                case "meta": front.meta = value
                case "range": front.range = value
                default: front.head = value
                }
            case "exclude":
                if let list = flowList(raw, line: line.number) { front.exclude = list }
            default:
                problem(line.number, "unknown front matter key '\(key)'; the keys are title, meta, range, head and exclude")
            }
        }
        if front.title == nil && seen["title"] == nil { problem(1, "the front matter has no 'title'") }
        return close + 1
    }

    mutating func scalar(_ raw: String, line: Int, key: String) -> String? {
        if raw.hasPrefix("\"") {
            switch Self.quoted(Substring(raw)) {
            case .success(let (value, rest)):
                if rest.trimmingCharacters(in: .whitespaces).isEmpty { return value }
                problem(line, "unexpected '\(rest.trimmingCharacters(in: .whitespaces))' after the quoted value of '\(key)'")
            case .failure(let message):
                problem(line, "'\(key)': \(message)")
            }
            return nil
        }
        if raw.isEmpty { problem(line, "front matter key '\(key)' has no value"); return nil }
        return raw
    }

    mutating func flowList(_ raw: String, line: Int) -> [String]? {
        guard raw.hasPrefix("["), raw.hasSuffix("]") else {
            problem(line, "'exclude' must be a list of quoted globs, like [\"*.png\"]")
            return nil
        }
        var rest = Substring(raw.dropFirst().dropLast())
        var items: [String] = []
        while true {
            rest = rest.drop { $0 == " " || $0 == "\t" }
            if rest.isEmpty { break }
            guard rest.first == "\"" else {
                problem(line, "'exclude' items must be double-quoted, found '\(rest)'")
                return nil
            }
            switch Self.quoted(rest) {
            case .success(let (value, after)):
                items.append(value)
                rest = after.drop { $0 == " " || $0 == "\t" }
                if rest.isEmpty { break }
                guard rest.first == "," else {
                    problem(line, "expected ',' between 'exclude' items, found '\(rest)'")
                    return nil
                }
                rest = rest.dropFirst()
                continue
            case .failure(let message):
                problem(line, "'exclude': \(message)")
                return nil
            }
            break
        }
        return items
    }

    // MARK: Sections

    mutating func section(heading: Line, text: String) -> Block {
        var block = Block(heading: heading, level: 2)
        var title = text
        var explicitID: String?
        if title.hasSuffix("}"), let open = title.range(of: "{#", options: .backwards) {
            explicitID = String(title[open.upperBound..<title.index(before: title.endIndex)])
            title = title[..<open.lowerBound].trimmingCharacters(in: .whitespaces)
        }
        if let dot = title.range(of: " \u{00B7} ") {
            block.kicker = title[..<dot.lowerBound].trimmingCharacters(in: .whitespaces)
            title = title[dot.upperBound...].trimmingCharacters(in: .whitespaces)
        }
        block.title = title
        if title.isEmpty { problem(heading.number, "section heading has no title") }
        if let id = explicitID {
            if id.isEmpty || !id.unicodeScalars.allSatisfy({ $0.isASCII && (Character($0).isLetter || Character($0).isNumber || $0 == "-" || $0 == "_") }) {
                problem(heading.number, "section id '\(id)' may only contain ASCII letters, digits, '-' and '_'")
            }
            block.id = id
        } else {
            block.id = Self.slug(title)
            if block.id.isEmpty, !title.isEmpty {
                problem(heading.number, "title '\(title)' has no ASCII letters or digits to make an id from; add {#id}")
            }
        }
        return block
    }

    mutating func checkIDs(_ blocks: [Block]) {
        var seen: [String: Int] = [:]
        for block in blocks where !block.id.isEmpty {
            let line = block.heading!.number
            if let first = seen[block.id] {
                problem(line, "duplicate section id '\(block.id)' (also line \(first)); set another with {#id}")
            } else {
                seen[block.id] = line
            }
        }
    }

    /// Returns whether the fence's lines are the current section's selectors.
    mutating func startHunks(at line: Int, sections: inout [Block], inAppendix: Bool) -> Bool {
        if inAppendix {
            problem(line, "appendix sections place no code, so they cannot have a hunks fence")
            return false
        }
        guard !sections.isEmpty else {
            problem(line, "hunks fence before the first section")
            return false
        }
        let i = sections.count - 1
        if sections[i].hunks != nil {
            problem(line, "section '\(sections[i].id)' has a second hunks fence (first at line \(sections[i].hunksLine))")
            return false
        }
        sections[i].hunks = []
        sections[i].hunksLine = line
        return true
    }

    mutating func parseSelectors(_ block: Block) -> Section {
        var selectors: [Selector]?
        if let hunkLines = block.hunks {
            selectors = hunkLines.compactMap { parseSelector($0, section: block.id) }
        }
        return Section(id: block.id, kicker: block.kicker, title: block.title, body: Self.trimBlankLines(block.body),
                       selectors: selectors, line: block.heading!.number)
    }

    // MARK: Selectors

    enum Token: Equatable {
        case word(String), quoted(String), at
        var display: String {
            switch self {
            case .word(let w): w
            case .quoted(let q): "\"\(q)\""
            case .at: "@"
            }
        }
    }

    mutating func parseSelector(_ line: Line, section: String) -> Selector? {
        let (tokens, source, error) = Self.tokenize(line.text)
        if tokens.isEmpty && error == nil { return nil }
        func fail(_ message: String) -> Selector? {
            problem(line.number, message, section: section, selector: source)
            return nil
        }
        if let error { return fail(error) }

        var i = 0
        var path = ""
        switch tokens[0] {
        case .word(let w), .quoted(let w): path = w
        case .at: return fail("a selector starts with a path")
        }
        i = 1
        var hunks = HunkPick.all
        var lines: LinePick?
        var again = false

        if i < tokens.count, case .word(let w) = tokens[i], w.hasPrefix("#") {
            guard let numbers = Self.hunkNumbers(w.dropFirst()) else {
                return fail("'\(w)' is not a hunk list like #3, #2-4 or #1,3,5")
            }
            hunks = .numbers(numbers)
            i += 1
        } else if i < tokens.count, tokens[i] == .at {
            guard i + 1 < tokens.count, case .quoted(let anchor) = tokens[i + 1] else {
                return fail("'@' must be followed by a quoted anchor, like @ \"func resync(\"")
            }
            if anchor.isEmpty { return fail("the anchor is empty") }
            i += 2
            if i < tokens.count, tokens[i] == .word("to") {
                guard i + 1 < tokens.count, case .quoted(let to) = tokens[i + 1] else {
                    return fail("'to' must be followed by a quoted anchor")
                }
                if to.isEmpty { return fail("the 'to' anchor is empty") }
                lines = .anchored(from: anchor, to: to)
                i += 2
            } else {
                hunks = .anchor(anchor)
            }
        }

        if i < tokens.count, tokens[i] == .word("lines") {
            if lines != nil { return fail("a selector has either 'lines' or '@ … to …', not both") }
            guard i + 1 < tokens.count, case .word(let spec) = tokens[i + 1], let range = Self.lineRange(spec) else {
                return fail("'lines' must be followed by a range like 5-12")
            }
            lines = .range(range.0, range.1)
            i += 2
        }
        if i < tokens.count, tokens[i] == .word("again") {
            again = true
            i += 1
        }
        if i < tokens.count {
            return fail("unexpected '\(tokens[i].display)'; the form is <path> [#n | @ \"text\"] [lines a-b | to \"text\"] [again]")
        }
        return Selector(source: source, path: path, hunks: hunks, lines: lines, again: again)
    }

    /// Splits a selector line into tokens and returns the source without its comment, or an error message.
    static func tokenize(_ text: String) -> ([Token], String, String?) {
        var tokens: [Token] = []
        let chars = Array(text)
        var i = 0
        var end = chars.count
        while i < chars.count {
            let c = chars[i]
            if c == " " || c == "\t" { i += 1; continue }
            if c == "#" {
                let atLineStart = tokens.isEmpty
                let next = i + 1 < chars.count ? chars[i + 1] : " "
                if atLineStart || ((i == 0 || chars[i - 1] == " " || chars[i - 1] == "\t") && (next == " " || next == "\t")) {
                    end = i
                    break
                }
            }
            if c == "\"" {
                switch quoted(Substring(String(chars[i...]))) {
                case .success(let (value, rest)):
                    tokens.append(.quoted(value))
                    i = chars.count - rest.count
                case .failure(let message):
                    return (tokens, text.trimmingCharacters(in: .whitespaces), message)
                }
                continue
            }
            if c == "@" { tokens.append(.at); i += 1; continue }
            var j = i
            while j < chars.count, chars[j] != " ", chars[j] != "\t" { j += 1 }
            tokens.append(.word(String(chars[i..<j])))
            i = j
        }
        let source = String(chars[..<end]).trimmingCharacters(in: .whitespaces)
        return (tokens, source, nil)
    }

    enum QuoteResult { case success((String, Substring)), failure(String) }

    /// Reads a double-quoted string with `\"` and `\\` escapes from the start of `s`.
    static func quoted(_ s: Substring) -> QuoteResult {
        var value = ""
        var i = s.index(after: s.startIndex)
        while i < s.endIndex {
            let c = s[i]
            if c == "\"" { return .success((value, s[s.index(after: i)...])) }
            if c == "\\" {
                let n = s.index(after: i)
                guard n < s.endIndex else { break }
                guard s[n] == "\"" || s[n] == "\\" else { return .failure("unknown escape '\\\(s[n])' in \(s); only \\\" and \\\\ are escapes") }
                value.append(s[n])
                i = s.index(after: n)
                continue
            }
            value.append(c)
            i = s.index(after: i)
        }
        return .failure("unterminated quote in \(s)")
    }

    static func hunkNumbers(_ s: Substring) -> [Int]? {
        var result: [Int] = []
        for item in s.split(separator: ",", omittingEmptySubsequences: false) {
            if let r = lineRange(String(item)) { result += Array(r.0...r.1) } else { return nil }
        }
        return result.isEmpty ? nil : result
    }

    /// `5` or `5-12`, 1-based, ascending.
    static func lineRange(_ s: String) -> (Int, Int)? {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count <= 2, let a = Int(parts[0]), a >= 1 else { return nil }
        guard parts.count == 2 else { return (a, a) }
        guard let b = Int(parts[1]), b >= a else { return nil }
        return (a, b)
    }

    // MARK: Lines

    /// `[^id]: text` at up to three spaces of indent.
    static func footnoteDefinition(_ text: String) -> (String, String)? {
        let indent = text.prefix { $0 == " " }.count
        guard indent <= 3 else { return nil }
        let rest = text.dropFirst(indent)
        guard rest.hasPrefix("[^"), let close = rest.firstIndex(of: "]") else { return nil }
        let id = rest[rest.index(rest.startIndex, offsetBy: 2)..<close]
        let after = rest[rest.index(after: close)...]
        guard !id.isEmpty, !id.contains(where: \.isWhitespace), after.hasPrefix(":") else { return nil }
        return (String(id), after.dropFirst().trimmingCharacters(in: .whitespaces))
    }

    /// An ATX heading's level and text, without a closing sequence of `#`.
    static func atxHeading(_ text: String) -> (Int, String)? {
        let indent = text.prefix { $0 == " " }.count
        guard indent <= 3 else { return nil }
        let rest = text.dropFirst(indent)
        let level = rest.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }
        let after = rest.dropFirst(level)
        guard after.isEmpty || after.first == " " || after.first == "\t" else { return nil }
        var content = after.trimmingCharacters(in: .whitespaces)
        if let closing = content.range(of: #"(^|\s)#+$"#, options: .regularExpression) {
            content = content[..<closing.lowerBound].trimmingCharacters(in: .whitespaces)
        }
        return (level, content)
    }

    /// Lowercase ASCII letters and digits; every other run of characters becomes one `-`.
    static func slug(_ title: String) -> String {
        var out = ""
        for scalar in title.lowercased().unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
            } else if !out.isEmpty, !out.hasSuffix("-") {
                out.append("-")
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }

    static func trimBlankLines(_ lines: [String]) -> String {
        let isBlank = { (s: String) in s.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = lines.firstIndex(where: { !isBlank($0) }), let last = lines.lastIndex(where: { !isBlank($0) }) else { return "" }
        return lines[first...last].joined(separator: "\n")
    }
}
