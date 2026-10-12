import Foundation
import Testing
import StoryGrafterCore
@testable import Highlight

struct LanguageSample: CustomTestStringConvertible, Sendable {
    var language: String
    var source: String
    var token: String
    var capture: String
    var testDescription: String { language }
}

/// One snippet per grammar: proves that the grammar links, its query (with inherited parts) compiles, and capture
/// names normalise.
let languageSamples: [LanguageSample] = [
    .init(language: "swift", source: "let x = 1", token: "let", capture: "keyword"),
    .init(language: "objc", source: "- (void)f { return; }", token: "return", capture: "keyword"),
    .init(language: "objc", source: "int f(void) { return 0; }", token: "0", capture: "number"),
    .init(language: "c", source: "int main(void) { return 0; }", token: "return", capture: "keyword"),
    .init(language: "cpp", source: "class A { public: int x; };", token: "class", capture: "keyword"),
    .init(language: "kotlin", source: "fun main() { val x = 1 }", token: "val", capture: "keyword"),
    .init(language: "java", source: "class A { int x = 1; }", token: "class", capture: "keyword"),
    .init(language: "ts", source: "const a: number = 1;", token: "number", capture: "type.builtin"),
    .init(language: "ts", source: "const a: number = 1;", token: "const", capture: "keyword"),
    .init(language: "tsx", source: "const a = <div className=\"x\"/>;", token: "div", capture: "tag"),
    .init(language: "tsx", source: "let a: string = \"\";", token: "string", capture: "type.builtin"),
    .init(language: "js", source: "const a = <div/>;", token: "div", capture: "tag"),
    .init(language: "python", source: "def f(): return 1", token: "def", capture: "keyword"),
    .init(language: "ruby", source: "def f; 1; end", token: "end", capture: "keyword"),
    .init(language: "go", source: "package main\nfunc f() {}", token: "func", capture: "keyword"),
    .init(language: "rust", source: "fn f() {}", token: "fn", capture: "keyword"),
    .init(language: "json", source: "{\"a\": 1}", token: "\"a\"", capture: "string"),
    .init(language: "yaml", source: "a: 'x'", token: "'x'", capture: "string"),
    .init(language: "toml", source: "a = \"x\"", token: "\"x\"", capture: "string"),
    .init(language: "shell", source: "if true; then echo; fi", token: "then", capture: "keyword"),
    .init(language: "sql", source: "SELECT a FROM t;", token: "SELECT", capture: "keyword"),
    .init(language: "html", source: "<p class=\"x\">hi</p>", token: "p", capture: "tag"),
    .init(language: "css", source: "a { color: red; }", token: "color", capture: "property"),
    .init(language: "markdown", source: "# Title\n", token: "Title", capture: "type"),
    .init(language: "markdown", source: "Some `code` here\n", token: "code", capture: "string"),
]

@Test(arguments: languageSamples)
func everyLanguageStyles(_ sample: LanguageSample) {
    #expect(capture(of: sample.token, in: sample.source, language: sample.language) == sample.capture)
}

@Test func everyQueryLoadsFromTheBundle() throws {
    for language in GrammarLanguage.allCases {
        #expect(try SyntaxStyler.query(for: language).patternCount > 0, "\(language.rawValue)")
    }
}

@Test func unknownLanguageIsUnstyled() {
    let lines = Highlighter(diff: emptyDiff, readBlob: { _, _ in nil }).styles(source: "let x = 1\n", language: "brainfuck")
    #expect(lines == [[StyledRun(bytes: 0..<9)], []])
}

@Test func runsCoverEveryByteInOrder() {
    let source = "let s = \"åäö 😀\" // ünïcode\n\tfunc g() {}"
    let lines = Highlighter(diff: emptyDiff, readBlob: { _, _ in nil }).styles(source: source, language: "swift")
    for (text, runs) in zip(source.split(separator: "\n", omittingEmptySubsequences: false), lines) {
        var end = 0
        for run in runs {
            #expect(run.bytes.lowerBound == end)
            end = run.bytes.upperBound
            #expect(String(bytes: Array(text.utf8)[run.bytes], encoding: .utf8) != nil, "run splits a scalar")
        }
        #expect(end == text.utf8.count)
    }
    #expect(capture(of: "😀", in: source, lines: lines) == "string")
    #expect(capture(of: "ünïcode", in: source, lines: lines) == "comment")
}

