/// Maps the capture names that grammars' highlight queries use onto the renderer's theme vocabulary.
enum CaptureNames {
    /// What a raw capture does when its runs are flattened.
    enum Normalised: Equatable {
        /// Styles its bytes with this theme name, e.g. `keyword.return`.
        case style(String)
        /// Takes part in flattening, so it hides enclosing captures, but renders unstyled.
        case plain
        /// Takes no part: as if the query never captured it.
        case ignore
    }

    /// Theme names. A capture keeps any suffix after one of these: `keyword.return` stays `keyword.return`.
    static let themeNames: Set<String> = [
        "keyword", "string", "string.special", "comment", "number", "constant", "constant.builtin",
        "type", "type.builtin", "function", "function.method", "function.builtin", "variable.builtin",
        "variable.parameter", "property", "attribute", "operator", "punctuation", "tag", "label", "escape",
        "constructor", "module", "embedded",
    ]

    /// Names that grammars use for a theme name; the longest matching prefix is replaced and the rest kept.
    static let aliases: [String: String] = [
        "text.title": "type",
        "text.literal": "string",
        "text.uri": "string.special",
        "text.reference": "label",
        "boolean": "constant.builtin",
        "float": "number",
        "include": "keyword",
        "import": "keyword",
        "conditional": "keyword",
        "repeat": "keyword",
        "exception": "keyword",
        "storageclass": "keyword",
        "preproc": "keyword",
        "type.qualifier": "keyword",
        "namespace": "module",
        "field": "property",
        "variable.member": "property",
        "parameter": "variable.parameter",
        "parameter.builtin": "variable.builtin",
        "method": "function.method",
        "method.call": "function.method",
        "function.call": "function",
        "character": "string",
        "character.special": "string.special",
        "delimiter": "punctuation",
    ]

    /// Captures that only exist to blank out an enclosing capture.
    static let plainNames: Set<String> = ["variable", "none"]

    static func normalise(_ raw: String) -> Normalised {
        let parts = raw.split(separator: ".").map(String.init)
        guard let head = parts.first, !head.hasPrefix("_") else { return .ignore }
        for length in stride(from: parts.count, through: 1, by: -1) {
            let prefix = parts[..<length].joined(separator: ".")
            let rest = parts[length...]
            if let alias = aliases[prefix] { return .style(([alias] + rest).joined(separator: ".")) }
            if plainNames.contains(prefix) { return .plain }
            if themeNames.contains(prefix) { return .style(raw) }
        }
        return .ignore
    }
}
