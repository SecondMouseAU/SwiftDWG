#!/usr/bin/env bash
# check-reader-version.sh: fail unless `DWG.readerVersion` equals the given release tag.
#
# `DWG.readerVersion` (Sources/SwiftDWG/DWG+ReaderVersion.swift) is the release's own version, kept
# by a consumer as a record of which release read a drawing. It is only a record if it equals the
# tag the package is resolved at. A constant cannot know its own tag, so the check runs where the
# tag exists: the `release-version` workflow calls this on every release tag, and a maintainer can
# call it before tagging.
#
# It reads the constant from the source text, so it needs no Swift toolchain.
#
# Usage:
#   Scripts/check-reader-version.sh 0.3.0     # the tag about to be made, or the tag just made
#   Scripts/check-reader-version.sh           # print the constant, no check
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
file="$root/Sources/SwiftDWG/DWG+ReaderVersion.swift"

[ -f "$file" ] || { echo "FAIL: $file not found" >&2; exit 1; }

declared="$(sed -n 's/^ *public static let readerVersion = "\([^"]*\)"$/\1/p' "$file")"

if [ -z "$declared" ]; then
    echo "FAIL: no 'public static let readerVersion = \"...\"' line in $file" >&2
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "$declared"
    exit 0
fi

tag="${1#refs/tags/}"

if [ "$declared" != "$tag" ]; then
    echo "FAIL: DWG.readerVersion is \"$declared\" but the tag is \"$tag\"." >&2
    echo "Set it to \"$tag\" in Sources/SwiftDWG/DWG+ReaderVersion.swift, merge, and tag that commit." >&2
    exit 1
fi

echo "OK: DWG.readerVersion and the tag are both $tag"
