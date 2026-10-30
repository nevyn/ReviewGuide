# Guide markup for tools

A review guide is a page for people, but a tool that shows the guide can place other things on it: a
reviewer's comments, a colleague's threads, a link into its own diff view. These attributes are the
contract for that. The classes and the element structure around them style the page and may change
between versions; the attributes stay.

| Element | Attributes | Meaning |
|---|---|---|
| `body` | `data-base`, `data-head` | The full shas of the diff's old and new side. `git diff <base> <head>` is the change the guide explains. |
| `tr` of a hunk table | `data-path`, `data-old`, `data-new` | The file path at the head, and the line's number on the old and new side. A deleted line has an empty `data-new`, an added line an empty `data-old`, a context line both. Gap rows (`class="gap"`) carry none of these. |
| `section` | `id` | The section's id, the target of the navigation and marker links. |

A tool that maps a row to its own view of the same change should check the text of the row against its
own copy of the line rather than trust the shas alone: the guide may have been built for an earlier
push, and a story can exclude files, so a row is only as current as the diff it is compared with.
