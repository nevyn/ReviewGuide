# ReviewGuide

Builds a review guide for a code change: the author's story on the left, in sections, and next to each section the exact diff hunks it explains. The output is one self-contained HTML file that a reviewer downloads from the merge request and opens in a browser. The idea comes from Linear's review guides (https://linear.app/docs/diffs).

## Status

A first working version, extracted from a single real use: a ~30-hunk merge request whose reviewer called the guide "a great addition that made this easy to follow". The engine is generic; the workflow around it is not yet. This README is a handover for whoever generalizes it.

## Usage

```sh
# Print the hunk map while writing a story
python3 reviewguide.py --repo PATH --range origin/main...HEAD --exclude '*.png' --list

# Build the guide
python3 reviewguide.py --repo PATH --range origin/main...HEAD --exclude '*.png' --story story.py --out guide.html
```

`example/story.py` documents this repository's own first commit; its header has the command.

## Story format

A story is a Python file. The engine runs it with these names defined:

| Name | Meaning |
|---|---|
| `TITLE` | Required. The page heading. |
| `META` | Optional. One line under the heading, before the range and the diff stat. |
| `section(id, kicker, title, story_html, code)` | Appends a section. `kicker` is the small label above the title ("Chapter 2"). `story_html` is trusted HTML. |
| `hunks(path_fragment, *numbers)` | Renders hunks of the one file whose path contains the fragment; 1-based numbers, all of them when none are given. |
| `no_code(text)` | A placeholder for a section that explains without code. |

The build fails unless every hunk in the diff is placed in some section. Keep that invariant: it is what makes the guide trustworthy, because the reviewer knows nothing in the diff is missing from the story.

## How the first guide was written

- One agent wrote the story from its own understanding of the change, chapter by chapter from the core outwards: the new primitive, where its inputs come from, then each caller. A prologue states the bug in one concrete example; the last chapter covers what the change deliberately leaves alone.
- Sections explain mechanism and intent, not the diff. Each section's hunks are chosen so the code beside it is what the text is about.
- The guide was rebuilt and re-uploaded after every push, so the attached copy always matched the reviewed head. The MR description linked it on its first line.

## Open decisions for the next iteration

1. **Story format.** Python works but is awkward to author and lets a story run arbitrary code. Candidates: Markdown with a fenced hunk selector per section, or YAML. Selecting hunks by number breaks when the diff changes; selecting by a search string inside the hunk would survive rebases.
2. **Who drafts the story.** Today an agent writes it by hand. A skill could draft it from the diff, the ticket and the commit messages, for the author to edit before publishing.
3. **Publishing.** GitLab serves an uploaded `.html` as a download, not inline. Alternatives: GitLab Pages, a CI artifact, posting the sections as diff comments anchored to their hunks, or a Markdown version as one MR comment.
4. **Packaging.** A plain script, a CLI on PATH, or a Claude Code skill that writes the story, builds and uploads.
5. **Language.** Python 3 standard library only, so it runs anywhere. Swift would match other tooling.

## Constraints

- Generated guides embed the reviewed code. They are git-ignored here; never commit one, and never publish one somewhere the code's owner wouldn't.
- No external assets, fonts or scripts in the page: it must work offline and when attached to an MR.
