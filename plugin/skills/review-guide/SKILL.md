---
name: review-guide
description: Write a review guide for the current branch with storygrafter - the story of the change, told from what this session learned while building it, placed next to every changed line - then build it and, when asked, publish it on the PR/MR. Use when the author asks for a review guide, a guided walkthrough of their change, or a story to attach to a PR/MR, typically at the end of the session that wrote the code, when an MR leaves draft, or after a push to one.
---

# review-guide

Run `storygrafter prompt` and follow its instructions. It prints this repository's context (range, story path, upload configuration) and the instructions that match the installed version of storygrafter.

If `storygrafter` is not on PATH, stop and tell the user: `brew install nevyn/tap/storygrafter`.
