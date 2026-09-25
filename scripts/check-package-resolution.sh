#!/bin/bash
# Refuse when the package resolution on disk is not the one HEAD commits.
#
#     check-package-resolution.sh
#
# ovation#421. SwiftPM records the revision every package resolved to in
# `Package.resolved`, which it writes INSIDE the generated project. `.gitignore`
# excluded that whole directory, so no resolved revision existed anywhere in
# version control. An exact version resolves a TAG, and a tag is a movable ref,
# so a re-cut tag would have moved the build with no diff anywhere (L25, L496).
# The file is now committed at the path SwiftPM writes it to, which is what
# Overture does by committing its whole project.
#
# COMMITTING IT IS HALF OF THE ANSWER, AND THIS IS THE OTHER HALF (L422). A build
# that resolves differently REWRITES the tracked file and goes on building, and a
# rewritten tracked file is only a line in `git status` nobody is made to read.
# So this compares the file on disk, which is what the last build resolved, with
# the file HEAD commits, and refuses on any difference. build-products.sh asks it
# after both builds, which makes it CI's question too, and the push gate asks it
# before a push, where a resolution moved on this Mac and not committed would
# otherwise leave the suite judging code against packages CI will not use.
#
# IT COMPARES AGAINST HEAD, never the index. A push sends commits, and CI builds
# what was committed, so a resolution that is only staged is still not the one
# the build it predicts will use.
#
# WHAT IT PRINTS is package identities, versions and short revisions, never a
# line of the file, and never a package location, which is a URL (L222). Every
# refusal names both remedies, and the suite runs each of them (L406): commit a
# move made on purpose, or put the committed resolution back.
#
# Exit codes, one per outcome (L11):
#
#     0  the resolution on disk is the one HEAD commits
#     1  it is not: it differs, it is missing from disk, or HEAD commits none
#     2  cannot measure: not a git work tree, or no python3 to read the files
#
# Seam: OVATION_REPO_ROOT.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${OVATION_REPO_ROOT:-$(dirname "${HERE}")}"
RESOLVED="Ovation.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

if ! git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "CANNOT MEASURE: ${REPO_ROOT} is not a git work tree, so there is no committed" >&2
    echo "                package resolution to compare the one on disk with." >&2
    exit 2
fi

if ! git -C "${REPO_ROOT}" cat-file -e "HEAD:${RESOLVED}" 2>/dev/null; then
    echo "REFUSED: HEAD commits no package resolution at ${RESOLVED}," >&2
    echo "         so nothing records which revision each package resolved to, and a" >&2
    echo "         tag moved under an exact version would move the build unseen (ovation#421)." >&2
    echo "         Build once, then commit the file the build wrote:" >&2
    echo "             git add -- ${RESOLVED}" >&2
    exit 1
fi

REMEDIES="         If the move was made on purpose (a version changed in project.yml), commit it:
             git add -- ${RESOLVED}
             git commit
         If it was not, put the committed resolution back and build again:
             git checkout HEAD -- ${RESOLVED}"

if [ ! -f "${REPO_ROOT}/${RESOLVED}" ]; then
    echo "REFUSED: HEAD commits a package resolution and there is none on disk at" >&2
    echo "         ${RESOLVED}. The next build would resolve every package" >&2
    echo "         afresh, which is the floating the committed file exists to end." >&2
    echo "         Put the committed one back:" >&2
    echo "             git checkout HEAD -- ${RESOLVED}" >&2
    exit 1
fi

# COMPARED BYTE FOR BYTE, through cmp, because a command substitution strips
# trailing newlines and would call two different files the same.
if cmp -s <(git -C "${REPO_ROOT}" show "HEAD:${RESOLVED}") "${REPO_ROOT}/${RESOLVED}"; then
    echo "OK: the package resolution on disk is the one HEAD commits (${RESOLVED})."
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "CANNOT MEASURE: the package resolution on disk differs from the one HEAD commits," >&2
    echo "                and there is no python3 to say which package moved." >&2
    exit 2
fi

# WHICH PACKAGE MOVED, AND HOW. Read as JSON, keyed on the package identity,
# because the pin order is SwiftPM's and a moved line says nothing on its own.
# A file that is not JSON at all is reported as that rather than as a crash.
MOVES="$(git -C "${REPO_ROOT}" show "HEAD:${RESOLVED}" | python3 -B -c '
import json, sys
def pins(text):
    try:
        data = json.loads(text)
        return {p["identity"]: p for p in data.get("pins", [])}, data.get("originHash")
    except (ValueError, KeyError, TypeError, AttributeError):
        return None, None
committed, committed_origin = pins(sys.stdin.read())
with open(sys.argv[1]) as f:
    resolved, resolved_origin = pins(f.read())
if committed is None or resolved is None:
    which = "HEAD commits" if committed is None else "is on disk"
    print("    the resolution that %s is not a readable Package.resolved" % which)
    sys.exit(0)
def state(pin):
    s = pin.get("state", {})
    return "%s at %s" % (s.get("version") or s.get("branch") or "no version", (s.get("revision") or "no revision")[:7])
for identity in sorted(set(committed) | set(resolved)):
    if identity not in resolved:
        print("    %s: committed at %s, and not resolved by the build" % (identity, state(committed[identity])))
    elif identity not in committed:
        print("    %s: resolved at %s, and not in the committed resolution" % (identity, state(resolved[identity])))
    elif committed[identity].get("state") != resolved[identity].get("state"):
        print("    %s: committed at %s, resolved at %s" % (identity, state(committed[identity]), state(resolved[identity])))
    elif committed[identity].get("location") != resolved[identity].get("location"):
        print("    %s: resolved from a different location than the committed one" % identity)
if committed_origin != resolved_origin:
    print("    the package requirements it was resolved against changed (originHash)")
' "${REPO_ROOT}/${RESOLVED}")"
PY_STATUS=$?
if [ "${PY_STATUS}" -ne 0 ]; then
    echo "CANNOT MEASURE: the package resolution on disk differs from the one HEAD commits," >&2
    echo "                and reading the two to say which package moved failed (python3 exited ${PY_STATUS})." >&2
    exit 2
fi

echo "REFUSED: the package resolution on disk is not the one HEAD commits," >&2
echo "         at ${RESOLVED}." >&2
if [ -n "${MOVES}" ]; then
    printf '%s\n' "${MOVES}" >&2
else
    echo "    no package moved: the two differ only in layout, and the file on disk is" >&2
    echo "    still a tracked file that no longer matches what HEAD commits." >&2
fi
printf '%s\n' "${REMEDIES}" >&2
exit 1
