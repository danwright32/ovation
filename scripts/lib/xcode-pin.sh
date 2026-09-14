#!/bin/bash
# The one reader of the Xcode this repository builds with. ovation#270.
#
# Both Mac jobs in .github/workflows/ci.yml built with whatever Xcode the runner
# image shipped as its default, and nothing named a version, so an image update
# could move the compiler with no change in this repository and the push gate on
# Dan's Mac would stop predicting CI without anybody being told (L25, L376).
#
# THE VERSION IS RECORDED ONCE, in .xcode-version at the repository root, and TWO
# things read it: scripts/select-xcode.sh, which makes CI build with it, and
# scripts/run-tests.sh, which says when this Mac builds with something else. The
# file and the reading of it are shared, because a second parser beside the
# first is how "26.6" in one place and "26.6.0" in the other come to disagree
# while each reads as correct (L370).
#
# Sourced, never run.

# xcode_pin_read <pin file>
#
# Prints the pinned version and succeeds. Returns 1 when the file is not there,
# and 2 when its first line is not a version number, printing nothing in either
# case: the pin is text a person typed, and every caller prints into a log
# (L222), so a malformed pin is described by the shape it should have and never
# quoted back.
xcode_pin_read() {
    local file="$1" version
    [ -f "$file" ] || return 1
    version="$(head -n 1 "$file" | tr -d '[:space:]')"
    printf '%s' "$version" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$' || return 2
    printf '%s' "$version"
}

# xcode_active_version <xcodebuild>
#
# Prints the version the given xcodebuild reports, from its own first line
# (`Xcode 26.6`), and succeeds. Returns 1 when it cannot be run or says something
# else, because a version that could not be read must never compare equal to
# anything (L50).
xcode_active_version() {
    local out version
    out="$("$1" -version 2>/dev/null)" || return 1
    version="$(printf '%s\n' "$out" | sed -n '1s/^Xcode \([0-9][0-9.]*\)$/\1/p')"
    [ -n "$version" ] || return 1
    printf '%s' "$version"
}