@Test func innermostCaptureWins() {
    let source = "let s = \"a\\(b)c\""
    let lines = Highlighter(diff: emptyDiff, readBlob: { _, _ in nil }).styles(source: source, language: "swift")
    #expect(capture(of: "a", in: source, lines: lines) == "string")
    #expect(capture(of: "\\(", in: source, lines: lines) == "punctuation.special")
    #expect(capture(of: "b", in: source, lines: lines) == nil, "the interpolated identifier is a variable, inside the string")
}

@Test func flatteningPrefersShorterThenLaterPatterns() {
    typealias C = SyntaxStyler.Capture
    let captures = [
        C(range: NSRange(location: 0, length: 6), pattern: 5, style: "string"),
        C(range: NSRange(location: 2, length: 2), pattern: 1, style: "escape"),
        C(range: NSRange(location: 4, length: 2), pattern: 3, style: "type"),
        C(range: NSRange(location: 4, length: 2), pattern: 2, style: "constant"),
    ]
    let flat = SyntaxStyler.flatten(captures, utf16Count: 6)
    #expect(flat.winners.map { $0 < 0 ? nil : flat.styles[Int($0)] } == ["string", "string", "escape", "escape", "type", "type"])
}

@Test func oversizedSourceIsUnstyled() {
    let source = String(repeating: "let x = 1\n", count: SyntaxStyler.maxBytes / 10 + 1)
    let lines = Highlighter(diff: emptyDiff, readBlob: { _, _ in nil }).styles(source: source, language: "swift")
    #expect(lines.first == [StyledRun(bytes: 0..<9)])
}

@Test(arguments: [
    ("Sources/App/Model.swift", GrammarLanguage.swift), ("Package.swift", .swift), ("ios/Podfile", .ruby),
    ("fastlane/Fastfile", .ruby), ("X.podspec", .ruby), ("A.h", .objc), ("A.mm", .objc), ("a.hpp", .cpp),
    ("b.kts", .kotlin), ("c.tsx", .tsx), ("d.cjs", .javascript), ("e.jsx", .javascript), ("f.YML", .yaml),
    ("g.zsh", .bash), ("README.md", .markdown), ("x.htm", .html),
])
func detectsLanguageFromPath(_ path: String, _ language: GrammarLanguage) {
    #expect(GrammarLanguage.detect(path: path) == language)
}

@Test func detectsLanguageFromShebangAndInfoString() {
    #expect(GrammarLanguage.detect(path: "scripts/release") == nil)
    #expect(GrammarLanguage.detect(shebang: "#!/bin/sh") == .bash)
    #expect(GrammarLanguage.detect(shebang: "#!/usr/bin/env bash") == .bash)
    #expect(GrammarLanguage.detect(shebang: "#!/usr/bin/env -S python3 -u") == .python)
    #expect(GrammarLanguage.detect(shebang: "# not a shebang") == nil)
    #expect(GrammarLanguage.named("objective-c") == .objc)
    #expect(GrammarLanguage.named("Shell") == .bash)
    #expect(GrammarLanguage.named(".kt") == .kotlin)
    #expect(GrammarLanguage.named("ts") == .typescript)
}

@Test(arguments: [
    ("keyword", CaptureNames.Normalised.style("keyword")),
    ("keyword.return", .style("keyword.return")),
    ("text.title", .style("type")),
    ("text.uri", .style("string.special")),
    ("boolean", .style("constant.builtin")),
    ("float", .style("number")),
    ("include", .style("keyword")),
    ("conditional", .style("keyword")),
    ("repeat", .style("keyword")),
    ("namespace", .style("module")),
    ("field", .style("property")),
    ("parameter", .style("variable.parameter")),
    ("method", .style("function.method")),
    ("method.call", .style("function.method")),
    ("character", .style("string")),
    ("delimiter", .style("punctuation")),
    ("punctuation.bracket", .style("punctuation.bracket")),
    ("variable.parameter", .style("variable.parameter")),
    ("variable", .plain),
    ("variable.other", .plain),
    ("none", .plain),
    ("spell", .ignore),
    ("_name", .ignore),
    ("text.emphasis", .ignore),
])
func normalisesCaptureNames(_ raw: String, _ expected: CaptureNames.Normalised) {
    #expect(CaptureNames.normalise(raw) == expected)
}
