import Foundation
@testable import StoryGrafterCore

/// A throwaway repository under the temporary directory. Never cleaned up; nothing outside it is touched.
struct TempRepo {
    let url: URL
    let git: Git

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("StoryGrafterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        git = Git(repo: url)
        _ = try git.run(["init", "-q", "-b", "main"])
    }

    func write(_ path: String, _ text: String) throws { try write(path, Data(text.utf8)) }

    func write(_ path: String, _ data: Data) throws {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
    }

    @discardableResult
    func commit(_ message: String) throws -> String {
        _ = try git.run(["add", "-A"])
        _ = try git.run(["-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false",
                         "commit", "-q", "-m", message])
        return try git.run(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// main: base, then one more commit after `feature` branches off. feature: a change of every kind.
    static func standard() throws -> TempRepo {
        let repo = try TempRepo()
        try repo.write("Sources/Clock/Station.swift", (1...30).map { "let line\($0) = \($0)" }.joined(separator: "\n") + "\n")
        try repo.write("Sources/Old.swift", "struct Old {}\n")
        try repo.write("Docs/Guide Notes.md", "# Notes\nfirst\n")
        try repo.write("Moving.txt", (1...20).map { "row \($0)" }.joined(separator: "\n") + "\n")
        try repo.write("Assets/icon.png", Data([0, 1, 2]))
        try repo.commit("base")
        _ = try repo.git.run(["checkout", "-q", "-b", "feature"])

        var station = (1...30).map { "let line\($0) = \($0)" }
        station[2] = "let line3 = 300"
        station[24] = "let line25 = 2500"
        try repo.write("Sources/Clock/Station.swift", station.joined(separator: "\n") + "\n")
        try repo.write("Sources/Clock/Drift.swift", "struct Drift {\n    var skew = 0\n}\n")
        _ = try repo.git.run(["rm", "-q", "Sources/Old.swift"])
        try repo.write("Docs/Guide Notes.md", "# Notes\nsecond\n")
        _ = try repo.git.run(["mv", "Moving.txt", "Moved.txt"])
        try repo.write("Assets/icon.png", Data([0, 1, 3]))
        try repo.write("Assets/logo.bin", Data([0, 9]))
        try repo.commit("feature")

        _ = try repo.git.run(["checkout", "-q", "main"])
        try repo.write("Unrelated.txt", "on main only\n")
        try repo.commit("main moves on")
        _ = try repo.git.run(["checkout", "-q", "feature"])
        return repo
    }
}
