import Foundation

public enum DiffParser {
    /// Parses unified diff text as `git diff` prints it with `a/` and `b/` prefixes. Hunk numbers are assigned per file.
    ///
    /// Handles added, deleted, renamed, copied, binary and mode-only files, C-quoted paths, the tab git appends
    /// to `---`/`+++` paths that contain spaces, `\ No newline at end of file`, and blank context lines.
    /// A binary file is `.binary` unless it was deleted, renamed or copied; `.mode` means nothing but the mode changed.
    /// A trailing `\r` is stripped from line text.
    public static func parse(_ text: String) -> [DiffFile] {
        var files: [DiffFile] = []
        var current: FileBuilder?
        var hunk: HunkBuilder?

        func finishHunk() {
            if let h = hunk, var f = current {
                f.hunks.append(h.build(number: f.hunks.count + 1))
                current = f
            }
            hunk = nil
        }
        func finishFile() {
            finishHunk()
            if let f = current { files.append(f.build()) }
            current = nil
        }

        for raw in text.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false) {
            var line = String(decoding: raw, as: UTF8.self)
            if line.hasSuffix("\r") { line.removeLast() }

            // Mutate in place: a bound copy of `hunk` would share `lines` and force a copy on every append.
            if hunk?.isOpen == true {
                hunk!.consume(line)
                continue
            }
            if line.hasPrefix("\\") { continue }  // "\ No newline at end of file" after the last body line
            if line.hasPrefix("diff --git ") {
                finishFile()
                current = FileBuilder(gitLine: String(line.dropFirst("diff --git ".count)))
                continue
            }
            guard current != nil else { continue }
            if line.hasPrefix("@@ ") {
                finishHunk()
                hunk = HunkBuilder(header: line)
                continue
            }
            current?.header(line)
        }
        finishFile()
        return files
    }
}

private struct FileBuilder {
    var gitPaths: (old: String, new: String)?
    var oldPath: String?
    var newPath: String?
    var renameFrom: String?, renameTo: String?
    var copyFrom: String?, copyTo: String?
    var added = false, deleted = false, binary = false, modeChanged = false
    var hunks: [Hunk] = []

    init(gitLine: String) { gitPaths = Self.splitGitLine(gitLine) }

    mutating func header(_ line: String) {
        func value(_ prefix: String) -> String? {
            line.hasPrefix(prefix) ? unquote(String(line.dropFirst(prefix.count))) : nil
        }
        if line.hasPrefix("new file mode ") { added = true }
        else if line.hasPrefix("deleted file mode ") { deleted = true }
        else if line.hasPrefix("old mode ") || line.hasPrefix("new mode ") { modeChanged = true }
        else if let v = value("rename from ") { renameFrom = v }
        else if let v = value("rename to ") { renameTo = v }
        else if let v = value("copy from ") { copyFrom = v }
        else if let v = value("copy to ") { copyTo = v }
        else if line.hasPrefix("--- ") { oldPath = Self.headerPath(String(line.dropFirst(4)), prefix: "a/") }
        else if line.hasPrefix("+++ ") { newPath = Self.headerPath(String(line.dropFirst(4)), prefix: "b/") }
        else if line.hasPrefix("Binary files ") || line == "GIT binary patch" { binary = true }
    }

    func build() -> DiffFile {
        let old = renameFrom ?? copyFrom ?? oldPath ?? gitPaths?.old
        let new = renameTo ?? copyTo ?? newPath ?? gitPaths?.new
        let status: FileStatus
        if deleted { status = .deleted }
        else if renameTo != nil { status = .renamed }
        else if copyTo != nil { status = .copied }
        else if binary { status = .binary }
        else if added { status = .added }
        else if modeChanged && hunks.isEmpty { status = .mode }
        else { status = .modified }
        let path = (deleted ? old : new) ?? old ?? ""
        let shownOld = (status == .renamed || status == .copied) ? old : nil
        return DiffFile(path: path, oldPath: shownOld, status: status, hunks: hunks)
    }

