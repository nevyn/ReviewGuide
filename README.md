# StoryGrafter

A gardener grafts a scion onto a rootstock so that the two grow as one tree. StoryGrafter grafts the author's story onto a code change, line by line.

It builds a review guide for a code change: the author's story on the left, in sections, and next to each section the exact diff lines it explains. The output is one self-contained HTML page that the author uploads and links from the merge request. The idea comes from Linear's review guides (https://linear.app/docs/diffs).

The build enforces coverage: every changed line of the diff is placed in exactly one section, so a reviewer who reads the story has seen the whole change.

## Install

```sh
brew install nevyn/tap/storygrafter
```

## Usage

```sh
storygrafter paths                 # where the story for this branch lives
storygrafter list                  # the diff's hunks, and where the story places each one
storygrafter check                 # every coverage and selector problem, or ok
storygrafter build --upload        # write the guide, upload it, print its URL
```

The range defaults to `origin/main...HEAD`; set `range:` in the story or pass `--range`. `storygrafter list --json` is meant for agents that draft stories. Stories are Markdown, documented in [docs/story-format.md](docs/story-format.md); `example/story.md` describes this repository's own change. All the docs are listed in [docs/index.md](docs/index.md).

## Writing a good story

- Tell it from the core outwards: the new primitive, where its inputs come from, then each caller. A prologue states the problem in one concrete example; the last section covers what the change deliberately leaves alone.
- Explain mechanism and intent, not the diff. Choose each section's code so that what sits beside the text is what the text is about.
- Rebuild and re-upload after every push, so that the linked guide always matches the reviewed head.

## Constraints

- Generated guides embed the reviewed code. Never commit one, and never publish one somewhere the code's owner wouldn't.
- No external assets, fonts or scripts in the page: it must work offline and when attached to a merge request.
