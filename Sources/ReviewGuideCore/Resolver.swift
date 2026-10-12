import Foundation

public enum Resolver {
    /// Resolves every selector and checks coverage. Throws every selector and coverage problem found.
    ///
    /// Problems come in story order, then unplaced lines and file changes in diff order.
    public static func resolve(_ story: Story, against diff: Diff) throws(StoryProblems) -> ResolvedStory {
        let resolution = analyze(story, against: diff)
        if !resolution.problems.isEmpty { throw StoryProblems(resolution.problems) }
        return resolution.resolved
    }

    /// Resolves what it can and reports the rest, without throwing: `reviewguide list` shows placements
    /// of a story that does not yet cover its diff. A selector with a problem contributes no code.
    public static func analyze(_ story: Story, against diff: Diff) -> Resolution {
        var placements = Placements()
        var problems: [StoryProblem] = []
        var sections: [ResolvedSection] = []

        for section in story.sections {
            var code: [ShownCode] = []
            for selector in section.selectors ?? [] {
                func problem(_ message: String) {
                    problems.append(StoryProblem(sectionID: section.id, selector: selector.source, message: message))
                }
                switch pick(selector, in: diff) {
                case .failure(let message):
                    problem(message)
                case .success(.fileChange(let file)):
                    code.append(.fileChange(file: file, again: selector.again))
                    guard !selector.again else { continue }
                    if let other = placements.fileChanges[file.path] {
                        problem("'\(file.path)' (\(file.changeSummary)) is already placed in section '\(other)'")
                    } else {
                        placements.fileChanges[file.path] = section.id
                    }
                case .success(.hunks(let file, let picks)):
                    for (hunk, lines) in picks {
                        code.append(.hunk(file: file, hunk: hunk, lines: lines, again: selector.again))
                        guard !selector.again else { continue }
                        var clashes: [String: Int] = [:]
                        for index in lines where hunk.lines[index].isChange {
                            let key = Placements.LineKey(path: file.path, hunk: hunk.number, index: index)
                            if let other = placements.lines[key] { clashes[other, default: 0] += 1 }
                            else { placements.lines[key] = section.id }
                        }
                        for (other, count) in clashes.sorted(by: { $0.key < $1.key }) {
                            problem("'\(file.path)' #\(hunk.number): \(count) changed line\(count == 1 ? "" : "s") already placed in section '\(other)'")
                        }
                    }
                }
            }
            sections.append(ResolvedSection(section: section, code: code))
        }

        for file in diff.files {
            if file.isFileChange {
                if placements.fileChanges[file.path] == nil {
                    problems.append(StoryProblem(message: "unplaced: \(file.path) (\(file.changeSummary))"))
                }
                continue
            }
            for hunk in file.hunks {
                for (index, line) in hunk.lines.enumerated() where line.isChange {
                    guard placements.lines[.init(path: file.path, hunk: hunk.number, index: index)] == nil else { continue }
                    let old = line.old.map(String.init) ?? "-", new = line.new.map(String.init) ?? "-"
                    problems.append(StoryProblem(message: "unplaced: \(file.path) #\(hunk.number) \(old)/\(new): \(line.text)"))
                }
            }
        }

        return Resolution(resolved: ResolvedStory(story: story, diff: diff, sections: sections),
                          placements: placements, problems: problems)
    }

    private enum Pick {
        case fileChange(DiffFile)
        case hunks(DiffFile, [(Hunk, Range<Int>)])
    }

    private enum Outcome<T> { case success(T), failure(String) }

    private static func pick(_ selector: Selector, in diff: Diff) -> Outcome<Pick> {
        let file: DiffFile
        switch match(selector.path, in: diff) {
        case .success(let f): file = f
        case .failure(let message): return .failure(message)
        }

        if file.isFileChange {
            guard selector.hunks == .all, selector.lines == nil else {
                return .failure("'\(file.path)' is a file change without hunks (\(file.changeSummary)); select it by path alone")
            }
            return .success(.fileChange(file))
        }

        if case .anchored(let from, let to) = selector.lines {
            return anchoredRange(file: file, from: from, to: to)
        }

        let hunks: [Hunk]
        switch selector.hunks {
        case .all:
            hunks = file.hunks
        case .numbers(let numbers):
            if let bad = numbers.first(where: { $0 > file.hunks.count }) {
                return .failure("'\(file.path)' has \(file.hunks.count) hunk\(file.hunks.count == 1 ? "" : "s"); there is no #\(bad)")
            }
            hunks = numbers.map { file.hunks[$0 - 1] }
        case .anchor(let text):
            hunks = file.hunks.filter { $0.lines.contains { $0.text.contains(text) } }
            if hunks.isEmpty { return .failure("no hunk of '\(file.path)' contains \"\(text)\"") }
        }

        if case .range(let a, let b) = selector.lines {
            guard hunks.count == 1 else {
                return .failure("'lines' needs exactly one hunk, but the selector picks \(hunks.count)")
            }
            let hunk = hunks[0]
            guard b <= hunk.lines.count else {
                return .failure("lines \(a)-\(b) fall outside '\(file.path)' #\(hunk.number), which has \(hunk.lines.count) lines")
            }
            return .success(.hunks(file, [(hunk, (a - 1)..<b)]))
        }
        return .success(.hunks(file, hunks.map { ($0, 0..<$0.lines.count) }))
    }

