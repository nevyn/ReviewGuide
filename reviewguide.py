#!/usr/bin/env python3
"""Build a side-by-side review guide: a story told in sections on the left, the exact diff hunks
each section explains on the right, in one self-contained HTML file.

Usage:
    reviewguide.py --repo PATH --range BASE..HEAD --story STORY.py --out GUIDE.html [--exclude GLOB ...]

The story is a Python file that the engine runs with these names already defined:
    TITLE = "..."                       # required: the page heading
    META = "..."                        # optional: one line under the heading
    section(id, kicker, title, story_html, code)
                                        # appends one section; code is hunks(...) output or no_code(...)
    hunks(path_fragment, *numbers)      # the hunks of the one file whose path contains path_fragment;
                                        # 1-based hunk numbers, all hunks when none are given
    no_code(text)                       # a placeholder for sections that explain without code

The build fails unless every hunk in the diff is placed in some section, so a story cannot silently
skip part of the change. Run `reviewguide.py --list ...` to print the hunk map while writing a story.
"""
import argparse, html, re, runpy, subprocess, sys
from pathlib import Path


def parse_diff(raw):
    """Map each path in a unified diff to its hunks, in order."""
    files, path, minus = {}, None, None
    for line in raw.splitlines():
        if line.startswith("--- "):
            minus = line[6:] if line.startswith("--- a/") else line[4:]
        elif line.startswith("+++ "):
            plus = line[6:] if line.startswith("+++ b/") else line[4:]
            # git appends a tab to paths that contain spaces; a deleted file has /dev/null on this side.
            path = (minus if plus == "/dev/null" else plus).rstrip("\t")
            files[path] = []
        elif line.startswith("@@") and path:
            m = re.match(r"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@(.*)", line)
            files[path].append({"ctx": m.group(3).strip(), "old": int(m.group(1)), "new": int(m.group(2)), "lines": []})
        elif path and files[path] and not line.startswith(("diff --git", "index ", "new file", "deleted file", "\\")):
            files[path][-1]["lines"].append(line)
    return files


def render_hunk(path, hunk):
    old, new, rows = hunk["old"], hunk["new"], []
    for line in hunk["lines"]:
        text = html.escape(line[1:]) or "&nbsp;"
        if line.startswith("-"):
            rows.append(f'<tr class="del"><td class="ln">{old}</td><td class="ln"></td><td class="sg">−</td><td class="code">{text}</td></tr>')
            old += 1
        elif line.startswith("+"):
            rows.append(f'<tr class="add"><td class="ln"></td><td class="ln">{new}</td><td class="sg">+</td><td class="code">{text}</td></tr>')
            new += 1
        else:
            rows.append(f'<tr><td class="ln">{old}</td><td class="ln">{new}</td><td class="sg"></td><td class="code">{text}</td></tr>')
            old += 1
            new += 1
    ctx = f' <span class="ctx">{html.escape(hunk["ctx"])}</span>' if hunk["ctx"] else ""
    return (f'<div class="hunk"><div class="file" title="{html.escape(path)}"><span class="fname">{html.escape(path.split("/")[-1])}</span>'
            f'<span class="fpath">{html.escape(path)}</span>{ctx}</div><table>{"".join(rows)}</table></div>')


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--repo", default=".", help="git repository to diff (default: current directory)")
    ap.add_argument("--range", required=True, help="git diff range, e.g. origin/main...HEAD")
    ap.add_argument("--exclude", action="append", default=[], help="pathspec glob to leave out, e.g. '*.png' (repeatable)")
    ap.add_argument("--story", help="story file (Python), see the module docstring")
    ap.add_argument("--out", help="HTML file to write")
    ap.add_argument("--list", action="store_true", help="print the hunk map and exit")
    args = ap.parse_args()

    pathspec = ["--", ".", *[f":!{glob}" for glob in args.exclude]]
    git = lambda *a: subprocess.run(["git", "-C", args.repo, *a], capture_output=True, text=True, check=True).stdout
    files = parse_diff(git("diff", args.range, *pathspec))

    if args.list:
        for path, file_hunks in files.items():
            for i, h in enumerate(file_hunks, 1):
                print(f"{path}  #{i}  {h['ctx']}")
        return
    if not (args.story and args.out):
        ap.error("--story and --out are required unless --list is given")

    sections, placed = [], set()

    def find(fragment):
        hits = [p for p in files if fragment in p]
        if len(hits) != 1:
            sys.exit(f"hunks({fragment!r}) must match exactly one path in the diff, matched {hits}")
        return hits[0]

    def hunks(fragment, *numbers):
        path = find(fragment)
        numbers = numbers or range(1, len(files[path]) + 1)
        out = []
        for n in numbers:
            if not 1 <= n <= len(files[path]):
                sys.exit(f"{path} has {len(files[path])} hunks, the story asked for #{n}")
            placed.add((path, n))
            out.append(render_hunk(path, files[path][n - 1]))
        return "".join(out)

    def no_code(text):
        return f'<div class="empty">{html.escape(text)}</div>'

    def section(sid, kicker, title, story_html, code):
        sections.append((sid, kicker, title, story_html, code))

    story = runpy.run_path(args.story, init_globals={"section": section, "hunks": hunks, "no_code": no_code})
    missing = [f"{p} #{i}" for p in files for i in range(1, len(files[p]) + 1) if (p, i) not in placed]
    if missing:
        sys.exit("hunks not placed in any section:\n  " + "\n  ".join(missing))

    nav = "".join(f'<a href="#{sid}"><span>{html.escape(k)}</span>{html.escape(t)}</a>' for sid, k, t, _, _ in sections)
    body = "".join(f'''
<section id="{sid}">
  <div class="story"><div class="sticky"><div class="kicker">{html.escape(k)}</div><h2>{html.escape(t)}</h2>{s}</div></div>
  <div class="code">{c}</div>
</section>''' for sid, k, t, s, c in sections)
    stat = git("diff", "--shortstat", args.range, *pathspec).strip()
    meta = " · ".join(x for x in (story.get("META", ""), f"<code>{html.escape(args.range)}</code>", html.escape(stat)) if x)
    template = (Path(__file__).parent / "template.html").read_text()
    page = (template.replace("{{TITLE}}", html.escape(story["TITLE"])).replace("{{META}}", meta)
            .replace("{{NAV}}", nav).replace("{{BODY}}", body))
    Path(args.out).write_text(page)
    print(f"wrote {args.out}: {len(sections)} sections, {len(placed)} hunks placed")


if __name__ == "__main__":
    main()