    /// `--- a/x`, `+++ b/x`, possibly C-quoted, possibly with a trailing tab; `nil` for `/dev/null`.
    static func headerPath(_ field: String, prefix: String) -> String? {
        var field = field
        if !field.hasPrefix("\""), field.hasSuffix("\t") { field.removeLast() }
        let path = unquote(field)
        if path == "/dev/null" { return nil }
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    /// Splits `a/<old> b/<new>` from a `diff --git` line. Unquoted paths with spaces are ambiguous; git only
    /// prints such a line with two different paths for renames and copies, whose header lines name both paths.
    static func splitGitLine(_ rest: String) -> (old: String, new: String)? {
        if rest.hasPrefix("\"") {
            guard let (first, remainder) = takeQuoted(rest) else { return nil }
            let second = remainder.trimmingCharacters(in: .whitespaces)
            return (strip(first, "a/"), strip(unquote(second), "b/"))
        }
        if rest.hasSuffix("\""), let open = rest.range(of: " \"", options: .backwards) {
            return (strip(String(rest[..<open.lowerBound]), "a/"), strip(unquote(String(rest[open.upperBound...]).withQuote), "b/"))
        }
        let chars = Array(rest)
        if chars.count >= 5, (chars.count - 5) % 2 == 0 {
            let n = (chars.count - 5) / 2
            let a = String(chars[2..<(2 + n)]), b = String(chars[(5 + n)...])
            if rest.hasPrefix("a/"), String(chars[(2 + n)..<(5 + n)]) == " b/", a == b { return (a, b) }
        }
        guard let space = rest.range(of: " b/") else { return nil }
        return (strip(String(rest[..<space.lowerBound]), "a/"), String(rest[space.upperBound...]))
    }

    static func strip(_ s: String, _ prefix: String) -> String { s.hasPrefix(prefix) ? String(s.dropFirst(prefix.count)) : s }
}

private extension String {
    var withQuote: String { "\"" + self }
}

private struct HunkBuilder {
    var header: String
    var oldStart = 0, oldCount = 1, newStart = 0, newCount = 1
    var remainingOld = 0, remainingNew = 0
    var nextOld = 0, nextNew = 0
    var lines: [DiffLine] = []

    init(header line: String) {
        // @@ -a[,b] +c[,d] @@[ function context]
        let afterOpen = line.dropFirst(3)
        let close = afterOpen.range(of: " @@")
        let ranges = close.map { afterOpen[..<$0.lowerBound] } ?? afterOpen
        header = close.map { String(afterOpen[$0.upperBound...]).trimmingCharacters(in: .whitespaces) } ?? ""
        for part in ranges.split(separator: " ") {
            let numbers = part.dropFirst().split(separator: ",").map { Int($0) ?? 0 }
            let start = numbers.first ?? 0, count = numbers.count > 1 ? numbers[1] : 1
            if part.hasPrefix("-") { oldStart = start; oldCount = count }
            if part.hasPrefix("+") { newStart = start; newCount = count }
        }
        remainingOld = oldCount; remainingNew = newCount
        nextOld = oldStart; nextNew = newStart
    }

    var isOpen: Bool { remainingOld > 0 || remainingNew > 0 }

    mutating func consume(_ line: String) {
        let text = line.isEmpty ? "" : String(line.dropFirst())
        switch line.first {
        case "+":
            lines.append(DiffLine(kind: .add, old: nil, new: nextNew, text: text))
            nextNew += 1; remainingNew -= 1
        case "-":
            lines.append(DiffLine(kind: .del, old: nextOld, new: nil, text: text))
            nextOld += 1; remainingOld -= 1
        case "\\":
            break
        default:  // " " or an empty line, which git prints for a blank context line with diff.suppressBlankEmpty
            lines.append(DiffLine(kind: .context, old: nextOld, new: nextNew, text: text))
            nextOld += 1; nextNew += 1; remainingOld -= 1; remainingNew -= 1
        }
    }

    func build(number: Int) -> Hunk {
        Hunk(number: number, header: header, oldStart: oldStart, oldCount: oldCount,
             newStart: newStart, newCount: newCount, lines: lines)
    }
}

/// Decodes a C-quoted git path (`"a/\303\274 \"x\""`); returns other strings unchanged.
func unquote(_ s: String) -> String {
    guard s.hasPrefix("\""), let (value, _) = takeQuoted(s) else { return s }
    return value
}

/// Decodes the C-quoted string at the start of `s` and returns it with the text after the closing quote.
private func takeQuoted(_ s: String) -> (String, Substring)? {
    var bytes: [UInt8] = []
    let utf8 = Array(s.utf8)
    var i = 1
    while i < utf8.count {
        let c = utf8[i]
        if c == UInt8(ascii: "\"") {
            let restIndex = s.utf8.index(s.utf8.startIndex, offsetBy: i + 1)
            return (String(decoding: bytes, as: UTF8.self), s[restIndex...])
        }
        if c == UInt8(ascii: "\\"), i + 1 < utf8.count {
            let e = utf8[i + 1]
            if (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(e), i + 3 < utf8.count {
                let digits = utf8[(i + 1)...(i + 3)].map { Int($0) - 48 }
                bytes.append(UInt8(truncatingIfNeeded: digits[0] * 64 + digits[1] * 8 + digits[2]))
                i += 4
                continue
            }
            let escapes: [UInt8: UInt8] = [
                UInt8(ascii: "a"): 7, UInt8(ascii: "b"): 8, UInt8(ascii: "t"): 9, UInt8(ascii: "n"): 10,
                UInt8(ascii: "v"): 11, UInt8(ascii: "f"): 12, UInt8(ascii: "r"): 13,
            ]
            bytes.append(escapes[e] ?? e)
            i += 2
            continue
        }
        bytes.append(c)
        i += 1
    }
    return nil
}
