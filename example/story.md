---
title: ReviewGuide v1
meta: The Python prototype becomes a Swift command line, a Homebrew formula and a Claude Code skill
range: main...HEAD
exclude: ["Grammars/*", "Sources/Highlight/Resources/queries/*", "Tests/Fixtures/*", "Tests/RenderTests/Fixtures/*"]
---
The prototype proved one idea: a reviewer follows a change far more easily when the author's explanation sits next to the code it explains, and when the tool guarantees that the explanation covers every changed line. v1 keeps that idea and rebuilds everything around it. Stories are Markdown, coverage is checked per line, code is highlighted with tree-sitter, and a skill writes the story from what the authoring session learned.

This guide was written with the tool it describes, and writing it found two bugs and a slow build.[^dogfood]

[^dogfood]: The quadratic diff parser and the git process per blob (Chapter 3), and the anchored ranges that could not name a changed line (Chapter 5).

## Prologue · A diff is a list; a change is a story
A diff shows files in path order, which is rarely the order that a change makes sense in. A review guide puts the author's story on the left, one idea per section, and the exact diff lines that the idea is about on the right.

The guide is only trustworthy because of **coverage**: the build fails unless every changed line is placed in exactly one section. A reader who reads the story top to bottom has seen the whole change, and knows it.

The prototype was a Python script that ran Python stories. It worked well enough on a real merge request that the reviewer asked for more. Its limits were the story format (code, selected by hunk number), no syntax highlighting, and no way to carry what the author had learned into the guide.

## Chapter 1 · The contract {#contract}
Three targets share one model, defined before any of them was written: `ReviewGuideCore` reads git and stories and checks coverage, `Highlight` styles lines, and `Render` writes the page. The executable wires them together.

The seam is small. `Diff` is what git says changed. `Story` is what the author wrote. `ResolvedStory` is the two joined: each section with the code it shows. `LineStyling` is the only thing that `Render` knows about highlighting, so the renderer tests use a stub and never parse a grammar.

`StyledRun` is the one decision that shapes both highlighters and the renderer: a line's styling is a flat list of byte ranges, each with an optional syntax capture and a changed flag. Syntax and change highlighting merge into those runs before rendering, so the HTML never has to nest spans that cross each other.

```hunks
Sources/ReviewGuideCore/Diff.swift
Sources/ReviewGuideCore/Story.swift
Sources/ReviewGuideCore/Resolved.swift
Sources/ReviewGuideCore/API.swift
docs/glossary.md
docs/index.md
```

## Chapter 2 · Stories are Markdown {#stories}
A story is CommonMark with three conventions: front matter, one `##` heading per section, and a `hunks` fence that lists the section's selectors. Everything else is ordinary Markdown, so footnotes, tables, alerts and code blocks work as a writer expects.

`StoryParser` is a line scanner, not a Markdown parser. It only needs to find headings, front matter, footnote definitions and `hunks` fences, and it must ignore all of them inside other code blocks. It collects every problem with its line number rather than stopping at the first, because an author fixing a story wants the whole list.

Footnote ids are case-insensitive, because cmark matches them that way when it renders. The parser rejects `[^Note]` and `[^note]` in one story rather than letting one silently resolve to the other.

`reviewguide format` prints this specification from the installed binary, so the skill always reads the format that the installed version accepts.

```hunks
docs/story-format.md
Sources/ReviewGuideCore/StoryParser.swift
Sources/reviewguide/Resources/story-format.md
Tests/ReviewGuideCoreTests/StoryParserTests.swift
```

## Chapter 3 · Reading git {#git}
`DiffParser` reads `git diff` output. Most of it handles git's quirks: quoted paths with C escapes, the tab that git appends to paths with spaces, renames with and without content changes, binary files, mode-only changes, and `\ No newline at end of file`. It ends a hunk by counting its lines rather than by looking for the next header, so a deleted line that reads `-- x` is not mistaken for a file header.

