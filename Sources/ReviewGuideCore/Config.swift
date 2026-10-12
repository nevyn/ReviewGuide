import Foundation

/// User configuration per docs/cli.md.
public struct Config: Sendable, Equatable {
    /// The upload command template; `nil` when neither the environment nor the config file sets one.
    public var upload: String?

    public init(upload: String? = nil) { self.upload = upload }

    /// `~/.config/reviewguide/config`.
    public static var defaultFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/reviewguide/config")
    }

    /// Reads `file` when it exists, then lets a non-empty `REVIEWGUIDE_UPLOAD` in `environment` override `upload`.
    /// - Throws: `UsageError` naming the file and line for a malformed config file, or when it exists but cannot be read.
    public static func load(environment: [String: String] = ProcessInfo.processInfo.environment,
                            file: URL = Config.defaultFile) throws -> Config {
        var config = Config()
        if FileManager.default.fileExists(atPath: file.path) {
            let text: String
            do { text = try String(contentsOf: file, encoding: .utf8) }
            catch { throw UsageError("cannot read \(file.path): \(error.localizedDescription)") }
            config = try parse(text, file: file)
        }
        if let upload = environment["REVIEWGUIDE_UPLOAD"], !upload.trimmingCharacters(in: .whitespaces).isEmpty {
            config.upload = upload
        }
        return config
    }

    /// Parses `key = value` lines. `#` at the start of a line, or after whitespace, starts a comment.
    /// - Parameter file: Named in error messages only.
    /// - Throws: `UsageError` for a line without `=` or an unknown key.
    public static func parse(_ text: String, file: URL) throws -> Config {
        var config = Config()
        for (i, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            var line = Substring(raw)
            if let hash = line.indices.first(where: { line[$0] == "#" && ($0 == line.startIndex || line[line.index(before: $0)].isWhitespace) }) {
                line = line[..<hash]
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let eq = trimmed.firstIndex(of: "=") else {
                throw UsageError("\(file.path):\(i + 1): expected 'key = value', found '\(trimmed)'")
            }
            let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "upload": config.upload = value
            default: throw UsageError("\(file.path):\(i + 1): unknown key '\(key)'; the only key is 'upload'")
            }
        }
        return config
    }
}
