# Glossary

**Review guide** — The rendered page (HTML, or the Markdown export) that tells the story of a change next to the code it explains. Not: walkthrough, tour, report.

**Story** — The Markdown source that the author writes and the engine renders into a review guide. Never committed: by default at `.storygrafter/<branch>.md` in the worktree, which git ignores. Not: script, guide source.

**Section** — One `##` block of a story: prose on the left, the code it places on the right. Not: chapter (a chapter is just a kicker some sections use).

**Kicker** — The small label above a section title ("Prologue", "Chapter 2"), written before ` · ` in the heading.

**Appendix** — A section under the `# Appendix` heading. It has no code column and places no code; it carries supplementary reading such as research notes.

**Attachment** — A block of supporting material embedded in the guide, folded by default: a payload, a crash excerpt, a log. Never part of the diff.

**Selector** — One line in a section's `hunks` fence that picks code from the diff: a path, optionally narrowed by hunk number, anchor or line range.

**Anchor** — A quoted search string in a selector (`@ "func resync("`) that picks hunks by content, so that the selector survives rebases.

**Changed line** — A `+` or `-` line in the diff. The unit of coverage, except for blank ones. Context lines are not changed lines.

**File change** — A change without hunks: a binary file, a pure rename, a mode change. Placed by selecting its path; counts toward coverage like a changed line.

**Placement** — The assignment of a changed line or file change to a section. A selector marked `again` shows code without placing it.

**Coverage** — The invariant that every changed line and file change in the diff, minus exclusions, is placed exactly once. The build fails otherwise. Not: completeness check.

**Exclusion** — A pathspec glob, declared in the story's front matter, that removes files from the diff. The guide lists every exclusion and the files it removed.

**Marker** — A `{@ "text"}` in section prose that points at one exact place in the section's code. Rendered as a numbered, coloured circle in both columns. Not: callout, annotation.

**Code link** — An inline code span in section prose whose text occurs exactly once in the section's code, and so links to it without a number.

**Replacement** — A run of deleted lines directly followed by a run of added lines in one hunk. Change highlighting pairs lines only within a replacement.

**Upload command** — The author's configured shell command that publishes a file and prints its URL.
