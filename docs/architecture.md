# Architecture

One SwiftPM package. The `storygrafter` executable and its resource bundle are the whole install; Homebrew puts both in `libexec` and links the executable into `bin`.

| Target | Owns |
|---|---|
| `StoryGrafterCore` | The diff model, running git, parsing `git diff`, the story model and parser, resolving selectors, coverage, configuration and upload. No rendering. |
| `Highlight` | Syntax highlighting with tree-sitter and change highlighting within lines. Produces styled runs per line. |
| `Render` | The HTML page and the Markdown export, from a resolved story plus styled lines. Owns the page template and CSS. |
| `storygrafter` | The command line. Wires the three together. |

## Pipeline

1. `StoryGrafterCore` runs `git diff --find-renames --no-color --no-ext-diff <range> -- . <exclusions>` and parses it into `DiffFile`s.
2. It parses the story into `Story`, resolves each selector to `Placement`s, and checks coverage.
3. `Highlight` styles every line that a section shows (see below).
4. `Render` lays out the sections and writes one self-contained file.

## Syntax highlighting

A hunk is a fragment: it can start inside a block comment or a multi-line string, and a lexer that starts at the hunk's first line colours everything after it wrong. So `Highlight` lexes whole files and then slices:

1. Read the old blob (`<base>:<oldPath ?? path>`) and the new blob (`<head>:<path>`) once per file, on first use. Added files have no old side, deleted files no new side.
2. Pick the grammar from the path's extension or file name, else from a `#!` first line. Parse the blob and run the language's highlight query. Markdown runs the inline grammar over the block tree's `inline` and table-cell ranges and adds its captures.
3. Flatten the captures, which nest and overlap: each character takes the capture of the innermost node, and on equal ranges the later pattern in the query wins. Capture names are normalised to the renderer's theme vocabulary (docs/grammars.md); `variable` and `none` take part but render unstyled, so an identifier inside a string interpolation is not coloured as string.
4. Split into UTF-8 runs per line.
5. A deleted line takes its styling from the old file at its old line number. Added and context lines take it from the new file. A line whose text differs from its blob line gets no syntax.

A language without a grammar, a blob over 1 MB or not UTF-8, and a parse over 2 s render unstyled. Highlighting never fails the build; unexpected failures (a git error, a timeout, a query that does not compile) are warned about on stderr. The grammars and queries are vendored: docs/grammars.md.

## Change highlighting

Within each hunk, every run of deleted lines directly followed by a run of added lines is a replacement.

1. Tokenize each line into words (letters, digits, `_`, combining marks), whitespace runs and single other characters.
2. Pair the deleted and added lines in order: each deleted line takes the best-scoring added line among the next 16 after the previous pair, so pairs never cross. The score is 2 × matching tokens / total tokens, counting non-whitespace tokens only; a pair needs 0.5. Unpaired lines keep plain line colouring.
3. Diff each pair's token sequences with `CollectionDifference`. Tokens that differ, whitespace included, are marked changed.

## Styled runs

`Highlight` returns, per shown line, a list of non-overlapping runs that cover the line: a UTF-8 byte range, an optional highlight capture name (`keyword`, `string.special`, …), and a changed flag. `Render` turns each run into one `<span>` whose classes are the capture name's components plus `chg`. Because the two layers are merged into flat runs before rendering, spans never nest.
