#!/bin/bash
# Assert that every file Ovation ported from a sibling repository records where
# it came from, and that the commit it names is still on that sibling's main.
#
# Implementation plan 0.4.6. Ovation ports at least eleven files one line at a
# time from Downbeat and Overture. A clone copies the pattern AS FIRST WRITTEN,
# including every value already corrected in the original, and the clone's own
# note that it follows a proven pattern is what makes it read as safe (L501). A
# port made from a stale checkout or an unmerged branch is therefore reported
# here rather than assumed.
#
# Every ported file carries, at the START of a comment line, in its own comment
# syntax ('#' for shell, yaml and gitignore, '//' for Swift):
#
#      <comment opener><space>Ported<dash>From: <owner>/<repo> <path> @ <commit>
#
# The marker is written with <dash> there on purpose. THIS SCRIPT HAS TO NAME ITS
# OWN NEEDLE IN ORDER TO SEARCH FOR IT, so an unescaped example here would make
# the check match itself, its own test, and every document describing the
# convention (L245). Measured on the first real run: seven bogus artifacts, all
# of them this file and its test.
#
# The remedy is the RULE, not a list of exempt filenames (L362). A real header
# sits at the start of its comment; prose about one is indented inside a block.
# So the match is anchored to allow at most one space after the comment opener,
# which no explanatory paragraph satisfies.
#
# Outcomes, one per artifact, each with its own wording because distinct causes
# need distinct messages (L11):
#
#     OK                  the commit is an ancestor of that sibling's main
#     NOT ON MAIN         the sibling was found, the commit is not on its main
#     COMMIT NOT FOUND    the sibling was found, the commit is not in it at all
#     CANNOT MEASURE      the sibling repository is not on this machine
#     UNREADABLE HEADER   a Ported-From line that cannot be parsed
#
# Exit codes, so a caller can tell them apart without parsing text:
#
#     0  every artifact verified, and there was at least one
#     1  at least one NOT ON MAIN
#     2  at least one CANNOT MEASURE or COMMIT NOT FOUND
#     3  no ported artifacts found at all
#     4  at least one UNREADABLE HEADER
#
# NOTHING FOUND IS NOT A PASS. Ovation has zero ported files on the day this is
# written, and a check that exits 0 on an empty tree would report success for
# months and be believed by the time it mattered (L98, L182). CANNOT MEASURE is
# not a pass either, for the same reason: a checker that goes green because it
# could not find what it was meant to check is indistinguishable from one that
# checked everything.
#
# Seams, so the test suite never reads a real sibling repository (L2):
#     OVATION_PORT_SCAN_ROOT         where to look for ported files
#     OVATION_SIBLING_SEARCH_ROOTS   colon separated roots to resolve siblings in
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN_ROOT="${OVATION_PORT_SCAN_ROOT:-$REPO_ROOT}"
DEFAULT_ROOTS="$HOME/Non-icloudDocuments/Apps:$HOME/Non-icloudDocuments/Photography Assets/Dan Wright Photography/Marketing/Outreach:$HOME/Documents"
SEARCH_ROOTS="${OVATION_SIBLING_SEARCH_ROOTS:-$DEFAULT_ROOTS}"

# Assembled from pieces so this file contains no literal instance of the marker
# it looks for. One definition, used by both the file search and the line
# extraction, so the two can never drift into looking for different things (L70).
MARKER="Ported""-From:"
HEADER_RE="^[[:space:]]*(#|//)[[:space:]]?${MARKER}"

if [ ! -d "$SCAN_ROOT" ]; then
    echo "CANNOT MEASURE: the scan root does not exist: $SCAN_ROOT"
    exit 2
fi

# ASKING ANOTHER REPOSITORY ABOUT ITSELF NEEDS MORE THAN `git -C`. An inherited
# GIT_DIR BEATS the -C, so every question below would be answered by whatever
# GIT_DIR names, which is this repository. That is not a hypothetical: git
# EXPORTS GIT_DIR to its hooks, and this check runs in the pre-push hook.
#
# From the primary checkout it survived by luck, because git sets the relative
# `.git` there and a relative GIT_DIR beside `-C /path/to/sibling` resolves to
# the sibling's own .git. From a WORKTREE it is an absolute path, every sibling
# answers with Ovation's own origin, matches no slug, and is reported as not
# being on this machine while sitting right there. A push was refused for nine
# unmeasurable ports on 2026-09-08 with all nine siblings present, and the same
# command passed by hand, which is what pointed at the environment.
#
# So every call goes through here. One definition, so a call site added later
# cannot quietly be the one that reads the wrong repository (L70, L621).
sibling_git() {
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY \
        -u GIT_COMMON_DIR -u GIT_NAMESPACE git "$@"
}

