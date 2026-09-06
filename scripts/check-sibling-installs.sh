#!/bin/bash
# Are the two sibling apps Ovation depends on actually the builds it needs?
#
# ovation#3, plan 0.2.0 and 0.2. Ovation reads what Downbeat writes, and both of
# those facts live outside this repository:
#
#   1. The installed OVERTURE must contain the widened version gate bdd85404.
#      Overture decodes the whole export file or none of it, so an Overture
#      without that fix refuses a version 3 export outright and loses its client
#      roster. It must also have come from main, because a build from a branch
#      is a build nobody can say the contents of.
#
#   2. The installed DOWNBEAT must be writing a version 3 export, which is the
#      one that carries shoot times. Read from the export it produced rather
#      than from Downbeat's own record of itself, because that is the artifact
#      Ovation actually consumes (L58: two systems that must agree cannot be
#      verified against records one of them wrote into the other).
#
# A value read once at startup is only true at startup, and when the thing it
# describes lives OUTSIDE the program there is no action inside the program to
# hang a re-read on, so it goes stale invisibly (L175). That is not theoretical
# here: the plan and the custody note both described these installs in the future
# tense for a week after they had happened. This script is the re-read.
#
# THREE OUTCOMES, KEPT APART:
#
#   0  PASS           both facts measured and both hold
#   1  BLOCKED        a fact was measured and is wrong
#   2  CANNOT MEASURE the fact could not be read at all
#
# CANNOT MEASURE is not a pass and not a failure (L11, L98, L260). A missing
# installed-build.json says nothing about which build is installed, and calling
# that either answer invents a measurement nobody took.
#
# PRIVACY FLOOR. The export carries real client and venue names. This script
# prints versions, counts, commits and field names, never a value out of it. A
# guard that scans the REPOSITORY cannot see what a tool prints, and printed
# output reaches terminal scrollback and transcripts by a route that guard never
# inspects (L222).
set -uo pipefail

SUPPORT="${HOME}/Library/Application Support"
RECORD="${OVATION_OVERTURE_BUILD_RECORD:-${SUPPORT}/Overture/installed-build.json}"
EXPORT_FILE="${OVATION_DOWNBEAT_EXPORT:-${SUPPORT}/Overture/downbeat-export.json}"
REPO="${OVATION_OVERTURE_REPO:-${HOME}/Non-icloudDocuments/Photography Assets/Dan Wright Photography/Marketing/Outreach/Overture}"
# The commit that widened Overture's version gate from an equality to a minimum.
GATE="${OVATION_OVERTURE_GATE_COMMIT:-bdd85404}"
# The export version Ovation needs. Downbeat's OvertureExportBuilder.formatVersion.
WANT_VERSION="${OVATION_EXPORT_VERSION:-3}"

cannot_measure() {
    echo "CANNOT MEASURE: $1"
    [ "${2:-}" = "" ] || echo "    $2"
    echo "    Nothing was verified. This is not a pass."
    exit 2
}
blocked() {
    echo "BLOCKED: $1"
    [ "${2:-}" = "" ] || echo "    $2"
    exit 1
}

# ---------------------------------------------------------------------------
# OVERTURE
# ---------------------------------------------------------------------------
[ -f "$RECORD" ] || cannot_measure \
    "there is no Overture installed-build.json at the recorded path" \
    "it is written by Overture's mac/build-install.sh; reinstall Overture, or correct the path"

# PARSED BY CONVERTING IT, not by `plutil -lint`. Measured 2026-09-06: `-lint`
# reports "Unexpected character {" on the very JSON that `plutil -extract` reads
# without complaint, so the tool named for the job is the wrong one here and
# using it made every healthy record read as corrupt.
readable_json() { plutil -convert xml1 -o /dev/null -- "$1" >/dev/null 2>&1; }

readable_json "$RECORD" || cannot_measure \
    "Overture's installed-build.json is not readable as JSON" \
    "it may have been written by a failed install; reinstall Overture"

# Each field is asked for BY NAME and refused BY NAME. One shared message here
# would let a missing field answer for a missing file, and the two need
# different actions (L11).
INSTALLED="$(plutil -extract commit raw -o - "$RECORD" 2>/dev/null)" || INSTALLED=""
[ -n "$INSTALLED" ] || cannot_measure \
    "Overture's installed-build.json has no 'commit' field" \
    "the record predates that field, or the install did not finish; reinstall Overture"

PROVENANCE="$(plutil -extract provenance raw -o - "$RECORD" 2>/dev/null)" || PROVENANCE=""
[ -n "$PROVENANCE" ] || cannot_measure \
    "Overture's installed-build.json has no 'provenance' field" \
    "the record predates that field, or the install did not finish; reinstall Overture"

[ -d "$REPO/.git" ] || cannot_measure \
    "the Overture checkout is not where it is recorded to be" \
    "set OVATION_OVERTURE_REPO to where it is now, and correct the path in this script"

# ANCESTRY IS ASKED OF THE REPOSITORY, not inferred from dates or from the
# commit strings looking different. Read only: nothing here checks anything out,
# because the checkout may be shared with a session that is working in it.
git -C "$REPO" cat-file -e "${INSTALLED}^{commit}" 2>/dev/null || cannot_measure \
    "the installed Overture commit ${INSTALLED:0:8} is not in that checkout" \
    "it was built from a clone this one has never fetched, so its contents cannot be established here"
git -C "$REPO" cat-file -e "${GATE}^{commit}" 2>/dev/null || cannot_measure \
    "the gate commit ${GATE:0:8} is not in that checkout" \
    "fetch Overture, or correct OVATION_OVERTURE_GATE_COMMIT"

if ! git -C "$REPO" merge-base --is-ancestor "$GATE" "$INSTALLED" 2>/dev/null; then
    blocked "the installed Overture ${INSTALLED:0:8} does not contain the version gate fix ${GATE:0:8}" \
        "it will refuse a version ${WANT_VERSION} export outright and lose its roster; reinstall Overture from main first"
fi

if [ "$PROVENANCE" != "main" ]; then
    blocked "the installed Overture came from '${PROVENANCE}', not main" \
        "a build from a branch is a build whose contents nobody can state; reinstall from main"
fi

# ---------------------------------------------------------------------------
# DOWNBEAT, judged by the artifact it produced rather than by its own record.
# ---------------------------------------------------------------------------
[ -f "$EXPORT_FILE" ] || cannot_measure \
    "there is no Downbeat export at the recorded path" \
    "launch Downbeat once, which rewrites it, or correct the path"

readable_json "$EXPORT_FILE" || cannot_measure \
    "the Downbeat export is not readable as JSON" \
    "it may have been caught mid write; launch Downbeat again and re-run this"

VERSION="$(plutil -extract version raw -o - "$EXPORT_FILE" 2>/dev/null)" || VERSION=""
[ -n "$VERSION" ] || cannot_measure \
    "the Downbeat export has no 'version' field" \
    "it was written by a build older than the format itself; reinstall Downbeat"

if [ "$VERSION" != "$WANT_VERSION" ]; then
    blocked "the Downbeat export is version ${VERSION}, not ${WANT_VERSION}" \
        "version ${WANT_VERSION} is the one carrying shoot times; reinstall Downbeat"
fi

# The verdict NAMES WHAT IT MEASURED, so a reader can tell it apart from a run
# that measured nothing and said nothing (L98). Commits are abbreviated and no
# value out of the export is printed.
echo "PASS: the installed Overture ${INSTALLED:0:8} (from ${PROVENANCE}) contains the gate fix ${GATE:0:8}"
echo "      and the Downbeat export is version ${VERSION}"
exit 0
