---
name: review-guide
description: Write a review guide for the current branch - the story of the change, told from what this session learned while building it, placed next to every changed line - then build it with the storygrafter command and upload it. Use when the author asks for a review guide, a guided walkthrough of their change, or a story to attach to a PR/MR, typically at the end of the session that wrote the code.
---

# review-guide

A review guide tells the story of a change in sections, each next to the exact diff lines that it explains. The `storygrafter` command checks **coverage**: every changed line is placed in exactly one section, so a reader who reads the story has seen the whole change. Your job is the story; the command does the rest.

The guide has two readers: the author, who reviews code that an agent wrote, and the colleagues who review it after them. Write for both. Its value is what this session knows and the diff does not show: why the change exists, the evidence behind it, the approaches that failed, the edge cases found, what was left alone on purpose.

The guide's deliverable is a file and, when an upload command is configured, a URL. Publishing it to a PR or MR is not part of this skill; hand the URL or path back and let the caller decide.

## 0. Preconditions

- `storygrafter` is on PATH. If not, stop and tell the user: `brew install nevyn/tap/storygrafter`.
- The change is committed. The guide covers `git diff <range>`, never the work tree; mention uncommitted changes if there are any.
- The range. Default `origin/main...HEAD`; use the PR/MR target branch when the session knows it. Run `git fetch` first if the base may be stale.
- `storygrafter format` prints the story format. Read it before writing.

## 1. Map the change

```bash
storygrafter paths                  # where the story and the guide go
storygrafter list --range <range>   # every file and hunk
```

Read every hunk. Read the surrounding code where a hunk only makes sense in context. `storygrafter list --json` gives line numbers when you need them.

## 2. Gather what the session learned

Start from your own context: the problem and how it showed up, the evidence (tickets, crash reports, logs, backend payloads), the approaches tried and rejected with the reason, the edge cases found, the decisions and their reasons, what was deliberately not changed.

If that is thin (the work spanned several sessions, or early details are gone), mine the transcripts. They are JSONL files under `~/.claude/projects/<project dir with / replaced by ->/`, and the user may point you at other sessions too. `grep` them for the names of the types, files and errors in the diff. Read only; never modify or delete a transcript.

Privacy rules, always:
- Never paste transcript text into the story. Paraphrase it, and cite a ticket, commit or file rather than a conversation.
- Before quoting a payload, log or crash excerpt, strip personal data, tokens, credentials and anything the reader has no need for. When unsure whether something may go in, ask the user. The user decides what is in the guide.

## 3. Outline

Order sections the way the change makes sense, not by path. A shape that works:

1. **Prologue**: the problem in one concrete example. No code, or the test that shows it.
2. **The core**: the new primitive or the central fix.
3. **Outwards**: where its inputs come from, then each caller.
4. **Tests**, unless each section already shows its own tests.
5. **Mechanical changes**: renames, moved code, generated files, grouped in one late section with one line on how they were produced.
6. **What this change leaves alone**, and why.
7. **Open questions**, if any.
8. **Appendix**: research notes, the timeline of dead ends, evidence as attachments.

## 4. Write

- Explain the mechanism and the intent, not the diff. "`resync()` now reads the skew before it takes the lock, because the lock is held across a network call" is useful; "adds a `let skew` line" is not.
- Choose each section's selectors so that the code beside the text is what the text talks about. Split a hunk with `lines` or `@ "from" to "to"` when it carries two ideas. Prefer content anchors (`@ "func resync("`) over hunk numbers: anchors survive rebases.
- Show code again in a later section with `again` when that section's point depends on it.
- Evidence goes in footnotes. Long research goes in the appendix. Payloads, logs and crash excerpts go in attachments.
- Write as the author would, in the author's voice. Don't mention the agent or the session ("we found" is fine; "Claude found in this session" is not).
- Plain, concrete language. One idea per sentence. Name who does what. Explain an unusual term the first time.
- Set `head:` in the front matter to `git rev-parse --short HEAD`.

## 5. Review while you write

Writing a section forces you to check its claims against the code, so do that: trace the call paths, walk the edge cases, read the callers you didn't change. Every doubt ends in one of two places:

- **A suspected bug**: stop writing and report it to the user with the evidence (file, line, the input that breaks it). Don't fix it silently. If the user has it fixed, the diff changes; continue against the new HEAD.
- **An open question**: a `> [!QUESTION]` in the section it belongs to, and a line in the Open questions section.

Never smooth a doubt over with confident prose. A reader trusts the guide because it says what is uncertain.

## 6. Check until it holds

```bash
storygrafter check --range <range>
```

Exit 1 lists every unplaced line and every bad selector. Fix them all and re-run until it exits 0. Rules:
- Place every unplaced line in the section where it belongs, or give it a section that explains it. Never add a catch-all section that just swallows leftovers.
- Exclude only generated or binary files that nobody reviews line by line (`*.png`, `*.pbxproj`, lockfiles), in the front matter's `exclude`. The guide lists every exclusion for the reader.

## 7. Build and hand over

```bash
storygrafter build --range <range> --upload   # when an upload command is configured
storygrafter build --range <range>            # otherwise; prints the path
```

`--format md` writes a Markdown version for readers who won't open an HTML file. Report to the caller: the guide's path, the URL when uploaded, the suspected bugs and open questions from step 5, and anything left out at the user's request.

## After every push

Run `storygrafter check` again. Anchors that no longer match and new unplaced lines are listed by name; update those sections, bump `head:`, build and upload again, and hand over the new URL.