# Resolve <owner>/<repo> to a local checkout by asking each candidate what its
# origin actually is, rather than matching on directory name. Overture's checkout
# is not called "overture", so a name match would miss it, and a directory that
# merely shares a name is not the same repository (L15).
resolve_sibling() {
    local slug="$1" root candidate url
    local IFS=:
    for root in $SEARCH_ROOTS; do
        [ -d "$root" ] || continue
        while IFS= read -r candidate; do
            url="$(sibling_git -C "$candidate" remote get-url origin 2>/dev/null)" || continue
            case "$url" in
                *"$slug".git|*"$slug"|*"$slug"/) printf '%s\n' "$candidate"; return 0 ;;
            esac
        done < <(find "$root" -maxdepth 3 -type d -name .git -not -path '*/.claude/*' 2>/dev/null | sed 's|/\.git$||')
    done
    return 1
}

# The branch the port has to be on. Prefer the local main, fall back to the
# remote tracking one, and refuse rather than guess if neither is there.
main_ref() {
    local repo="$1"
    for ref in main origin/main; do
        if sibling_git -C "$repo" rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
            printf '%s\n' "$ref"; return 0
        fi
    done
    return 1
}

found=0
not_on_main=0
# TWO KINDS OF CANNOT MEASURE (ovation#135). A sibling that is not on this
# machine is a question nothing here could ever have answered, and every fresh
# clone, second machine and CI runner is in that state. A sibling that IS here
# and cannot answer is a fault on this machine. The gate lets the first through
# while naming it and refuses the second, which it cannot do while they share one
# code (L11, L260).
sibling_absent=0
cannot_measure=0
unreadable=0

# Nested checkouts hold a full second copy of a repository's sources, and a
# recursive walk collects them (L234). Overture's .claude/worktrees proves they
# exist in this estate.
while IFS= read -r file; do
    while IFS= read -r line; do
        found=$((found+1))
        spec="${line#*$MARKER}"
        # shellcheck disable=SC2086
        set -- $spec
        slug="${1:-}"; path="${2:-}"; at="${3:-}"; commit="${4:-}"
        rel="${file#$SCAN_ROOT/}"
        if [ "$#" -ne 4 ] || [ "$at" != "@" ] || [ -z "$slug" ] || [ -z "$path" ] \
           || ! printf '%s' "$slug" | grep -q '^[^/][^/]*/[^/][^/]*$' \
           || ! printf '%s' "$commit" | grep -qi '^[0-9a-f]\{7,40\}$'; then
            echo "UNREADABLE HEADER: $rel"
            echo "    could not read a repository, path and commit out of: ${spec# }"
            unreadable=$((unreadable+1))
            continue
        fi
        if ! sibling="$(resolve_sibling "$slug")"; then
            echo "CANNOT MEASURE: $rel"
            echo "    the sibling repository $slug is not on this machine"
            echo "    roots searched: $SEARCH_ROOTS"
            sibling_absent=$((sibling_absent+1))
            continue
        fi
        if ! ref="$(main_ref "$sibling")"; then
            echo "CANNOT MEASURE: $rel"
            echo "    $slug has neither a main nor an origin/main to compare against"
            cannot_measure=$((cannot_measure+1))
            continue
        fi
        if ! sibling_git -C "$sibling" cat-file -e "${commit}^{commit}" 2>/dev/null; then
            echo "COMMIT NOT FOUND: $rel"
            echo "    $slug does not contain $commit, so the port cannot be placed"
            cannot_measure=$((cannot_measure+1))
            continue
        fi
        if sibling_git -C "$sibling" merge-base --is-ancestor "$commit" "$ref" 2>/dev/null; then
            echo "OK: $rel  ($slug $path @ ${commit:0:8})"
        else
            echo "NOT ON MAIN: $rel"
            echo "    $slug $path @ ${commit:0:8} is not an ancestor of $ref"
            echo "    it was ported from a branch or a checkout that never merged"
            not_on_main=$((not_on_main+1))
        fi
    done < <(grep -hE "$HEADER_RE" "$file" 2>/dev/null)
done < <(grep -rlE "$HEADER_RE" "$SCAN_ROOT" \
            --exclude-dir=.git --exclude-dir=worktrees --exclude-dir=node_modules \
            --exclude-dir=DerivedData --exclude-dir=build 2>/dev/null | sort)

echo
if [ "$found" -eq 0 ]; then
    echo "NO PORTED ARTIFACTS found under $SCAN_ROOT."
    echo "Nothing was examined, so nothing was verified. This is the expected"
    echo "answer only until the first port lands; after that it means a"
    echo "Ported-From header has been lost."
    exit 3
fi

echo "examined $found ported artifact(s): $((found - not_on_main - cannot_measure - unreadable - sibling_absent)) ok, $not_on_main not on main, $sibling_absent not on this machine, $cannot_measure unmeasurable, $unreadable unreadable"
[ "$not_on_main" -gt 0 ] && exit 1
# 4 BEFORE 2: a run that must be refused cannot be softened by an unrelated
# question nothing on this machine could have answered.
[ "$unreadable" -gt 0 ] && exit 4
[ "$cannot_measure" -gt 0 ] && exit 4
[ "$sibling_absent" -gt 0 ] && exit 2
exit 0
