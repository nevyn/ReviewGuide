import Foundation
import StoryGrafterCore
import SwiftTreeSitter

/// Whole-file syntax styling: parse, run the highlight query, flatten captures, split into lines.
enum SyntaxStyler {
    /// Sources above this size are left unstyled.
    static let maxBytes = 1 << 20
    /// A parse that runs longer than this is abandoned and the source left unstyled.
    static let parseTimeout: TimeInterval = 2

    /// Syntax runs for each `\n`-separated line of `source`, or `nil` when it cannot be styled.
    /// Runs cover each line's UTF-8 bytes, never split a scalar, and have `changed == false`.
    static func styleLines(_ source: String, language: GrammarLanguage) throws(HighlightError) -> [StyledLine] {
        guard source.utf8.count <= maxBytes else { throw .tooLarge(bytes: source.utf8.count) }
        let tree = try parse(source, language: language)
        var captures = try captures(in: tree, source: source, language: language)
        if language == .markdown {
            captures += try inlineCaptures(blockTree: tree, source: source, patternOffset: try query(for: .markdown).patternCount)
        }
        return lines(of: source, winners: flatten(captures, utf16Count: source.utf16.count))
    }

    // MARK: Parsing and queries

    private static func parse(_ source: String, language: GrammarLanguage, ranges: [TSRange]? = nil) throws(HighlightError) -> MutableTree {
        let parser = Parser()
        do { try parser.setLanguage(language.tsLanguage) } catch { throw .incompatibleGrammar(language.rawValue) }
        parser.timeout = parseTimeout
        if let ranges { parser.includedRanges = ranges }
        guard let tree = parser.parse(source) else { throw .parseTimedOut(language: language.rawValue) }
        return tree
    }

    /// A capture after normalisation, in UTF-16 code units of the source.
    struct Capture {
        var range: NSRange
        var pattern: Int
        var style: String?
    }

    private static func captures(in tree: MutableTree, source: String, language: GrammarLanguage, patternOffset: Int = 0) throws(HighlightError) -> [Capture] {
        let query = try query(for: language)
        var result: [Capture] = []
        let matches = query.execute(in: tree).resolve(with: Predicate.Context(string: source))
        for match in matches where unhandledPredicatesAllow(match) {
            for capture in match.captures {
                let style: String?
                switch CaptureNames.normalise(capture.name ?? "") {
                case .style(let name): style = name
                case .plain: style = nil
                case .ignore: continue
                }
                result.append(Capture(range: capture.range, pattern: patternOffset + match.patternIndex, style: style))
            }
        }
        return result
    }

    /// Evaluates the predicates that SwiftTreeSitter passes through unevaluated. Unknown ones reject the match,
    /// since a pattern such as `((identifier) @property (#has-ancestor? @property struct_declaration))` would
    /// otherwise restyle every identifier.
    private static func unhandledPredicatesAllow(_ match: QueryMatch) -> Bool {
        match.predicates.allSatisfy { predicate in
            guard case let .generic(name, strings, captureNames) = predicate else { return true }
            switch name {
            case "has-ancestor?", "not-has-ancestor?":
                let types = Set(strings)
                let found = match.captures.filter { captureNames.contains($0.name ?? "") }.allSatisfy { capture in
                    var node = capture.node.parent
                    while let current = node {
                        if let type = current.nodeType, types.contains(type) { return true }
                        node = current.parent
                    }
                    return false
                }
                return name == "has-ancestor?" ? found : !found
            default:
                return false
            }
        }
    }

    /// The inline grammar runs over the block tree's `inline` and table-cell ranges, as the grammar's injections specify.
    private static func inlineCaptures(blockTree: MutableTree, source: String, patternOffset: Int) throws(HighlightError) -> [Capture] {
        var ranges: [TSRange] = []
        func collect(_ node: Node) {
            if node.nodeType == "inline" || node.nodeType == "pipe_table_cell" {
                ranges.append(node.tsRange)
                return
            }
            node.enumerateChildren(block: collect)
        }
        guard let root = blockTree.rootNode else { return [] }
        collect(root)
        guard !ranges.isEmpty else { return [] }
        let tree = try parse(source, language: .markdownInline, ranges: ranges)
        return try captures(in: tree, source: source, language: .markdownInline, patternOffset: patternOffset)
    }

    private static let queryCache = QueryCache()