`DiffLoader` resolves the range to two shas and diffs those, with explicit prefixes and `--no-relative`, so a user's git config cannot change what the parser sees. Exclusions use git's default pathspec matching, in which `*` crosses `/`: with `glob` magic, `*.png` would miss `Assets/icon.png`.

Writing this guide found a bug here. Listing this branch never finished: its diff includes 6.3 million lines of vendored grammar C, and the parser copied the whole open hunk for every line it appended.[^quadratic] It now mutates the hunk in place, and a test parses a 300,000-line hunk under a time limit.

[^quadratic]: `if var h = hunk { h.consume(line); hunk = h }` binds a copy that shares the `lines` buffer, so the append triggers copy-on-write of the entire array. A first fix with `if let` had the same flaw: any live binding keeps the buffer shared. Fixed in 6d37c7b4.

Writing it also showed that building was slow: 14 s for this guide, nearly all of it spent starting two git processes per blob. `BlobBatch` keeps one `git cat-file --batch` running and reads every blob through it, which takes the build to 1.6 s with identical output.

`Git` drains stderr on a dedicated thread. Draining it on `DispatchQueue.global()` hung the test suite once parallel tests had filled the cooperative pool: every test waited on a drain block that never got a thread.

```hunks
Sources/ReviewGuideCore/Git.swift
Sources/ReviewGuideCore/DiffParser.swift
Sources/ReviewGuideCore/DiffLoader.swift
Sources/ReviewGuideCore/BlobBatch.swift
Tests/ReviewGuideCoreTests/DiffParserTests.swift
Tests/ReviewGuideCoreTests/BlobBatchTests.swift
Tests/ReviewGuideCoreTests/DiffLoaderTests.swift
Tests/ReviewGuideCoreTests/TempRepo.swift
Tests/ReviewGuideCoreTests/Fixtures.swift
```

## Chapter 4 · Coverage {#coverage}
`Resolver.analyze` is the heart of the tool. It walks every selector of every section, records which section placed each changed line, and then walks the diff to find every changed line that no section placed.

Placement is keyed by path, hunk number and line index. Context lines never count: they may appear in several sections, because a reader needs them for orientation. `again` shows code without placing it, for a section that revisits code that an earlier section explained.

Every problem names its input: the section, the selector as written, and for an unplaced line its path, hunk, old and new line numbers and text. `check` prints all of them, so one run tells the author everything that is missing. A hunk with more than three changed lines and none of them placed is reported as one line, so a forgotten new file doesn't bury the rest of the list.

```hunks
Sources/ReviewGuideCore/Resolver.swift lines 1-130
Sources/ReviewGuideCore/Resolver.swift lines 168-224
Tests/ReviewGuideCoreTests/ResolverTests.swift
```

## Chapter 5 · Anchors that survive rebases {#anchors}
The prototype selected hunks by number. After a rebase, hunk 3 can be a different hunk, and the story then explains the wrong code, confidently. v1 prefers content anchors: `@ "func resync("` picks the hunks that contain the text, and `@ "from" to "to"` picks a line range.

The first version of line ranges failed on its first real use. A modified line appears twice in a diff, as the old `-` line and the new `+` line, so the anchor that an author naturally writes, the line they changed, matched two lines.

Ranges now read like the new file. Anchors match context and added lines, and fall back to deleted lines only when the text exists nowhere else, as in a pure deletion. Deleted lines travel with the line after them, so a range never splits a replacement between its old and new side.

```hunks
Sources/ReviewGuideCore/Resolver.swift lines 131-167
Tests/ReviewGuideCoreTests/AnchoredRangeTests.swift
```

> [!QUESTION]
> An anchored range cannot run to the end of a hunk, so splitting a new file into "everything from X on" still needs `lines`, as this guide does for `Resolver.swift`. Add `@ "from" to end`?

## Chapter 6 · Syntax highlighting {#syntax}
A hunk is a fragment. It can start inside a block comment or a multi-line string, and a highlighter that starts at the hunk's first line colours everything after it wrong. So `Highlight` parses whole files, the old blob for deleted lines and the new blob for the rest, and slices the result per line.

