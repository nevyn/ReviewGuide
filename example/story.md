---
title: ReviewGuide v1 in Swift
meta: The core: diff, story, coverage and the command line
range: main...HEAD
exclude: ["Tests/Fixtures/*"]
---
ReviewGuide moves from a Python script with Python stories to a Swift command line with Markdown stories. This guide covers the contract between the three targets and the core: reading `git diff`, parsing stories, checking coverage, and the commands.

## Prologue · The contract {#contract}
The docs fix the story format, the command line and the vocabulary before any code. The shared model types are the contract between the core, highlighting and rendering, so that the three can be built in parallel.

```hunks
docs/glossary.md
docs/story-format.md
docs/cli.md
docs/architecture.md
Diff.swift
Story.swift
Resolved.swift
API.swift
Highlighter.swift
Renderers.swift
HighlightTests/ContractTests.swift
RenderTests/ContractTests.swift
Package.swift
Package.resolved
.gitignore
```

## Chapter 1 · Reading git diff {#diff}
`git diff` is parsed by counting each hunk's lines rather than by looking for `---` and `+++`, because a deleted line that starts with `--` prints as `---`.[^dashes] Paths come from `rename from`/`to` and the `---`/`+++` lines, unquoted from git's C escapes; the `diff --git` line is only a fallback, for binary and mode-only files whose two paths are the same.

The loader resolves the range to two shas and passes flags that override any user configuration that would change the output: prefixes, relative paths, external diff drivers.

```hunks
Git.swift
DiffParser.swift
DiffLoader.swift
DiffParserTests.swift
DiffLoaderTests.swift
TempRepo.swift
Fixtures.swift
```

[^dashes]: An SQL comment `-- note` that is deleted shows up as `--- note`.

## Chapter 2 · Stories {#story}
The parser tracks fenced code blocks, so that a story can quote Markdown, headings and `hunks` fences included, without them taking effect. It collects every problem with its line number before failing.

```hunks
StoryParser.swift
StoryParserTests.swift
story-format.md @ "## Selectors" to "Quoted strings" again
```

## Chapter 3 · Coverage {#coverage}
Each selector resolves to hunks or a line range within one hunk, and each changed line it picks is placed in its section. `analyze` returns the placements even when coverage fails, which is what `list` shows while a story is being written.

```hunks
Resolver.swift
ResolverTests.swift
```

## Chapter 4 · Paths, configuration and upload {#paths}
Stories live in the common git directory, which every worktree shares and `git status` never shows. The Markdown export is named `.guide.md`, so that building it never overwrites a story.

```hunks
GuidePaths.swift
Config.swift
Uploader.swift
PathsConfigUploadTests.swift
```

## Chapter 5 · The command line {#cli}
Every command maps its errors to the exit status in the CLI doc: story problems exit 1, one per line; anything that names a bad input exits 2.

```hunks
Sources/reviewguide/ReviewGuideCommand.swift
Sources/reviewguide/Commands.swift
Sources/reviewguide/ListJSON.swift
CLITests.swift
```

## Epilogue · Retiring the Python engine {#retire}
The Python engine, its template and its Python story are gone. This story replaces the example.

```hunks
reviewguide.py
template.html
example/story.py
example/story.md
README.md
docs/index.md
```

# Appendix

## Test fixtures
The diff fixtures are `git diff` output from throwaway repositories with fabricated files, one per quirk of git's format. They are excluded from this guide.