    /// Resolves `@ "from" to "to"`. Anchors match the new side (context and added lines), and deleted lines only
    /// when the text is on no new-side line. Deleted lines travel with the line after them, or with the line before
    /// them when they end the hunk, so the range never splits a replacement.
    private static func anchoredRange(file: DiffFile, from: String, to: String) -> Outcome<Pick> {
        func describe(_ hunk: Hunk, _ i: Int) -> String {
            let line = hunk.lines[i]
            return "#\(hunk.number) \(line.old.map(String.init) ?? "-")/\(line.new.map(String.init) ?? "-")"
        }
        var newSide: [(Hunk, Int)] = [], oldSide: [(Hunk, Int)] = []
        for hunk in file.hunks {
            for (i, line) in hunk.lines.enumerated() where line.text.contains(from) {
                if line.kind == .del { oldSide.append((hunk, i)) } else { newSide.append((hunk, i)) }
            }
        }
        let hits = newSide.isEmpty ? oldSide : newSide
        guard let (hunk, start) = hits.first else {
            return .failure("no line of '\(file.path)' contains \"\(from)\"")
        }
        guard hits.count == 1 else {
            let side = newSide.isEmpty ? "deleted lines" : "lines of the new side"
            let places = hits.map { describe($0.0, $0.1) }.joined(separator: ", ")
            return .failure("\"\(from)\" is on \(hits.count) \(side) of '\(file.path)' (\(places)); it must be unique")
        }

        let rest = hunk.lines.indices[start...]
        let newEnd = rest.first { hunk.lines[$0].kind != .del && hunk.lines[$0].text.contains(to) }
        guard let end = newEnd ?? rest.first(where: { hunk.lines[$0].text.contains(to) }) else {
            return .failure("no line from \"\(from)\" (\(describe(hunk, start))) to the end of '\(file.path)' #\(hunk.number) contains \"\(to)\"")
        }

        var lower = start, upper = end
        if hunk.lines[start].kind != .del {
            while lower > 0, hunk.lines[lower - 1].kind == .del { lower -= 1 }
        }
        if hunk.lines[end].kind != .del, hunk.lines[(end + 1)...].allSatisfy({ $0.kind == .del }) {
            upper = hunk.lines.count - 1
        }
        return .success(.hunks(file, [(hunk, lower..<(upper + 1))]))
    }

    private static func match(_ path: String, in diff: Diff) -> Outcome<DiffFile> {
        let exact = diff.files.filter { $0.path == path }
        let found = exact.isEmpty ? diff.files.filter { $0.path.hasSuffix("/" + path) } : exact
        if found.count == 1 { return .success(found[0]) }
        if found.count > 1 {
            return .failure("matches \(found.count) files: \(found.map(\.path).joined(separator: ", ")); write more of the path")
        }
        for exclusion in diff.excluded {
            if let hit = exclusion.files.first(where: { $0 == path || $0.hasSuffix("/" + path) }) {
                return .failure("matches no file in the diff: '\(hit)' is excluded by '\(exclusion.pattern)'")
            }
        }
        return .failure("matches no file in the diff")
    }
}

/// The outcome of `Resolver.analyze`: what resolved, where each change landed, and every problem.
public struct Resolution: Sendable, Equatable {
    /// Every section, with the code of the selectors that resolved.
    public var resolved: ResolvedStory
    public var placements: Placements
    /// Empty when the story satisfies the diff; ordered like `Resolver.resolve` throws them.
    public var problems: [StoryProblem]
}

/// The section that placed each changed line and file change. Lines shown with `again` are not placements.
public struct Placements: Sendable, Equatable {
    struct LineKey: Hashable, Sendable {
        var path: String
        var hunk: Int
        var index: Int
    }

    var lines: [LineKey: String] = [:]
    var fileChanges: [String: String] = [:]

    /// The id of the section that placed `hunk.lines[index]` of `file`; `nil` when unplaced or a context line.
    public func sectionID(file: DiffFile, hunk: Hunk, index: Int) -> String? {
        lines[LineKey(path: file.path, hunk: hunk.number, index: index)]
    }

    /// The id of the section that placed `file`, a file change without hunks; `nil` when unplaced.
    public func sectionID(fileChange file: DiffFile) -> String? { fileChanges[file.path] }
}

extension DiffFile {
    /// How the file changed, as `reviewguide list` and unplaced problems print it: `renamed from Old.swift`,
    /// `binary`, `mode change`, `added`, `deleted`, `copied from x`, `modified`.
    public var changeSummary: String {
        switch status {
        case .renamed: "renamed from \(oldPath ?? "?")"
        case .copied: "copied from \(oldPath ?? "?")"
        case .mode: "mode change"
        default: status.rawValue
        }
    }
}
