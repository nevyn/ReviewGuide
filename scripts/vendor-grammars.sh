#!/bin/bash
# Vendors tree-sitter grammars into Grammars/ and their highlight queries into
# Sources/Highlight/Resources/queries/. See docs/grammars.md.
# Re-running with unchanged pins changes nothing. Files that a pin bump no longer
# produces are not deleted: check `git status` after a bump.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
grammars="$root/Grammars"
queries="$root/Sources/Highlight/Resources/queries"

# name | repo | ref | dir | grammar subdirectory in the repo | query parts
# dir is the path under Grammars/; grammars from one repo share its parent.
# A query part is <name>:<path in that grammar's repo>; parts are concatenated in order, base first.
pins='
swift|alex-pinkus/tree-sitter-swift|0.7.4-with-generated-files|swift|.|swift:queries/highlights.scm
c|tree-sitter/tree-sitter-c|v0.24.2|c|.|c:queries/highlights.scm
objc|tree-sitter-grammars/tree-sitter-objc|v3.0.2|objc|.|c:queries/highlights.scm objc:queries/highlights.scm
cpp|tree-sitter/tree-sitter-cpp|v0.23.4|cpp|.|c:queries/highlights.scm cpp:queries/highlights.scm
kotlin|fwcd/tree-sitter-kotlin|0.3.8|kotlin|.|kotlin:queries/highlights.scm
java|tree-sitter/tree-sitter-java|v0.23.5|java|.|java:queries/highlights.scm
javascript|tree-sitter/tree-sitter-javascript|v0.25.0|javascript|.|javascript:queries/highlights.scm javascript:queries/highlights-jsx.scm javascript:queries/highlights-params.scm
typescript|tree-sitter/tree-sitter-typescript|v0.23.2|typescript/typescript|typescript|javascript:queries/highlights.scm typescript:queries/highlights.scm
tsx|tree-sitter/tree-sitter-typescript|v0.23.2|typescript/tsx|tsx|javascript:queries/highlights.scm javascript:queries/highlights-jsx.scm typescript:queries/highlights.scm
python|tree-sitter/tree-sitter-python|v0.25.0|python|.|python:queries/highlights.scm
ruby|tree-sitter/tree-sitter-ruby|v0.23.1|ruby|.|ruby:queries/highlights.scm
go|tree-sitter/tree-sitter-go|v0.25.0|go|.|go:queries/highlights.scm
rust|tree-sitter/tree-sitter-rust|v0.24.2|rust|.|rust:queries/highlights.scm
json|tree-sitter/tree-sitter-json|v0.24.8|json|.|json:queries/highlights.scm
yaml|tree-sitter-grammars/tree-sitter-yaml|v0.7.2|yaml|.|yaml:queries/highlights.scm
toml|tree-sitter-grammars/tree-sitter-toml|v0.7.0|toml|.|toml:queries/highlights.scm
bash|tree-sitter/tree-sitter-bash|v0.25.1|bash|.|bash:queries/highlights.scm
sql|DerekStride/tree-sitter-sql|39fdb006403747241244326e8af3b3e96b85381c|sql|.|sql:queries/highlights.scm
html|tree-sitter/tree-sitter-html|v0.23.2|html|.|html:queries/highlights.scm
css|tree-sitter/tree-sitter-css|v0.25.0|css|.|css:queries/highlights.scm
markdown|tree-sitter-grammars/tree-sitter-markdown|v0.5.3|markdown/block|tree-sitter-markdown|markdown:tree-sitter-markdown/queries/highlights.scm
markdown_inline|tree-sitter-grammars/tree-sitter-markdown|v0.5.3|markdown/inline|tree-sitter-markdown-inline|markdown_inline:tree-sitter-markdown-inline/queries/highlights.scm
'
# sql: tags carry no generated parser.c, so the pin is a commit on the gh-pages branch.

work="$(mktemp -d /tmp/vendor-grammars.XXXXXX)"
trap 'rm -rf "$work"' EXIT

# Prints the checkout dir of repo@ref, fetching it once per run.
checkout() {
    local repo="$1" ref="$2"
    local dir="$work/$(echo "$repo@$ref" | tr '/@' '__')"
    if [ ! -d "$dir" ]; then
        git init -q "$dir"
        git -C "$dir" fetch -q --depth 1 "https://github.com/$repo" "$ref" ||
            { echo "error: cannot fetch $repo at $ref" >&2; exit 1; }
        git -C "$dir" checkout -q FETCH_HEAD
    fi
    echo "$dir"
}

field() { echo "$1" | cut -d'|' -f"$2"; }

pin_line() {
    echo "$pins" | grep "^$1|" || { echo "error: no pin for '$1'" >&2; exit 1; }
}

mkdir -p "$grammars" "$queries"
pins_file="$grammars/PINS"
: > "$work/PINS"
echo "# name repo ref commit (written by scripts/vendor-grammars.sh)" >> "$work/PINS"

echo "$pins" | while IFS='|' read -r name repo ref dir sub parts; do
    [ -n "$name" ] || continue
    repo_dir="$(checkout "$repo" "$ref")"
    commit="$(git -C "$repo_dir" rev-parse HEAD)"
    echo "$name $repo $ref $commit" >> "$work/PINS"
    echo "vendoring $name from $repo@$ref" >&2

    src="$repo_dir/$sub/src"
    dest="$grammars/$dir"
    [ -f "$src/parser.c" ] || { echo "error: $repo@$ref has no $sub/src/parser.c" >&2; exit 1; }
    mkdir -p "$dest/src/tree_sitter" "$dest/include"
    cp "$src/parser.c" "$dest/src/"
    for f in "$src"/scanner.c "$src"/schema.*.c "$src"/*.h; do
        [ -f "$f" ] && cp "$f" "$dest/src/"
    done
    cp "$src"/tree_sitter/*.h "$dest/src/tree_sitter/"

    # Grammars from one repo share its LICENSE and common/ headers, one level up.
    if [ "$sub" = "." ]; then group="$dest"; else group="$(dirname "$dest")"; fi
    for f in LICENSE LICENSE.md LICENSE.txt; do
        [ -f "$repo_dir/$f" ] && cp "$repo_dir/$f" "$group/LICENSE"
    done
    [ -f "$group/LICENSE" ] || { echo "error: $repo@$ref has no LICENSE" >&2; exit 1; }
    if [ -d "$repo_dir/common" ]; then
        for f in "$repo_dir"/common/*.h; do
            [ -f "$f" ] && mkdir -p "$group/common" && cp "$f" "$group/common/"
        done
    fi

    printf '#pragma once\ntypedef struct TSLanguage TSLanguage;\nconst TSLanguage *tree_sitter_%s(void);\n' "$name" \
        > "$dest/include/tree_sitter_$name.h"

    out="$work/$name.scm"
    : > "$out"
    for part in $parts; do
        part_name="${part%%:*}"
        part_path="${part#*:}"
        line="$(pin_line "$part_name")"
        part_repo="$(field "$line" 2)"
        part_ref="$(field "$line" 3)"
        part_dir="$(checkout "$part_repo" "$part_ref")"
        [ -f "$part_dir/$part_path" ] || { echo "error: $part_repo@$part_ref has no $part_path" >&2; exit 1; }
        printf '; ---- %s@%s %s\n' "$part_repo" "$part_ref" "$part_path" >> "$out"
        cat "$part_dir/$part_path" >> "$out"
        echo >> "$out"
    done
    cp "$out" "$queries/$name.scm"
done

cp "$work/PINS" "$pins_file"
