import Foundation

/// A fenced code block's info string: a plain code block or an attachment.
struct FenceInfo: Equatable {
    struct Attachment: Equatable {
        var caption: String
        /// Relative to the story file's directory.
        var file: String?
    }

    /// The first word of the info string, or the `file=` extension; empty when neither gives one.
    var language: String
    var attachment: Attachment?

    /// Parses `<lang>`, `<lang> attachment "<caption>"` or `attachment "<caption>" file=<path>`.
    /// Throws a message naming the info string when `attachment` is present but malformed.
    init(_ info: String) throws(FenceInfoError) {
        let tokens = try Self.tokenize(info)
        guard let at = tokens.firstIndex(of: .word("attachment")), at <= 1 else {
            language = tokens.first?.text ?? ""
            attachment = nil
            return
        }
        guard at + 1 < tokens.count, case .quoted(let caption) = tokens[at + 1] else {
            throw FenceInfoError(message: "attachment needs a quoted caption: ```\(info)")
        }
        var file: String?
        for token in tokens[(at + 2)...] {
            guard case .word(let w) = token, w.hasPrefix("file=") else {
                throw FenceInfoError(message: "unexpected \(token.text) in attachment info string: ```\(info)")
            }
            file = String(w.dropFirst(5))
            if file!.isEmpty { throw FenceInfoError(message: "file= needs a path: ```\(info)") }
        }
        let lang = at == 1 ? tokens[0].text : ""
        language = lang.isEmpty ? (file.map { URL(fileURLWithPath: $0).pathExtension } ?? "") : lang
        attachment = Attachment(caption: caption, file: file)
    }

    enum Token: Equatable {
        case word(String), quoted(String)
        var text: String { switch self { case .word(let s), .quoted(let s): s } }
    }

    /// Splits on whitespace. A `"` starts a quoted string with `\"` and `\\` escapes, also right after `=`.
    static func tokenize(_ info: String) throws(FenceInfoError) -> [Token] {
        var tokens: [Token] = []
        var chars = Substring(info)
        while let c = chars.first {
            if c.isWhitespace { chars.removeFirst(); continue }
            if c == "\"" {
                tokens.append(.quoted(try quoted(&chars, info: info)))
                continue
            }
            var word = ""
            while let c = chars.first, !c.isWhitespace {
                if c == "\"" && word.hasSuffix("=") { word += try quoted(&chars, info: info); continue }
                word.append(c); chars.removeFirst()
            }
            tokens.append(.word(word))
        }
        return tokens
    }

    private static func quoted(_ chars: inout Substring, info: String) throws(FenceInfoError) -> String {
        chars.removeFirst()
        var out = ""
        while let c = chars.popFirst() {
            switch c {
            case "\"": return out
            case "\\": if let next = chars.popFirst() { out.append(next) }
            default: out.append(c)
            }
        }
        throw FenceInfoError(message: "unterminated quote in info string: ```\(info)")
    }
}

struct FenceInfoError: Error { var message: String }
