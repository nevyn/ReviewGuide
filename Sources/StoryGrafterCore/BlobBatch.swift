import Foundation

/// Reads blobs through one long-lived `git cat-file --batch`, instead of starting git for every blob.
///
/// Safe to share between threads; requests are serialized. Falls back to `Git.show` for a path that contains a
/// newline, which the batch protocol cannot express.
public final class BlobBatch: @unchecked Sendable {
    private let git: Git
    private let process = Process()
    private let input: FileHandle
    private let output: FileHandle
    private var buffer = Data()
    private let lock = NSLock()

    /// Starts `git cat-file --batch` in `git.repo`. Throws when git cannot be started.
    public init(git: Git) throws {
        self.git = git
        let stdin = Pipe(), stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", git.repo.path, "cat-file", "--batch"]
        process.standardInput = stdin
        process.standardOutput = stdout
        try process.run()
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
    }

    deinit {
        try? input.close()
        process.waitUntilExit()
    }

    /// The blob at `rev:path`, or `nil` when there is no such blob (a missing path, or an object that is not a blob).
    /// Throws `GitError` when git stops answering.
    public func blob(rev: String, path: String) throws -> Data? {
        if path.contains("\n") { return try git.show(rev: rev, path: path) }
        return try lock.withLock {
            let object = "\(rev):\(path)"
            do { try input.write(contentsOf: Data((object + "\n").utf8)) } catch { throw failure(object, "\(error)") }
            guard let header = readLine() else { throw failure(object, "no response") }
            // "<sha> <type> <size>", or "<object> missing" / "<object> ambiguous"
            let fields = header.split(separator: " ")
            guard fields.count == 3, let size = Int(fields[2]) else { return nil }
            guard let content = read(size + 1) else { throw failure(object, "response truncated") }
            return fields[1] == "blob" ? content.prefix(size) : nil
        }
    }

    private func failure(_ object: String, _ detail: String) -> GitError {
        GitError(command: ["git", "cat-file", "--batch"], status: process.isRunning ? 0 : process.terminationStatus,
                 stderr: "reading \(object): \(detail)")
    }

    private func readLine() -> String? {
        while true {
            if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...newline)
                return line
            }
            guard fill() else { return nil }
        }
    }

    private func read(_ count: Int) -> Data? {
        while buffer.count < count { guard fill() else { return nil } }
        let data = Data(buffer.prefix(count))
        buffer.removeFirst(count)
        return data
    }

    private func fill() -> Bool {
        let chunk = output.availableData
        buffer.append(chunk)
        return !chunk.isEmpty
    }
}
