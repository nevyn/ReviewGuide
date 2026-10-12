#!/bin/bash
# Usage:
#   scripts/release.sh 0.2.0   release a new version from origin/main
#   scripts/release.sh redo    delete the latest release and its tag, then release the same version again from HEAD
# Then waits for the release workflow and updates Formula/reviewguide.rb in the tap checkout at $TAP_DIR.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
TAP_DIR="${TAP_DIR:-$HOME/Dev/homebrew-tap}"
REPO=nevyn/ReviewGuide

die() { echo "release: $*" >&2; exit 1; }

[ -z "$(git status --porcelain)" ] || die "the work tree is not clean"
[ "$(git symbolic-ref --short HEAD)" = main ] || die "not on main"
git fetch -q origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "main differs from origin/main"
[ -d "$TAP_DIR/.git" ] || die "no tap checkout at $TAP_DIR (set TAP_DIR)"

notes="$(mktemp)"
if [ "${1:-}" = redo ]; then
    tag="$(gh release view --repo "$REPO" --json tagName -q .tagName)"
    version="${tag#v}"
    gh release view "$tag" --repo "$REPO" --json body -q .body > "$notes"
    echo "release: redoing $tag; notes saved to $notes"
    gh release delete "$tag" --repo "$REPO" --cleanup-tag --yes
    git tag -d "$tag" 2>/dev/null || true
else
    version="${1:?usage: scripts/release.sh VERSION | redo}"
    tag="v$version"
    git rev-parse -q --verify "refs/tags/$tag" > /dev/null && die "$tag already exists; use redo"
    printf '// Written by scripts/release.sh.\nlet reviewguideVersion = "%s"\n' "$version" > Sources/reviewguide/Version.swift
    git commit -q -m "Release $version" Sources/reviewguide/Version.swift
    git push -q origin main
    previous="$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || git rev-list --max-parents=0 HEAD)"
    git log --format='- %s' "$previous..HEAD^" > "$notes"
    "${EDITOR:-vi}" "$notes"
fi

gh release create "$tag" --repo "$REPO" --target "$(git rev-parse HEAD)" --title "$version" --notes-file "$notes"
sleep 10
run="$(gh run list --repo "$REPO" --workflow release.yml --branch "$tag" --limit 1 --json databaseId -q '.[0].databaseId')"
[ -n "$run" ] || die "no release workflow run found for $tag"
gh run watch "$run" --repo "$REPO" --exit-status

sha="$(gh release download "$tag" --repo "$REPO" --pattern '*.sha256' --output - | cut -d' ' -f1)"
[ ${#sha} -eq 64 ] || die "bad sha256 '$sha' for $tag"
mkdir -p "$TAP_DIR/Formula"
sed -e "s/@VERSION@/$version/g" -e "s/@SHA256@/$sha/" packaging/reviewguide.rb.template | grep -v '^# Template' > "$TAP_DIR/Formula/reviewguide.rb"
git -C "$TAP_DIR" add Formula/reviewguide.rb
git -C "$TAP_DIR" commit -q -m "reviewguide $version"
git -C "$TAP_DIR" push -q
echo "release: $tag published; brew upgrade reviewguide"
