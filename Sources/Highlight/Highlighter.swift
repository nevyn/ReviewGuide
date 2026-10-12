import Foundation
import ReviewGuideCore

/// Tree-sitter syntax styling plus change styling within paired lines, per docs/architecture.md.
///
/// Each file side is read, parsed and styled once, on first use, and cached; a `Highlighter` is safe to share
/// between threads. Highlighting never throws: a file without a grammar, over 1 MB, not UTF-8 or unreadable
/// renders unstyled. Unexpected failures (git errors, parse timeouts, broken queries) are also reported on stderr,
/// naming the file and side.
public struct Highlighter: LineStyling {
    /// Reads the blob at `rev:path`; returns `nil` when the path does not exist at that rev.
    public typealias BlobReader = @Sendable (_ rev: String, _ path: String) throws -> Data?

    private let diff: Diff
    private let cache: FileCache

    /// `git` reads the old blobs at `diff.base` and the new blobs at `diff.head`, once per file.
    public init(git: Git, diff: Diff) {
        self.init(diff: diff, readBlob: { rev, path in try git.show(rev: rev, path: path) })
    }

    /// Styles `diff` with blobs from `readBlob`: old sides at (`diff.base`, `oldPath ?? path`),
    /// new sides at (`diff.head`, `path`). Added files have no old side and deleted files no new side.
    public init(diff: Diff, readBlob: @escaping BlobReader) {
        self.diff = diff
        self.cache = FileCache(readBlob: readBlob)
    }

    /// One `StyledLine` per entry of `hunk.lines`. Deleted lines take syntax from the old blob at `DiffLine.old`,
    /// added and context lines from the new blob at `DiffLine.new`. A line whose text differs from the blob's
    /// line (a blob that does not match the diff) is left unstyled.
    public func styles(for file: DiffFile, hunk: Hunk) -> [StyledLine] {
        hunk.lines.map { line in
            let side: FileCache.Side = line.kind == .del
                ? .init(rev: diff.base, path: file.oldPath ?? file.path, exists: file.status != .added)
                : .init(rev: diff.head, path: file.path, exists: file.status != .deleted)
            guard let number = line.kind == .del ? line.old : line.new,
                  let blobLines = cache.lines(for: side), number >= 1, number <= blobLines.count
            else { return Self.unstyled(line.text) }
            return Self.fit(blobLines[number - 1], text: line.text, blobText: cache.text(for: side, line: number))
        }
    }

    /// Syntax styling for a standalone snippet, one entry per `\n`-separated line. `language` is a Markdown
    /// info-string language (`swift`, `objective-c`, `ts`, `shell`) or a file extension (`kt`, `.yml`);
    /// unknown languages, and snippets over 1 MB, come back unstyled.
    public func styles(source: String, language: String) -> [StyledLine] {
        let unstyled = { splitLines(source).map { Self.unstyled(String($0)) } }
        guard let grammar = GrammarLanguage.named(language) else { return unstyled() }
        do { return try SyntaxStyler.styleLines(source, language: grammar) } catch {
            if !error.isExpected { FileCache.warn("highlighting a \(language) snippet: \(error)") }
            return unstyled()
        }
    }

    static func unstyled(_ text: String) -> StyledLine {
        let count = text.utf8.count
        return count == 0 ? [] : [StyledRun(bytes: 0..<count)]
    }

    /// Blob runs for a diff line, tolerating a trailing `\r` that one side has and the other lacks.
    static func fit(_ runs: StyledLine, text: String, blobText: Substring?) -> StyledLine {
        guard let blobText else { return unstyled(text) }
        func trimmed<S: StringProtocol>(_ s: S) -> S.SubSequence { s.hasSuffix("\r") ? s.dropLast() : s[...] }
        guard trimmed(blobText) == trimmed(text) else { return unstyled(text) }
        let count = text.utf8.count
        var result: StyledLine = []
        for run in runs where run.bytes.lowerBound < count {
            result.append(StyledRun(bytes: run.bytes.lowerBound..<min(run.bytes.upperBound, count), capture: run.capture))
        }
        if let end = result.last?.bytes.upperBound, end < count { result.append(StyledRun(bytes: end..<count)) }
        return result
    }
}

/// Styled lines per file side, read and styled once.
final class FileCache: @unchecked Sendable {
    struct Side: Hashable {
        var rev: String
        var path: String
        /// `false` for the old side of an added file and the new side of a deleted one.
        var exists: Bool
    }

    private struct Entry {
        var text: [Substring]
        var lines: [StyledLine]
    }

    private let readBlob: Highlighter.BlobReader
    private let lock = NSLock()
    private var entries: [Side: Entry?] = [:]

    init(readBlob: @escaping Highlighter.BlobReader) { self.readBlob = readBlob }

    func lines(for side: Side) -> [StyledLine]? { entry(for: side)?.lines }

    func text(for side: Side, line: Int) -> Substring? {
        guard let text = entry(for: side)?.text, line >= 1, line <= text.count else { return nil }
        return text[line - 1]
    }

    private func entry(for side: Side) -> Entry? {
        lock.lock()
        if let cached = entries[side] { lock.unlock(); return cached }
        lock.unlock()
        let entry = load(side)
        lock.lock()
        entries[side] = entry
        lock.unlock()
        return entry
    }

    private func load(_ side: Side) -> Entry? {
        guard side.exists, !side.rev.isEmpty else { return nil }
        let data: Data
        do {
            guard let blob = try readBlob(side.rev, side.path) else { return nil }
            data = blob
        } catch {
            Self.warn("reading \(side.rev):\(side.path): \(error)")
            return nil
        }
        guard let source = String(data: data, encoding: .utf8) else { return nil }
        let text = splitLines(source)
        let language = GrammarLanguage.detect(path: side.path) ?? text.first.flatMap(GrammarLanguage.detect(shebang:))
        guard let language else { return nil }
        do {
            return Entry(text: text, lines: try SyntaxStyler.styleLines(source, language: language))
        } catch {
            if !error.isExpected { Self.warn("highlighting \(side.rev):\(side.path): \(error)") }
            return nil
        }
    }

    static func warn(_ message: String) {
        FileHandle.standardError.write(Data("reviewguide: warning: \(message); left unstyled\n".utf8))
    }
}

/// Splits at `\n` only. `String.split` would keep `\r\n` together, since it is one `Character`.
func splitLines(_ source: String) -> [Substring] {
    source.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false).map { Substring($0) }
}
