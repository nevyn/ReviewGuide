import Testing
import TSGrammarSwift
import TSGrammarC
import TSGrammarObjC
import TSGrammarCpp
import TSGrammarKotlin
import TSGrammarJava
import TSGrammarJavaScript
import TSGrammarTypeScript
import TSGrammarTSX
import TSGrammarPython
import TSGrammarRuby
import TSGrammarGo
import TSGrammarRust
import TSGrammarJSON
import TSGrammarYAML
import TSGrammarTOML
import TSGrammarBash
import TSGrammarSQL
import TSGrammarHTML
import TSGrammarCSS
import TSGrammarMarkdown
import TSGrammarMarkdownInline

@Test func everyVendoredGrammarLinks() {
    let languages: [OpaquePointer?] = [
        tree_sitter_swift(), tree_sitter_c(), tree_sitter_objc(), tree_sitter_cpp(), tree_sitter_kotlin(),
        tree_sitter_java(), tree_sitter_javascript(), tree_sitter_typescript(), tree_sitter_tsx(),
        tree_sitter_python(), tree_sitter_ruby(), tree_sitter_go(), tree_sitter_rust(), tree_sitter_json(),
        tree_sitter_yaml(), tree_sitter_toml(), tree_sitter_bash(), tree_sitter_sql(), tree_sitter_html(),
        tree_sitter_css(), tree_sitter_markdown(), tree_sitter_markdown_inline(),
    ]
    #expect(languages.count == 22)
    #expect(languages.allSatisfy { $0 != nil })
}
