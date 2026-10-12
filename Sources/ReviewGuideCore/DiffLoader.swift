import Foundation

public enum DiffLoader {
    /// Runs `git diff --find-renames --no-color --no-ext-diff <base> <head> -- :(top) :(top,exclude)<glob>…`,
    /// parses it and resolves `base` and `head`.
    ///
    /// - Parameters:
    ///   - range: `A...B` diffs from `git merge-base A B` to B; `A..B` and `A B` diff from A to B. An empty side
    ///     means `HEAD`. A single rev throws `UsageError`: the work tree is never diffed.
    ///   - exclude: Pathspec globs relative to the repository root, with git's default matching, in which `*`
    ///     also matches `/`: `*.png` removes `Assets/icon.png`.
    /// - Throws: `UsageError` for a malformed range or a rev that is not a commit, `GitError` when git fails otherwise.
    public static func load(git: Git, range: String, exclude: [String]) throws -> Diff {
        let (left, right, mergeBase) = try split(range: range)
        let head = try commit(git, right, range: range)
        let base = mergeBase
            ? try git.run(["merge-base", left, right]).trimmingCharacters(in: .whitespacesAndNewlines)
            : try commit(git, left, range: range)

        let diffArgs = ["-c", "core.quotePath=true", "diff", "--find-renames", "--no-color", "--no-ext-diff",
                        "--no-textconv", "-U3", "--src-prefix=a/", "--dst-prefix=b/", "--no-relative", base, head]
        let text = try git.run(diffArgs + ["--", ":(top)"] + exclude.map { ":(top,exclude)\($0)" })

        let excluded = try exclude.map { pattern in
            let names = try git.runData(diffArgs + ["--name-only", "-z", "--", ":(top)\(pattern)"])
            let files = names.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
            return Exclusion(pattern: pattern, files: files)
        }
        return Diff(range: range, base: base, head: head, files: DiffParser.parse(text), excluded: excluded)
    }

    static func split(range: String) throws -> (left: String, right: String, mergeBase: Bool) {
        func side(_ s: Substring) -> String { s.isEmpty ? "HEAD" : String(s) }
        let trimmed = range.trimmingCharacters(in: .whitespaces)
        if let dots = trimmed.range(of: "...") {
            return (side(trimmed[..<dots.lowerBound]), side(trimmed[dots.upperBound...]), true)
        }
        if let dots = trimmed.range(of: "..") {
            return (side(trimmed[..<dots.lowerBound]), side(trimmed[dots.upperBound...]), false)
        }
        let revs = trimmed.split(whereSeparator: \.isWhitespace)
        if revs.count == 2 { return (String(revs[0]), String(revs[1]), false) }
        if revs.count == 1 {
            throw UsageError("range '\(range)' names one rev; the work tree is never diffed, so use '\(trimmed)..HEAD'")
        }
        throw UsageError("range '\(range)' is not 'A...B', 'A..B' or 'A B'")
    }

    private static func commit(_ git: Git, _ rev: String, range: String) throws -> String {
        do {
            return try git.run(["rev-parse", "--verify", "\(rev)^{commit}"]).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as GitError {
            throw UsageError("range '\(range)': '\(rev)' is not a commit in \(git.repo.path) (\(error))")
        }
    }
}
