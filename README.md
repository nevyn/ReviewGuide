# StoryGrafter

A gardener grafts a scion onto a rootstock so that the two grow as one tree. StoryGrafter grafts the author's story onto a code change, line by line.

It builds a **review guide**: the story of a change in sections on the left, and next to each section the exact diff lines it explains. The output is one self-contained HTML file. The idea comes from Linear's review guides (https://linear.app/docs/diffs).

[![A section of StoryGrafter's own review guide: the story on the left, the highlighted code it explains on the right](docs/images/example-guide.png)](https://files.d.nevyn.dev/k/1d773aad592e8125/storygrafter-v1-guide.html)

[Open the full example guide](https://files.d.nevyn.dev/k/1d773aad592e8125/storygrafter-v1-guide.html): StoryGrafter's own v1 change, built from [example/story.md](example/story.md).

The build enforces **coverage**: every changed line of the diff is placed in exactly one section, so a reviewer who reads the story has seen the whole change.

## Let your agent write it

StoryGrafter is meant to be run by the coding agent that made the change, at the end of the session. The agent knows what the diff doesn't show: why the change exists, the evidence behind it, the approaches that failed, the edge cases it found. A review guide is where that knowledge lands, next to the code it explains. Writing the guide is also a review: explaining each section forces the agent to check its claims against the code, and that finds bugs.

Install it, then give your agent this prompt:

```
Write a review guide for this branch with `storygrafter` (run `storygrafter --help`).

1. Read the story format with `storygrafter format`. `storygrafter paths` says where the
   story goes; `storygrafter list` shows every hunk in the diff. Use our merge request's
   target branch for the range (default origin/main...HEAD).
2. Tell the story in the order the change makes sense, not file by file: a prologue
   with the problem in one concrete example, then the core change, then outwards to
   its callers, and last what the change deliberately leaves alone.
3. Include what this conversation knows and the diff doesn't: why we made the change,
   the evidence (tickets, crash reports, logs, payloads), the approaches we tried and
   dropped and why, and the edge cases we found. Use footnotes for evidence and the
   appendix for longer research. Paraphrase; never paste conversation text, and strip
   personal data and secrets from anything you quote.
4. Explain mechanism and intent, not the diff. Pick each section's code with content
   anchors so that the code beside the text is what the text is about.
5. Check every claim against the code while you write. If you find a bug, stop and
   tell me. Mark anything unsettled with a `> [!QUESTION]` alert.
6. Run `storygrafter check` until it passes, then `storygrafter build`, and give me
   the path to the HTML file.
```

Attach the HTML file to the merge request the way your forge allows, or let the agent do it. After every push, ask the agent to run `storygrafter check` again, fix what moved, and rebuild.

## Install

```sh
brew install nevyn/tap/storygrafter
```

## Usage

```sh
storygrafter format                # the story format
storygrafter paths                 # where the story and the guide for this branch live
storygrafter list                  # the diff's hunks, and where the story places each one
storygrafter check                 # every coverage and selector problem, or ok
storygrafter build                 # write the guide and print its path
```

Stories live out of tree, in `.git/review-guides/<branch>.md`, and the guide is written next to them. The range defaults to `origin/main...HEAD`; set `range:` in the story or pass `--range`. `storygrafter list --json` is for agents. The docs are listed in [docs/index.md](docs/index.md).

## Optional extras

- **Upload in one step.** Configure an upload command that publishes a file and prints its URL, and `storygrafter build --upload` prints a link to paste into the merge request. See [docs/cli.md](docs/cli.md#configuration).
- **A Claude Code skill.** The `review-guide` skill carries the prompt above and more: when to mine transcripts, how to handle private data, what to hand back. Add it with `/plugin marketplace add nevyn/StoryGrafter`, then install `storygrafter`.

## Writing a good story

- Tell it from the core outwards: the new primitive, where its inputs come from, then each caller. A prologue states the problem in one concrete example; the last section covers what the change deliberately leaves alone.
- Explain mechanism and intent, not the diff. Choose each section's code so that what sits beside the text is what the text is about.
- Prefer content anchors (`@ "func resync("`, `@ "from" until "to"`) over hunk numbers and line numbers: anchors survive rebases.

## Constraints

- Generated guides embed the reviewed code. Never commit one, and never publish one somewhere the code's owner wouldn't.
- No external assets, fonts or scripts in the page: it must work offline and when attached to a merge request.