Tree-sitter grammars are vendored rather than declared as packages.[^vendoring] `scripts/vendor-grammars.sh` pins 20 languages, copies their parsers and licenses, and concatenates each language's highlight queries with the ones it inherits: TypeScript needs JavaScript's, C++ and Objective-C need C's.

[^vendoring]: Several grammar manifests test for `src/scanner.c` with a relative path that SwiftPM evaluates outside the package, which silently drops the scanner and fails the link. SwiftPM also mirror-clones each grammar's full history: 1.3 GB and 24 minutes for a first build.

Captures nest and overlap, so `SyntaxStyler` flattens them: each character takes the capture of the innermost node. `CaptureNames` maps every grammar's vocabulary onto the theme's; `variable` takes part in flattening but renders unstyled, so an identifier inside a string interpolation is not coloured as a string.

Highlighting never fails the build. A file without a grammar, over 1 MB or not UTF-8 renders plain, and an unexpected failure is a warning on stderr that names the blob.

```hunks
docs/architecture.md
docs/grammars.md
scripts/vendor-grammars.sh
Sources/Highlight/GrammarLanguage.swift
Sources/Highlight/SyntaxStyler.swift
Sources/Highlight/CaptureNames.swift
Sources/Highlight/Highlighter.swift
Tests/HighlightTests/GrammarLinkTests.swift
Tests/HighlightTests/SyntaxTests.swift
Tests/HighlightTests/HunkTests.swift
Tests/HighlightTests/Support.swift
Tests/HighlightTests/ContractTests.swift
```

## Chapter 7 · What changed within a line {#change}
Line colours say that a line changed; change highlighting says what in it changed. `ChangeStyler` finds each replacement, a run of deleted lines directly followed by added lines, and pairs those lines in order by similarity. A pair diffs at token level: `count` → `code` marks one word, not the characters `unt` → `de`.

Similarity ignores whitespace tokens, so `a = b + c` → `x = y - z` scores 0.2 and does not pair, and a rewritten line keeps plain line colouring instead of a confetti of marks.

```hunks
Sources/Highlight/ChangeStyler.swift
Tests/HighlightTests/ChangeTests.swift
```

## Chapter 8 · The page {#page}
The page keeps the prototype's layout: the story sticky on the left, code on the right, stacked below 900 px, light and dark from the system. It is one self-contained file with no external assets, so it works offline and as an attachment.

Markdown goes through cmark-gfm's C API.[^cmark] Footnotes are numbered across the whole guide, and each section lists the notes that it references. Alerts become callouts; `[!QUESTION]` marks what the author has not settled. Attachments render folded, highlighted like code.

[^cmark]: Apple's swift-markdown has no footnote support. cmark-gfm does, but `cmark_node_get_type_string` names footnote nodes `<unknown>`, so the code compares node types against the constants.

Each section has a "reviewed" checkbox, stored per head sha in `localStorage`, so a long guide survives a closed tab. The Markdown export is for readers who won't open an HTML file.

```hunks
Sources/Render/HTMLRenderer.swift
Sources/Render/Resources/template.html
Sources/Render/StyledHTML.swift
Sources/Render/Prose.swift
Sources/Render/CMark.swift
Sources/Render/FenceInfo.swift
Sources/Render/MarkdownRenderer.swift
Tests/RenderTests/PageTests.swift
Tests/RenderTests/ProseTests.swift
Tests/RenderTests/StyledHTMLTests.swift
Tests/RenderTests/MarkdownExportTests.swift
Tests/RenderTests/SampleTests.swift
Tests/RenderTests/Support.swift
```

## Chapter 9 · The command line {#cli}
`list`, `check`, `build`, `upload`, `paths` and `format`. Exit 1 means the story does not satisfy the diff; exit 2 means anything else went wrong, with a message that names the input.

Stories and guides live in the repository's common git directory, `.git/review-guides/<branch>.md`. Every worktree of a clone sees the same story, a worktree's deletion doesn't take the story with it, and `git status` never shows it, so a guide that embeds code cannot be committed by accident.

