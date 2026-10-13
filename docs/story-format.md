# Story format

A story is a CommonMark document with GitHub extensions (tables, strikethrough, autolinks, footnotes, alerts) plus three conventions: front matter, `##` sections, and a `hunks` fence per section. Raw HTML is passed through; the story is the author's own text.

````markdown
---
title: Station clock drift fix
meta: GL-1234 · iOS 9.12
range: origin/main...HEAD
head: 4af1844a
exclude: ["*.png", "*.pbxproj"]
---
Two sentences that summarise the change. Rendered in the page header.

## Prologue · The bug in one example
Prose. A claim with a source.[^crash]

[^crash]: 412 crashes in 9.11, all in `Station.resync()`.

## Chapter 1 · The new primitive {#primitive}
Prose, with a marker on the line it explains {@ "let skew"}.

```hunks
Sources/Clock/Drift.swift
Station.swift @ "func resync("
Station.swift #3 lines 1-12
Station.swift @ "let skew" to "}"
Station.swift @ "func drift(" to end
Sources/Clock/Station.swift #1 again
```

> [!QUESTION]
> Should a skew above 5 s also log?

# Appendix

## Backend payload
```json attachment "GET /stations, anonymised"
{"id": 1, "skew_ms": 5200}
```
````

## Front matter

A `---` block at the very top. One `key: value` per line; a value is a bare string, a double-quoted string, or a flow list of double-quoted strings. No other YAML.

| Key | Required | Meaning |
|---|---|---|
| `title` | yes | The page heading. |
| `meta` | no | One line under the heading. |
| `range` | no | The git diff range. `--range` overrides it; the default is `<origin's default branch>...HEAD`. |
| `head` | no | The HEAD sha that the story was written against. When it differs from the built HEAD, the build warns on stderr and gives the value to set once the story is up to date. |
| `exclude` | no | Pathspec globs to leave out of the diff. The guide lists each glob and the files it removed. |

Text between the front matter and the first heading is the summary.

## Sections

Every `##` heading starts a section, which runs to the next `##` or `#`.

- `## Kicker · Title`: the text before ` · ` (space, U+00B7, space) is the kicker. Without ` · ` the section has no kicker.
- A trailing `{#id}` sets the section's anchor id. The default id is the title slug; duplicate ids are an error.
- A section has at most one `hunks` fence. The fence may appear anywhere in the section and is removed from the prose. A section without one renders without a code column.

`# Appendix` (exactly that text) starts the appendix. Every `##` after it is an appendix section: full width, and a `hunks` fence there is an error. Any other `#` heading is an error.

## Selectors

One selector per line in a `hunks` fence. `#` starts a comment. Blank lines are ignored.

```
<path> [<hunks>] [<lines>] [again]
```

**Path.** A repo-relative path, or a suffix of one that starts after a `/` (`Station.swift` matches `Sources/Clock/Station.swift`). It must match exactly one file in the diff. Quote paths that contain spaces: `"My File.swift"`. Renamed files match on their new path.

**Hunks**, at most one of:

| Form | Picks |
|---|---|
| (none) | Every hunk of the file, or the file change for a file without hunks. |
| `#3`, `#2-4`, `#1,3,5` | Hunks by 1-based number, as `storygrafter list` prints them. |
| `@ "text"` | Every hunk where some line (changed or context) contains `text`. Matching nothing is an error. |

**Lines**, only when the hunks part resolves to exactly one hunk:

| Form | Picks |
|---|---|
| `lines 5-12` | Lines 5 through 12 of the hunk body, 1-based, context lines included. |
| `@ "from" to "to"` | From the line containing `from` through the first line at or after it, in the same hunk, that contains `to`. Replaces the hunks part: `from` must be on exactly one line of the file. |
| `@ "from" to end` | From the line containing `from` through the end of its hunk. |
| `@ "from" until "text"` | From the line containing `from` up to, not including, the next line that contains `text`, and the deletions directly before that line. For a range that ends where the next function begins. |

An anchored range reads like the new file: `from` and `to` match context and added lines, and match deleted lines only when no such line contains the text. Deleted lines travel with the line after them (with the line before them when they end the hunk), so a range never splits a replacement between its old and new side.

**`again`** shows the code without placing it, for a section that revisits code that an earlier section already placed.

Quoted strings use `\"` and `\\` as escapes.

## Coverage

The build places every changed line and file change that the selectors pick. It fails, listing every problem rather than the first, when:

- a changed line or file change is not placed,
- a changed line or file change is placed twice without `again`,
- a selector matches no file, several files, or no hunk,
- a `lines` or `to` range falls outside its hunk.

Context lines may appear in several sections without `again`. Blank changed lines (empty or whitespace only) are shown wherever a range includes them but need no placement, because no anchor can name one.

## Markers

A marker points from a sentence to one exact place in the section's code: `{@ "text"}`, or `{@ path "text"}` to name the file. The page shows the same numbered, coloured circle in the prose and just before the text in the code, and underlines the text in the circle's colour. Hovering either circle lights up both, and clicking one scrolls to the other.

```markdown
The sweep now reads the relationships once {@ "let relationships ="}, not once per entity {@ "[Relationships.self][eid]"}.
```

- Markers number themselves 1, 2, 3 in reading order within each section.
- The text must occur exactly once in the code that the section shows. Like anchors, it matches context and added lines, and deleted lines only when the text is nowhere else. `check` reports a marker that matches nothing or several places; a path, or more of the text, narrows it.
- The path is a repo-relative path or a suffix of one, as in selectors. Quote the text with `\"` and `\\` as escapes.
- Markers belong in section prose. Markers in the summary, the appendix or a footnote are errors, because those have no code.
- Markers inside code spans and code blocks are text, not markers.

**Code links** need no markup. An inline code span, such as `` `sweepOrphans` ``, whose text occurs exactly once in the section's code links to it the same way, with a dotted underline and no number. A span ending in `()` also matches the name followed by `(`. Spans of fewer than three characters, and spans that match several places, stay plain.

## Supplementary reading

- **Footnotes**: GFM `[^id]` references and `[^id]: text` definitions. The definition may sit anywhere in the story. Ids are case-insensitive, as in CommonMark.
- **Alerts**: `> [!NOTE]`, `> [!WARNING]` and `> [!QUESTION]`. `[!QUESTION]` marks something the author has not settled.
- **Attachments**: a fenced block whose info string is `<language> attachment "<caption>"` embeds its content folded and highlighted. `attachment "<caption>" file=<path>` embeds a file instead, with `<path>` relative to the story file and the language taken from its extension. A caption cannot contain `"` or a backtick, because CommonMark unescapes info strings and a backtick fence ends at a backtick.
