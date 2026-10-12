# A review guide for this repository's own first commit. Build it from the repo root with:
#   python3 reviewguide.py --range "$(git hash-object -t tree /dev/null)..HEAD" --story example/story.py --out /tmp/guide.html

TITLE = "ReviewGuide · first commit"
META = "The tool documenting itself"

section("why", "Prologue", "A diff is a list; a change is a story", """
<p>A reviewer reading a diff file by file sees the parts in alphabetical order, not in the order they make sense.</p>
<p>A review guide puts the author's explanation next to the code it explains: the story on the left, its hunks on the right, one section per idea. The reviewer reads the story top to bottom and still sees every changed line.</p>
""", no_code("No code here: the next sections walk the commit."))

section("engine", "Chapter 1", "The engine", """
<p><code>parse_diff</code> splits <code>git diff</code> output into hunks per path. Paths containing spaces get a trailing tab from git, and deleted files have <code>/dev/null</code> on the new side; both are handled there.</p>
<p>The story is plain Python, run with three helpers already defined: <code>section</code>, <code>hunks</code> and <code>no_code</code>. <code>hunks</code> picks hunks by path fragment and 1-based number, and records them as placed.</p>
<p><b>The one invariant:</b> the build fails if any hunk in the diff is not placed in some section, so a story cannot quietly skip part of the change.</p>
""", hunks("reviewguide.py"))

section("template", "Chapter 2", "The page", """
<p>One self-contained HTML file with no external assets, so it can be attached to a merge request and opened offline. Light and dark follow the reader's system setting.</p>
<p>Each section is a two-column grid; the story column is sticky, so it stays in view while a long diff scrolls past. Below 900&nbsp;px the columns stack.</p>
""", hunks("template.html"))

section("docs", "Chapter 3", "Handover notes and this example", """
<p>The README records what works, what is still shaped by its first use, and the decisions the next iteration has to make. This story is the example it points to.</p>
""", hunks("README.md") + hunks(".gitignore") + hunks("example/story.py"))
