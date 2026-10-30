# CLI

`storygrafter` runs inside a git work tree, or anywhere with `--repo`. Every command that reads a story defaults to the story path of the current branch.

| Command | Does |
|---|---|
| `storygrafter list [--json]` | Prints the diff's files and hunks. With a story, it also shows where each changed line is placed. |
| `storygrafter check` | Resolves the story against the diff and reports every coverage and selector error. Writes nothing. |
| `storygrafter build [--format html\|md] [--out FILE] [--upload]` | Checks, then writes the review guide and prints its path. The file is the deliverable. With `--upload`, it also runs the upload command and prints the URL as the last line of stdout. |
| `storygrafter upload FILE` | Runs the upload command on `FILE` and prints the URL. |
| `storygrafter paths` | Prints the default story and output paths for the current branch, creating their directory. |
| `storygrafter format` | Prints the story format specification for the installed version. |
| `storygrafter prompt` | Prints instructions for a coding agent to write, check, build and publish a review guide, preceded by this repository's context: branch, head, range, story path, and whether an upload command is configured. |

Common options: `--repo PATH` (default `.`), `--range RANGE` (overrides the story's `range`), `--story FILE`.

The range defaults to `<origin's default branch>...HEAD`, read from `refs/remotes/origin/HEAD`. `git clone` and `git fetch` set that ref, and `git remote set-head origin --auto` repairs it. Without it, the default is `origin/main...HEAD`.

## Default paths

Stories and guides live in the worktree, where agents are allowed to write; agent sandboxes and permission modes refuse writes inside `.git`:

```
<worktree>/.storygrafter/<branch>.md
<worktree>/.storygrafter/<branch>.html   # or .guide.md for --format md
```

storygrafter writes a `.gitignore` containing `*` into `.storygrafter/`. Git applies it to the whole directory, the `.gitignore` included, so nothing in it ever shows in `git status`, and the repository's own ignore files stay untouched. Each worktree keeps its own stories.

A story that already exists elsewhere wins, in this order: `.storygrafter/` in the worktree, `<git-common-dir>/review-guides/` (where storygrafter 0.3 and earlier kept stories), then `/tmp/storygrafter/<repo>-<hash>/`. When the worktree is not writable, a new story goes to `/tmp`, where it lasts until reboot. `storygrafter paths` and `storygrafter prompt` say which place is in use.

`<branch>` keeps its slashes as subdirectories. A detached HEAD is an error unless `--story` is given. With `--story x/foo.md`, the guide defaults to `x/foo.html` or `x/foo.guide.md`.

## Exit status

| Code | Meaning |
|---|---|
| 0 | Success. Warnings (such as a `head` mismatch) go to stderr. |
| 1 | The story does not satisfy the diff: coverage or selector errors, all of them listed on stderr as `<section id>: <selector>: <problem>` or `unplaced: <path> #<hunk> <old>/<new>: <line text>`. A hunk with more than three changed lines, none of them placed, is one line: `unplaced: <path> #<hunk> (all of it: +<added> -<deleted>)`. |
| 2 | Usage error, git failure, unreadable story, or upload failure. The message names the failing input. |

## `list --json`

```json
{
  "range": "origin/main...HEAD",
  "base": "<merge-base sha>",
  "head": "<HEAD sha>",
  "excluded": [{"pattern": "*.png", "files": ["Assets/icon.png"]}],
  "files": [{
    "path": "Sources/Clock/Station.swift",
    "oldPath": null,
    "status": "modified",
    "placedIn": null,
    "hunks": [{
      "number": 1,
      "header": "final class Station {",
      "oldStart": 40, "oldCount": 7, "newStart": 40, "newCount": 9,
      "lines": [
        {"kind": "context", "old": 40, "new": 40, "text": "    func resync() {", "placedIn": null},
        {"kind": "add", "old": null, "new": 41, "text": "        let skew = clock.skew", "placedIn": "primitive"}
      ]
    }]
  }]
}
```

- `status` is one of `added`, `deleted`, `modified`, `renamed`, `copied`, `binary`, `mode`.
- `placedIn` is the id of the section that placed the line or file change. It is `null` when nothing placed it, and always `null` on context lines and without a story.
- A file's `placedIn` is used only for a file without hunks.

## Configuration

Uploading is optional: without an upload command, `build` writes the file and the author attaches it to the merge request. The upload command comes from the `STORYGRAFTER_UPLOAD` environment variable, or else from `upload = …` in `~/.config/storygrafter/config` (lines of `key = value`; `#` starts a comment).

The command is a template run by `/bin/sh -c`. `{file}` is replaced with the shell-quoted absolute path of the guide. The URL is the last stdout line that starts with `http://` or `https://`. stderr passes through. A non-zero exit, or no URL, is an upload failure.

```
upload = upload {file}
```
