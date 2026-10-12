import Foundation
import SwiftTreeSitter
import TSGrammarBash
import TSGrammarC
import TSGrammarCSS
import TSGrammarCpp
import TSGrammarGo
import TSGrammarHTML
import TSGrammarJSON
import TSGrammarJava
import TSGrammarJavaScript
import TSGrammarKotlin
import TSGrammarMarkdown
import TSGrammarMarkdownInline
import TSGrammarObjC
import TSGrammarPython
import TSGrammarRuby
import TSGrammarRust
import TSGrammarSQL
import TSGrammarSwift
import TSGrammarTOML
import TSGrammarTSX
import TSGrammarTypeScript
import TSGrammarYAML

/// A vendored tree-sitter grammar. The raw value names its query file in `Resources/queries`.
enum GrammarLanguage: String, CaseIterable, Sendable {
    case swift, c, objc, cpp, kotlin, java, javascript, typescript, tsx, python, ruby, go, rust
    case json, yaml, toml, bash, sql, html, css, markdown
    /// Only parsed inside the inline ranges of a `markdown` tree; never detected.
    case markdownInline = "markdown_inline"

    var tsLanguage: Language {
        let pointer: OpaquePointer? = switch self {
        case .swift: tree_sitter_swift()
        case .c: tree_sitter_c()
        case .objc: tree_sitter_objc()
        case .cpp: tree_sitter_cpp()
        case .kotlin: tree_sitter_kotlin()
        case .java: tree_sitter_java()
        case .javascript: tree_sitter_javascript()
        case .typescript: tree_sitter_typescript()
        case .tsx: tree_sitter_tsx()
        case .python: tree_sitter_python()
        case .ruby: tree_sitter_ruby()
        case .go: tree_sitter_go()
        case .rust: tree_sitter_rust()
        case .json: tree_sitter_json()
        case .yaml: tree_sitter_yaml()
        case .toml: tree_sitter_toml()
        case .bash: tree_sitter_bash()
        case .sql: tree_sitter_sql()
        case .html: tree_sitter_html()
        case .css: tree_sitter_css()
        case .markdown: tree_sitter_markdown()
        case .markdownInline: tree_sitter_markdown_inline()
        }
        guard let pointer else { preconditionFailure("tree_sitter_\(rawValue)() returned NULL") }
        return Language(pointer)
    }

    /// The grammar for a repo-relative path, from its extension or file name; `nil` when there is none.
    static func detect(path: String) -> GrammarLanguage? {
        let name = (path as NSString).lastPathComponent
        if let language = fileNames[name] { return language }
        let ext = (name as NSString).pathExtension.lowercased()
        return ext.isEmpty ? nil : extensions[ext]
    }

    /// The grammar named by a `#!` first line, for files without a telling extension.
    static func detect(shebang firstLine: Substring) -> GrammarLanguage? {
        guard firstLine.hasPrefix("#!") else { return nil }
        let words = firstLine.dropFirst(2).split(whereSeparator: { $0 == " " || $0 == "/" })
        // `#!/usr/bin/env -S python3 -u` names the interpreter after env and its flags.
        for word in words.reversed() where !word.hasPrefix("-") {
            if let language = interpreters.first(where: { word.hasPrefix($0.key) })?.value { return language }
        }
        return nil
    }

    /// The grammar for a Markdown info-string language (`objective-c`, `ts`, `shell`) or a file extension.
    static func named(_ name: String) -> GrammarLanguage? {
        var key = name.trimmingCharacters(in: .whitespaces).lowercased()
        if key.hasPrefix(".") { key.removeFirst() }
        return infoStrings[key] ?? extensions[key]
    }

    static let extensions: [String: GrammarLanguage] = [
        "swift": .swift,
        "c": .c,
        "h": .objc, "m": .objc, "mm": .objc,
        "cc": .cpp, "cpp": .cpp, "cxx": .cpp, "hpp": .cpp, "hh": .cpp, "hxx": .cpp,
        "kt": .kotlin, "kts": .kotlin,
        "java": .java,
        "js": .javascript, "mjs": .javascript, "cjs": .javascript, "jsx": .javascript,
        "ts": .typescript, "mts": .typescript, "cts": .typescript,
        "tsx": .tsx,
        "py": .python, "pyi": .python,
        "rb": .ruby, "podspec": .ruby, "gemspec": .ruby, "rake": .ruby,
        "go": .go,
        "rs": .rust,
        "json": .json,
        "yml": .yaml, "yaml": .yaml,
        "toml": .toml,
        "sh": .bash, "bash": .bash, "zsh": .bash,
        "sql": .sql,
        "html": .html, "htm": .html,
        "css": .css,
        "md": .markdown, "markdown": .markdown,
    ]

    static let fileNames: [String: GrammarLanguage] = [
        "Gemfile": .ruby, "Podfile": .ruby, "Fastfile": .ruby, "Rakefile": .ruby, "Appfile": .ruby,
        "Matchfile": .ruby, "Pluginfile": .ruby, "Dangerfile": .ruby, "Brewfile": .ruby,
        "Cargo.lock": .toml, "Pipfile": .toml,
    ]

    static let infoStrings: [String: GrammarLanguage] = [
        "objective-c": .objc, "objectivec": .objc, "objc": .objc, "obj-c": .objc,
        "c++": .cpp, "kotlin": .kotlin, "javascript": .javascript, "typescript": .typescript,
        "python": .python, "ruby": .ruby, "golang": .go, "rust": .rust,
        "shell": .bash, "console": .bash, "markdown": .markdown,
    ]

    private static let interpreters: [String: GrammarLanguage] = [
        "bash": .bash, "sh": .bash, "zsh": .bash, "python": .python, "ruby": .ruby, "node": .javascript,
    ]
}
