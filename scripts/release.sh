#!/bin/bash
# Usage:
#   scripts/release.sh 0.2.0   tag v0.2.0 on origin/main and push it; CI builds, releases and updates the tap
#   scripts/release.sh redo    delete the latest release and its tag, then tag the same version on origin/main again
set -euo pipefail
REPO=nevyn/ReviewGuide

die() { echo "release: $*" >&2; exit 1; }

git fetch -q origin --tags
head="$(git rev-parse origin/main)"

if [ "${1:-}" = redo ]; then
    tag="$(gh release view --repo "$REPO" --json tagName -q .tagName)"
    echo "release: redoing $tag at $(git rev-parse --short "$head")"
    gh release delete "$tag" --repo "$REPO" --cleanup-tag --yes
    git tag -d "$tag" 2>/dev/null || true
else
    version="${1:?usage: scripts/release.sh VERSION | redo}"
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version '$version' is not MAJOR.MINOR.PATCH"
    tag="v$version"
    git rev-parse -q --verify "refs/tags/$tag" > /dev/null && die "$tag already exists; use redo"
fi

git tag "$tag" "$head"
git push -q origin "$tag"
echo "release: pushed $tag; follow it with: gh run watch --repo $REPO"