`ResourceBundle` exists because of Homebrew. Homebrew links `bin/reviewguide` to the real file in `libexec`, and `Bundle.module` looks for resource bundles beside the link instead of the file. `ResourceBundle` resolves the link first.

The upload command is the author's, configured once: `upload = upload {file}`. The tool runs it, takes the last URL that it prints, and hands that back. Publishing the URL on a PR or MR is the caller's business.

```hunks
docs/cli.md
Sources/reviewguide/ReviewGuideCommand.swift
Sources/reviewguide/Commands.swift
Sources/reviewguide/ListJSON.swift
Sources/reviewguide/Version.swift
Sources/ReviewGuideCore/GuidePaths.swift
Sources/ReviewGuideCore/ResourceBundle.swift
Sources/ReviewGuideCore/Config.swift
Sources/ReviewGuideCore/Uploader.swift
Tests/ReviewGuideCoreTests/CLITests.swift
Tests/ReviewGuideCoreTests/PathsConfigUploadTests.swift
```

## Chapter 10 · The skill {#skill}
The guide's value is what the authoring session knows and the diff doesn't show: why the change exists, the evidence, the approaches that failed. Only that session has it, so the skill runs there, at the end of the work.

The skill also makes writing the guide a review. Every claim gets checked against the code, and every doubt ends as either a reported bug or an open question in the guide, never as confident prose. That is how this guide found its bugs.

The repository is its own plugin marketplace, like Rivulets.

```hunks
plugin/skills/review-guide/SKILL.md
plugin/.claude-plugin/plugin.json
.claude-plugin/marketplace.json
```

## Chapter 11 · Shipping {#shipping}
A `v*` tag does everything, the way riv releases: CI stamps the version, tests, builds a universal binary, publishes the release with notes from the commits since the previous tag, and points `Formula/reviewguide.rb` in the shared tap at it. `scripts/release.sh redo` re-tags the same version when a release needs another attempt.

The formula installs the binary and its resource bundles into `libexec` and links the binary into `bin`, which is the layout `ResourceBundle` resolves.

```hunks
Package.swift
Package.resolved
.github/workflows/release.yml
.github/workflows/check.yml
packaging/homebrew/reviewguide.rb
packaging/homebrew/README.md
scripts/release.sh
LICENSE
.gitignore
```

> [!QUESTION]
> The universal binary is 81 MB; grammar parse tables are about 37 MB of each architecture. And the vendored grammars add 195 MB to the repository. Ship arm64 only, and drop grammars nobody here reviews?

## Epilogue · The prototype retires {#retire}
The Python engine, its template and its Python story go. This story replaces the example; it covers the change that it ships in.

```hunks
reviewguide.py
template.html
example/story.py
example/story.md
README.md
```

# Appendix

## The research behind the dependencies {#research}
- **Bindings**: tree-sitter/swift-tree-sitter 0.10.0, pinned exactly. A stray older tag, 0.25.0, sorts above it and would resolve to older code under `from:`. The C runtime package dropped its `Package.swift` in v0.27.
- **Grammars**: all 20 languages build into one binary with the 0.25 runtime and no ABI mismatch. SQL's parser exists only on its `gh-pages` branch, and Kotlin's only maintained fork with queries is fwcd's.
- **Markdown**: swift-cmark 0.9.0, the `cmark-gfm` products, through the C API.
- **Bundles**: SwiftPM puts each target's resources in a bundle beside the executable. A probe confirmed that a binary reached through a symlink finds none of them, which is how Homebrew installs.

## Dead ends {#dead-ends}
- **Hunk numbers as the main selector** break silently after a rebase. Kept as a fallback; anchors are the default.
- **Grammar packages as dependencies**: dropped scanners and 1.3 GB of clones. Vendored instead.
- **`:(exclude,glob)` pathspecs**: `*` stops at `/`, so the documented `*.png` example matched nothing in subdirectories.
- **Writing the Markdown export to `<branch>.md`**: that is the story's own path. The export is `<branch>.guide.md`, and `build` refuses to overwrite the story.
- **Draining pipes on `DispatchQueue.global()`**: starved the cooperative pool and hung the tests.
