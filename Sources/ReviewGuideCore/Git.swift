import Foundation

/// Runs git in one repository.
public struct Git: Sendable {
    /// The directory passed to `git -C`; a work tree or any directory inside one.
    public var repo: URL
    public init(repo: URL) { self.repo = repo }

    /// Runs `git -C <repo> <args>` and returns stdout, decoded as UTF-8 with invalid bytes repaired.
    /// Throws `GitError` naming the command, the exit status and git's stderr on non-zero exit.
    public func run(_ args: [String]) throws -> String {
        String(decoding: try runData(args), as: UTF8.self)
    }

    /// Runs `git -C <repo> <args>` and returns stdout as raw bytes. Throws like `run(_:)`.
    public func runData(_ args: [String]) throws -> Data {
        let command = ["git", "-C", repo.path] + args
        let result = try Subprocess.run(executable: "/usr/bin/env", arguments: command)
        guard result.status == 0 else {
            throw GitError(command: command, status: result.status, stderr: String(decoding: result.stderr, as: UTF8.self))
        }
        return result.stdout
    }

    /// The blob at `rev:path`, or `nil` when the path does not exist at that rev.
    /// `path` is relative to the repository root. Throws `GitError` when `rev` itself does not resolve.
    public func show(rev: String, path: String) throws -> Data? {
        let object = "\(rev):\(path)"
        let exists = try Subprocess.run(executable: "/usr/bin/env", arguments: ["git", "-C", repo.path, "cat-file", "-e", object])
        guard exists.status == 0 else {
            _ = try run(["rev-parse", "--verify", "\(rev)^{tree}"])
            return nil
        }
        return try runData(["cat-file", "blob", object])
    }
}

/// A git command that exited non-zero.
public struct GitError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The full argument vector, starting with `git`.
    public var command: [String]
    public var status: Int32
    /// git's stderr, trimmed.
    public var stderr: String

    public init(command: [String], status: Int32, stderr: String) {
        self.command = command; self.status = status
        self.stderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var description: String {
        let detail = stderr.isEmpty ? "" : ": \(stderr)"
        return "`\(command.joined(separator: " "))` exited with status \(status)\(detail)"
    }
}

/// Invalid input that is not a story problem: a bad range, a missing file, a detached HEAD.
public struct UsageError: Error, Sendable, Equatable, CustomStringConvertible {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

enum Subprocess {
    struct Result { var status: Int32; var stdout: Data; var stderr: Data }

    /// Runs a process to completion and captures stdout; stderr is captured, or passed through to ours.
    static func run(executable: String, arguments: [String], passStderrThrough: Bool = false) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        if !passStderrThrough { process.standardError = err }
        try process.run()

        // Drain stderr concurrently so that neither pipe fills up and blocks the child.
        let errData = LockedData()
        let group = DispatchGroup()
        if !passStderrThrough {
            DispatchQueue.global().async(group: group) { errData.set(err.fileHandleForReading.readDataToEndOfFile()) }
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, stdout: outData, stderr: errData.get())
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func set(_ value: Data) { lock.withLock { data = value } }
    func get() -> Data { lock.withLock { data } }
}
