import Foundation

/// Runs the upload command on a file and returns the URL it printed.
public struct Uploader: Sendable {
    /// A `/bin/sh -c` template in which `{file}` stands for the shell-quoted absolute path of the file.
    public var command: String

    public init(command: String) { self.command = command }

    /// Substitutes `file` into the command and runs it. The command's stderr passes through to ours.
    /// - Returns: The last stdout line that starts with `http://` or `https://`.
    /// - Throws: `UploadError` when the file is missing, the template has no `{file}`, the command exits non-zero,
    ///   or it prints no URL.
    public func upload(file: URL) throws -> URL {
        let path = file.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: path) else { throw UploadError("no file to upload at \(path)") }
        guard command.contains("{file}") else { throw UploadError("the upload command `\(command)` has no {file} placeholder") }
        let script = command.replacingOccurrences(of: "{file}", with: Self.shellQuote(path))

        let result = try Subprocess.run(executable: "/bin/sh", arguments: ["-c", script], passStderrThrough: true)
        let stdout = String(decoding: result.stdout, as: UTF8.self)
        guard result.status == 0 else {
            throw UploadError("the upload command `\(script)` exited with status \(result.status)")
        }
        let line = stdout.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
        guard let line, let url = URL(string: line) else {
            let printed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            throw UploadError("the upload command `\(script)` printed no http(s) URL on stdout"
                              + (printed.isEmpty ? "" : "; it printed:\n\(printed)"))
        }
        return url
    }

    /// Wraps `s` in single quotes for `/bin/sh`.
    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public struct UploadError: Error, Sendable, Equatable, CustomStringConvertible {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}
