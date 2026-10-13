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
        /// `<git-common-dir>/review-guides/`, shared by every worktree of the clone.
        case gitDirectory
        /// `/tmp/storygrafter/<repo>-<hash>/`, used when the git directory is not writable, as in sandboxed agents.
        /// The directory survives until reboot.
        case temporary
    }

    public init(story: URL, html: URL, markdown: URL, location: Location? = nil) {
        self.story = story; self.html = html; self.markdown = markdown; self.location = location
    }

    /// The default paths for the branch checked out in `git.repo`, with slashes in the branch name as subdirectories.
    ///
    /// The story lives in `<git-common-dir>/review-guides/<branch>.md` when that directory can be written, and in
    /// `/tmp/storygrafter/<repo>-<hash>/<branch>.md` otherwise. An existing story wins over writability, so a story
    /// that a sandboxed agent wrote to `/tmp` is still found from outside the sandbox. `/tmp` rather than `$TMPDIR`,
    /// because sandboxes set their own `$TMPDIR`. Creates the chosen directory.
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

        let primary = paths(base: commonURL.appendingPathComponent("review-guides").appendingPathComponent(branch),
                            location: .gitDirectory)
        let fallback = paths(base: temporaryRoot(forCommonDir: commonURL).appendingPathComponent(branch),
                             location: .temporary)
        let fm = FileManager.default
        if fm.fileExists(atPath: primary.story.path) { return primary }
        if fm.fileExists(atPath: fallback.story.path) { return fallback }
        if canWrite(primary.story.deletingLastPathComponent()) { return primary }
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
