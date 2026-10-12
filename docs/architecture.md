# Architecture

One SwiftPM package. The `reviewguide` executable and its resource bundle are the whole install; Homebrew puts both in `libexec` and links the executable into `bin`.

| Target | Owns |
|---|---|
| `ReviewGuideCore` | The diff model, running git, parsing `git diff`, the story model and parser, resolving selectors, coverage, configuration and upload. No rendering. |
| `Highlight` | Syntax highlighting with tree-sitter and change highlighting within lines. Produces styled runs per line. |
| `Render` | The HTML page and the Markdown export, from a resolved story plus styled lines. Owns the page template and CSS. |
| `reviewguide` | The command line. Wires the three together. |

## Pipeline

1. `ReviewGuideCore` runs `git diff --find-renames --no-color --no-ext-diff <range> -- . <exclusions>` and parses it into `DiffFile`s.
2. It parses the story into `Story`, resolves each selector to `Placement`s, and checks coverage.
3. `Highlight` styles every line that a section shows (see below).
4. `Render` lays out the sections and writes one self-contained file.

## Syntax highlighting

A hunk is a fragment: it can start inside a block comment or a multi-line string, and a lexer that starts at the hunk's first line colours everything after it wrong. So `Highlight` lexes whole files and then slices:

1. Fetch the old blob (`git show <base>:<oldPath>`) and the new blob (`git show <head>:<path>`) once per file.
2. Parse each with the file's tree-sitter grammar and run the grammar's highlight query. Captures become runs with UTF-8 byte ranges.
3. Split the runs at line breaks into one list per line.
4. A deleted line takes its styling from the old file at its old line number. Added and context lines take it from the new file.

A language without a grammar, or a file that does not parse, renders unstyled. Highlighting never fails the build.

## Change highlighting

Within each hunk, every run of deleted lines followed by a run of added lines is a replacement.

1. Pair the deleted and added lines of a replacement by similarity, in order. A pair below the similarity threshold stays unpaired and keeps plain line colouring.
2. For each pair, tokenize both lines into words, whitespace runs and single punctuation characters, and diff the token sequences.
3. Tokens that differ are marked changed.

## Styled runs

`Highlight` returns, per shown line, a list of non-overlapping runs that cover the line: a UTF-8 byte range, an optional highlight capture name (`keyword`, `string.special`, …), and a changed flag. `Render` turns each run into one `<span>` whose classes are the capture name's components plus `chg`. Because the two layers are merged into flat runs before rendering, spans never nest.
