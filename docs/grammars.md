# Grammars

`Highlight` styles code with tree-sitter grammars that are vendored into `Grammars/`, one C target each, and highlight queries that are vendored into `Sources/Highlight/Resources/queries/`. Nothing is fetched at build time.

## Languages

| Language | Detected from |
|---|---|
| Swift | `.swift` |
| Objective-C | `.h`, `.m`, `.mm` |
| C | `.c` |
| C++ | `.cc`, `.cpp`, `.cxx`, `.hpp`, `.hh`, `.hxx` |
| Kotlin | `.kt`, `.kts` |
| Java | `.java` |
| JavaScript (with JSX) | `.js`, `.mjs`, `.cjs`, `.jsx`; `node` shebang |
| TypeScript | `.ts`, `.mts`, `.cts` |
| TSX | `.tsx` |
| Python | `.py`, `.pyi`; `python` shebang |
| Ruby | `.rb`, `.rake`, `.gemspec`, `.podspec`, `Gemfile`, `Podfile`, `Fastfile`, `Rakefile` and other fastlane and Bundler files; `ruby` shebang |
| Go | `.go` |
| Rust | `.rs` |
| JSON | `.json` |
| YAML | `.yml`, `.yaml` |
| TOML | `.toml`, `Cargo.lock`, `Pipfile` |
| Bash | `.sh`, `.bash`, `.zsh`; `sh`, `bash` and `zsh` shebangs |
| SQL | `.sql` |
| HTML | `.html`, `.htm` |
| CSS | `.css` |
| Markdown | `.md`, `.markdown` |

Attachments and other snippets name their language with a Markdown info string (`swift`, `objective-c`, `ts`, `shell`, …) or an extension. The tables are in `Sources/Highlight/GrammarLanguage.swift`.

## Pins and the vendoring script

`scripts/vendor-grammars.sh` holds the pin table: for each grammar, its repository, the tag or commit, the grammar's directory in the repository, and the query files to concatenate. For each grammar it fetches the ref shallowly, copies `parser.c`, `scanner.c`, local headers, YAML's `schema.*.c` includes and the `tree_sitter/` headers into `Grammars/<dir>/src/`, copies the `LICENSE`, writes `include/tree_sitter_<name>.h`, and writes the concatenated queries to `queries/<name>.scm`. `Grammars/PINS` records each ref and the commit it resolved to.

Some queries build on another language's: TypeScript on JavaScript's, TSX on JavaScript's, JSX's and TypeScript's, C++ and Objective-C on C's. The script concatenates the parts base first, each under a comment that names its repository, ref and file, so that the derived language's patterns win.

Re-running the script with unchanged pins changes nothing.

### Bump a pin

1. Change the ref in the script's table.
2. Run `scripts/vendor-grammars.sh`.
3. Check `git status`: the script does not delete files that the new ref no longer has.
4. Run `swift test`. `everyLanguageStyles` and `everyQueryLoadsFromTheBundle` catch a query that no longer compiles against the grammar, and capture names that the normalisation table does not know.

Check the generated `parser.c` against the tree-sitter runtime that `swift-tree-sitter` pulls in: the grammar's ABI version must be one that the runtime supports.

### Add a language

1. Add a row to the script's table and run it.
2. Add the target to the `grammars` list in `Package.swift`.
3. Add a case to `GrammarLanguage`, with its `tree_sitter_<name>()` and its extensions or info strings.
4. Add a sample to `languageSamples` in `Tests/HighlightTests/SyntaxTests.swift`.

## Capture names

Grammars name their captures differently: one says `@keyword.conditional`, another `@conditional`, Markdown's `@text.title`. `CaptureNames` in `Sources/Highlight/CaptureNames.swift` maps them onto the theme names that the renderer styles (`keyword`, `string`, `type`, …). A name that extends a theme name keeps its suffix (`keyword.return`), and the renderer classes both. Aliases replace the longest matching prefix. `variable` and `none` render unstyled; anything else unknown is ignored. A new grammar's queries may need new aliases there.

The bindings do not evaluate `#has-ancestor?`; `SyntaxStyler` does. A pattern with any other predicate that neither evaluates never matches, rather than matching everything.
