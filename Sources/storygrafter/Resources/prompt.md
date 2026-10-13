# Writing a review guide with storygrafter

A review guide tells the story of a code change in sections, each next to the exact diff lines that it explains. `storygrafter` checks **coverage**: every changed line is placed in exactly one section, so a reader who reads the story has seen the whole change. Your job is the story; the tool does the rest.

The guide has two readers: the author, who reviews code that an agent may have written, and the colleagues who review it after them. Its value is what this conversation knows and the diff doesn't show: why the change exists, the evidence behind it, the approaches that failed, the edge cases found, what was left alone on purpose.

## 1. Prepare

- The guide covers `git diff <range>` of committed code, never the work tree. Commit first, or say which changes are left out.
- Use the range from the context above. If the merge request targets another branch, set `range:` in the story's front matter.
- Run `storygrafter format` and read the story format before writing.
- Run `storygrafter list` to see every file and hunk; `storygrafter list --json` gives line numbers. Read every hunk, and the surrounding code where a hunk only makes sense in context.

## 2. Gather what the session learned

Start from your own context: the problem and how it showed up, the evidence (tickets, crash reports, logs, backend payloads), the approaches tried and rejected with the reason, the edge cases found, the decisions and their reasons, what was deliberately not changed. If that is thin because the work spanned several sessions, and your harness keeps transcripts of earlier sessions, search them for the names of the types, files and errors in the diff. Only read them.

Privacy, always:
- Never paste conversation text into the story. Paraphrase, and cite a ticket, commit or file rather than a conversation.
- Before quoting a payload, log or crash excerpt, strip personal data, tokens, credentials and anything the reader doesn't need. When unsure whether something may go in, ask the user. The user decides what is in the guide.

## 3. Outline

Order sections the way the change makes sense, not by path:

1. **Prologue**: the problem in one concrete example.
2. **The core**: the new primitive or the central fix.
3. **Outwards**: where its inputs come from, then each caller.
4. **Tests**, unless each section already shows its own.
5. **Mechanical changes**: renames, moved code, generated files, in one late section with a line on how they were produced.
6. **What this change leaves alone**, and why.
7. **Open questions**, if any.
8. **Appendix**: research notes, the dead ends, evidence as attachments.

## 4. Write

- Explain mechanism and intent, not the diff. "`resync()` now reads the skew before it takes the lock, because the lock is held across a network call" is useful; "adds a `let skew` line" is not.
- Point at the exact code you are talking about with markers: `{@ "let skew"}` puts a numbered circle in the sentence and on that text in the code. Use one wherever a sentence makes a claim about a specific line or token, typically one to four per section. Name code in backticks too: a backticked name that occurs once in the section's code links to it automatically.
- Choose each section's selectors so that the code beside the text is what the text is about. Prefer content anchors (`@ "func resync("`, `@ "from" until "next"`, `@ "from" to end`) over hunk and line numbers: anchors survive rebases.
- Put evidence in footnotes, long research in the appendix, and payloads, logs and crash excerpts in attachments.
- Write in the author's voice. Don't mention the agent or the session.
- Plain, concrete language. One idea per sentence. Name who does what.
- Set `head:` in the front matter to the commit the guide describes.

## 5. Review while you write

Writing a section forces you to check its claims against the code, so do it: trace the call paths, walk the edge cases, read the callers you didn't change. Every doubt ends in one of two places:

- **A suspected bug**: stop and report it to the user with the evidence (file, line, the input that breaks it). Don't fix it silently.
- **An open question**: a `> [!QUESTION]` alert in its section, and a line in the open questions section.

Never smooth a doubt over with confident prose.

## 6. Check until it holds

Run `storygrafter check` and fix everything it lists until it exits 0. Place every unplaced line where it belongs, or give it a section that explains it; never add a catch-all section that just swallows leftovers. Exclude only generated or binary files that nobody reviews line by line, in the front matter's `exclude`.

## 7. Build

Run `storygrafter build`. It prints the path of the HTML file; that file is the review guide. `--format md` also writes a Markdown version.

## 8. Publish, when asked to

- If the context above says an upload command is configured, `storygrafter build --upload` also prints a URL.
- Otherwise use the forge's own attachments. GitLab's project uploads API (`POST /projects/:id/uploads`) returns a Markdown link to paste. GitHub has no API for pull request attachments: unless the repository's instructions name another place, hand the path to the user.
- Publish only where the code's owner would. A guide contains the reviewed code, and forge uploads may be permanent.
- Link the guide from the merge request description under a "Review guide" heading, and replace the previous link rather than adding another. Editing a description is visible to others: follow the user's rules for outward-facing actions.

## 9. Keep it current

Build the guide when the merge request leaves draft, and again after every push. Run `storygrafter check`: anchors that no longer match and new unplaced lines are listed by name. Update those sections, set `head:` to the new commit, build, publish, and replace the link.

## Hand back

Report the guide's path (and URL, if uploaded), the suspected bugs and open questions from step 5, and anything left out at the user's request.
