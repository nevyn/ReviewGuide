import Foundation

/// Where a story and its review guides live.
public struct GuidePaths: Sendable, Equatable {
    public var story: URL
    /// The HTML review guide.
    public var html: URL
    /// The Markdown export. Named `.guide.md` so that it never overwrites a story called `.md`.
    public var markdown: URL
    /// Why the branch default is where it is; `nil` for explicit `--story` paths.
    public var location: Location?

    public enum Location: Sendable, Equatable {
        /// `<worktree>/.storygrafter/`, which a `.gitignore` of `*` inside it keeps out of `git status`.
        case worktree
        /// `<git-common-dir>/review-guides/`, where storygrafter 0.3 and earlier kept stories. Read, never chosen anew.
        case gitDirectory
        /// `/tmp/storygrafter/<repo>-<hash>/`, used when the worktree is not writable. It survives until reboot.
        case temporary
    }

    public init(story: URL, html: URL, markdown: URL, location: Location? = nil) {
        self.story = story; self.html = html; self.markdown = markdown; self.location = location
    }

    /// The default paths for the branch checked out in `git.repo`, with slashes in the branch name as subdirectories.
    ///
    /// The story lives in `<worktree>/.storygrafter/<branch>.md`, beside the code that it describes and inside the
    /// directory that agent sandboxes let an agent write; `.git` is not such a directory. The tool writes a
    /// `.gitignore` of `*` into `.storygrafter/`, so the directory never shows in `git status` and the repository's own
    /// ignore files stay untouched. A story that already exists wins, checked in this order: the worktree,
    /// `<git-common-dir>/review-guides/` (where 0.3 and earlier kept it), then `/tmp/storygrafter/<repo>-<hash>/`.
    /// When the worktree cannot be written, a new story goes to `/tmp` (not `$TMPDIR`, which sandboxes replace).
    /// Creates the chosen directory.
    /// - Throws: `UsageError` on a detached HEAD, `GitError` outside a repository.
    public static func forCurrentBranch(git: Git) throws -> GuidePaths {
        let symbolic = try Subprocess.run(executable: "/usr/bin/env",
                                          arguments: ["git", "-C", git.repo.path, "symbolic-ref", "--short", "-q", "HEAD"])
        let branch = String(decoding: symbolic.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard symbolic.status == 0, !branch.isEmpty else {
            _ = try git.run(["rev-parse", "--git-dir"])  // Throws a GitError when this is not a repository at all.
            throw UsageError("HEAD is detached in \(git.repo.path), so there is no branch to name the story after; pass --story FILE")
        }
        let common = try git.run(["rev-parse", "--git-common-dir"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let commonURL = (common.hasPrefix("/") ? URL(fileURLWithPath: common) : git.repo.appendingPathComponent(common))
            .standardizedFileURL

        let top = try git.run(["rev-parse", "--show-toplevel"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let storyRoot = URL(fileURLWithPath: top).standardizedFileURL.appendingPathComponent(".storygrafter")

        let worktree = paths(base: storyRoot.appendingPathComponent(branch), location: .worktree)
        let legacy = paths(base: commonURL.appendingPathComponent("review-guides").appendingPathComponent(branch),
                           location: .gitDirectory)
        let fallback = paths(base: temporaryRoot(forCommonDir: commonURL).appendingPathComponent(branch),
                             location: .temporary)
        let fm = FileManager.default
        for existing in [worktree, legacy, fallback] where fm.fileExists(atPath: existing.story.path) {
            if existing.location == .worktree { _ = ignoring(storyRoot) }
            return existing
        }
        if ignoring(storyRoot), canWrite(worktree.story.deletingLastPathComponent()) { return worktree }
        try fm.createDirectory(at: fallback.story.deletingLastPathComponent(), withIntermediateDirectories: true)
        return fallback
    }

    /// Guides next to an explicit story: `x/foo.md` gives `x/foo.html` and `x/foo.guide.md`.
    public static func beside(story: URL) -> GuidePaths {
        let base = story.deletingPathExtension()
        return GuidePaths(story: story, html: base.appendingPathExtension("html"), markdown: base.appendingPathExtension("guide.md"))
    }

    /// `/tmp/storygrafter/<repo>-<hash>`: the repository's directory name for people, a hash of the common dir so
    /// that two clones of the same repository never share stories.
    static func temporaryRoot(forCommonDir commonDir: URL) -> URL {
        let name = commonDir.lastPathComponent == ".git" ? commonDir.deletingLastPathComponent().lastPathComponent
                                                         : commonDir.lastPathComponent
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325  // FNV-1a: stable across runs, unlike Hasher
        for byte in commonDir.path.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return URL(fileURLWithPath: "/tmp/storygrafter")
            .appendingPathComponent("\(name)-\(String(hash, radix: 16).prefix(8))")
    }

    private static func paths(base: URL, location: Location) -> GuidePaths {
        GuidePaths(story: base.appendingPathExtension("md"), html: base.appendingPathExtension("html"),
                   markdown: base.appendingPathExtension("guide.md"), location: location)
    }

    /// Creates `root` with a `.gitignore` of `*` in it, unless one is there already; false when that fails.
    private static func ignoring(_ root: URL) -> Bool {
        let ignore = root.appendingPathComponent(".gitignore")
        if FileManager.default.fileExists(atPath: ignore.path) { return true }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("*\n".utf8).write(to: ignore)
            return true
        } catch {
            return false
        }
    }

    /// Creates `directory` and a probe file in it. Permission bits don't tell: sandboxes deny writes that they allow.
    private static func canWrite(_ directory: URL) -> Bool {
        let probe = directory.appendingPathComponent(".storygrafter-probe-\(ProcessInfo.processInfo.processIdentifier)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: probe)
            try FileManager.default.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }
}
