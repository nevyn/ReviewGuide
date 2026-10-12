import Foundation

/// Where a story and its review guides live.
public struct GuidePaths: Sendable, Equatable {
    public var story: URL
    /// The HTML review guide.
    public var html: URL
    /// The Markdown export. Named `.guide.md` so that it never overwrites a story called `.md`.
    public var markdown: URL

    public init(story: URL, html: URL, markdown: URL) { self.story = story; self.html = html; self.markdown = markdown }

    /// `<git-common-dir>/review-guides/<branch>.md`, `.html` and `.guide.md` for the branch checked out in `git.repo`.
    /// Slashes in the branch name become subdirectories. The common dir is shared by every worktree of a clone.
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
        let commonURL = common.hasPrefix("/") ? URL(fileURLWithPath: common) : git.repo.appendingPathComponent(common)
        let base = commonURL.standardizedFileURL.appendingPathComponent("review-guides").appendingPathComponent(branch)
        return GuidePaths(story: base.appendingPathExtension("md"), html: base.appendingPathExtension("html"),
                          markdown: base.appendingPathExtension("guide.md"))
    }

    /// Guides next to an explicit story: `x/foo.md` gives `x/foo.html` and `x/foo.guide.md`.
    public static func beside(story: URL) -> GuidePaths {
        let base = story.deletingPathExtension()
        return GuidePaths(story: story, html: base.appendingPathExtension("html"), markdown: base.appendingPathExtension("guide.md"))
    }
}