    static func query(for language: GrammarLanguage) throws(HighlightError) -> Query {
        try queryCache.query(for: language)
    }

    // MARK: Flattening

    /// For each UTF-16 unit, the index into `styles` of its winning capture, or -1 for none.
    /// The innermost (shortest) capture wins; on equal ranges, the later pattern wins.
    static func flatten(_ captures: [Capture], utf16Count: Int) -> (winners: [Int32], styles: [String?]) {
        var styles: [String?] = []
        var styleIDs: [String?: Int32] = [:]
        var winners = [Int32](repeating: -1, count: utf16Count)
        let ordered = captures.enumerated().sorted { a, b in
            if a.element.range.length != b.element.range.length { return a.element.range.length > b.element.range.length }
            if a.element.pattern != b.element.pattern { return a.element.pattern < b.element.pattern }
            return a.offset < b.offset
        }
        for (_, capture) in ordered {
            let id: Int32
            if let known = styleIDs[capture.style] { id = known } else {
                id = Int32(styles.count)
                styles.append(capture.style)
                styleIDs[capture.style] = id
            }
            let lower = max(0, capture.range.location)
            let upper = min(utf16Count, capture.range.location + capture.range.length)
            guard lower < upper else { continue }
            for unit in lower..<upper { winners[unit] = id }
        }
        return (winners, styles)
    }

    /// Splits flattened winners into per-line runs over UTF-8 bytes.
    static func lines(of source: String, winners: (winners: [Int32], styles: [String?])) -> [StyledLine] {
        var result: [StyledLine] = []
        var line: StyledLine = []
        var utf16 = 0
        var byte = 0
        for scalar in source.unicodeScalars {
            if scalar == "\n" {
                result.append(line)
                line = []
                utf16 += 1
                byte = 0
                continue
            }
            let winner = winners.winners[utf16]
            let style = winner < 0 ? nil : winners.styles[Int(winner)]
            let width = scalar.utf8.count
            if let last = line.last, last.capture == style {
                line[line.count - 1].bytes = last.bytes.lowerBound..<(byte + width)
            } else {
                line.append(StyledRun(bytes: byte..<(byte + width), capture: style))
            }
            byte += width
            utf16 += scalar.utf16.count
        }
        result.append(line)
        return result
    }
}

/// Why a source was left unstyled.
enum HighlightError: Error, CustomStringConvertible {
    case tooLarge(bytes: Int)
    case notUTF8
    case incompatibleGrammar(String)
    case parseTimedOut(language: String)
    case queryMissing(String)
    case queryInvalid(language: String, error: String)

    var description: String {
        switch self {
        case .tooLarge(let bytes): "\(bytes) bytes is over the \(SyntaxStyler.maxBytes)-byte limit"
        case .notUTF8: "not UTF-8"
        case .incompatibleGrammar(let language): "the \(language) grammar's ABI does not match the tree-sitter runtime"
        case .parseTimedOut(let language): "the \(language) parse took over \(Int(SyntaxStyler.parseTimeout)) s"
        case .queryMissing(let language): "Resources/queries/\(language).scm is missing from the StoryGrafter_Highlight bundle"
        case .queryInvalid(let language, let error): "Resources/queries/\(language).scm does not compile: \(error)"
        }
    }

    /// Expected limits, not faults: not worth a warning.
    var isExpected: Bool {
        switch self {
        case .tooLarge, .notUTF8: true
        default: false
        }
    }
}

/// Compiled highlight queries, one per language, loaded on first use.
final class QueryCache: @unchecked Sendable {
    private let lock = NSLock()
    private var queries: [GrammarLanguage: Result<Query, HighlightError>] = [:]

    static var bundle: Bundle { ResourceBundle.named("StoryGrafter_Highlight") ?? Bundle.module }

    func query(for language: GrammarLanguage) throws(HighlightError) -> Query {
        lock.lock()
        defer { lock.unlock() }
        if let cached = queries[language] { return try cached.get() }
        let result = Result<Query, HighlightError> { () throws(HighlightError) -> Query in
            guard let url = Self.bundle.url(forResource: language.rawValue, withExtension: "scm", subdirectory: "Resources/queries")
            else { throw .queryMissing(language.rawValue) }
            do { return try Query(language: language.tsLanguage, url: url) } catch {
                throw .queryInvalid(language: language.rawValue, error: String(describing: error))
            }
        }
        queries[language] = result
        return try result.get()
    }
}
