#!/bin/bash
# Whether the Xcode this repository pins is still the newest CI's image offers.
#
# ovation#320. Xcode updated itself on Dan's Mac to 27.0 and the pinned 26.6 is
# no longer installed here, so the push gate stopped predicting CI. Measured
# 2026-09-16: macos-26, the image both Mac jobs run on, carries 26.0.1 up to 26.6
# and nothing newer, and the only published image with an Xcode 27 is a public
# preview on a newer macOS whose Xcode is a BETA build (27A5252f) against the
# release build this Mac has (27A266a). There is no version both sides can hold,
# so the decision taken was to wait with the mismatch named.
#
# THIS IS WHAT MAKES THE WAITING END. A suppression with no expiry is a decision
# nobody revisits (L523), and the premise under it, that the image has no newer
# Xcode, is exactly the kind that expires without a symptom (L316). So it is
# re-measured on a schedule rather than argued about once.
#
# IT IS NOT WRITTEN TO LOOK FOR XCODE 27. A check keyed on the version wanted
# today is a one-shot that goes silent for ever once it fires (L637). The
# question is "does the image offer an Xcode newer than the pin", which is the
# same question when 26.7 appears and nobody has been told to bump the pin.
#
# AND IT WATCHES THE OTHER DIRECTION, which is the one that actually breaks
# things. Runner images keep only the newest patch of each version, so the day
# the image replaces 26.6 the CI build REFUSES by scripts/select-xcode.sh, with
# no warning first. That has its own outcome here because it is not an
# opportunity, it is an outage due shortly (L11).
#
# RUN BY THE WORKFLOW AND BY A PERSON. It reads and prints, and changes nothing:
# the name says it inspects, and a name that reads like an inspection must not
# write (L206). Correcting the pin stays a person's decision, because which
# version to move to is a choice about the compiler, not arithmetic.
#
# FIVE OUTCOMES, one per exit code, each with its own sentence (L11, L184):
#
#   0  the pin is the newest Xcode the image offers. Nothing to do
#   1  REFUSED: the workflow names more than one Mac runner, so "the image CI
#      builds on" has no single answer and none is guessed
#   2  CANNOT MEASURE: the pin, the workflow or the manifest could not be read,
#      or the manifest carried no Xcode table. Never reported as healthy
#   3  the image offers an Xcode NEWER than the pin
#   4  the image no longer offers the PINNED Xcode at all, so the CI build is
#      about to refuse. Takes precedence over 3, which is usually also true
#
# Seams, so its suite reaches no network and no real workflow (L2, L291):
#
#   OVATION_XCODE_VERSION_FILE       the pin, defaulting to .xcode-version
#   OVATION_CI_WORKFLOW              the workflow the runner label is read from
#   OVATION_RUNNER_MANIFEST_COMMAND  a command given a manifest file name, which
#                                    prints that manifest. Defaults to fetching
#                                    it from the runner-images repository
set -uo pipefail
# ovation#399: every library is loaded through require_lib, which refuses by name
# rather than carrying on without it. See scripts/lib/require.sh.
. "$(dirname "${BASH_SOURCE[0]}")/lib/require.sh" 2>/dev/null || { echo "REFUSED: scripts/lib/require.sh is missing, so nothing was checked." >&2; exit 2; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/xcode-pin.sh
require_lib "$REPO_ROOT/scripts/lib/xcode-pin.sh"

PIN_FILE="${OVATION_XCODE_VERSION_FILE:-$REPO_ROOT/.xcode-version}"
WORKFLOW="${OVATION_CI_WORKFLOW:-$REPO_ROOT/.github/workflows/ci.yml}"
FETCH_COMMAND="${OVATION_RUNNER_MANIFEST_COMMAND:-}"
MANIFEST_BASE="https://raw.githubusercontent.com/actions/runner-images/main/images/macos"

# THE COMPARISON IS NUMERIC, PER COMPONENT. This is the whole check: 26.10 is
# newer than 26.9 and sorts EARLIER as text, so a string comparison would report
# the healthy day for ever while a newer Xcode sat on the image. `sort -V` is not
# used because it is a GNU extension this suite would then depend on differently
# on Dan's Mac and on the Linux runner (L434).
version_gt() {
    local i ac bc
    local -a A B
    IFS=. read -r -a A <<< "$1"
    IFS=. read -r -a B <<< "$2"
    for (( i = 0; i < ${#A[@]} || i < ${#B[@]}; i++ )); do
        # A MISSING COMPONENT IS ZERO, so 26.6 and 26.6.0 are the same version
        # rather than one being newer, which is how the runner image writes the
        # same Xcode in two places.
        ac=$(( 10#${A[i]:-0} ))
        bc=$(( 10#${B[i]:-0} ))
        [ "$ac" -gt "$bc" ] && return 0
        [ "$ac" -lt "$bc" ] && return 1
    done
    return 1
}

version="$(xcode_pin_read "$PIN_FILE")"
case $? in
    0) ;;
    1)
        echo "CANNOT MEASURE: there is no Xcode pin at $PIN_FILE."
        echo "    Nothing was compared. The pin is one line holding a version, like 26.6."
        exit 2
        ;;
    *)
        # NOT QUOTED. The pin is text a person typed and this prints into a public
        # log (L222); the shape it should have is the remedy (L399).
        echo "CANNOT MEASURE: $PIN_FILE does not hold a version number like 26.6."
        echo "    Nothing was compared."
        exit 2
        ;;
esac

if [ ! -f "$WORKFLOW" ]; then
    echo "CANNOT MEASURE: the CI workflow is not at $WORKFLOW."
    echo "    The runner image is read from there rather than written here a second"
    echo "    time, so without it there is nothing to ask GitHub about (L41)."
    exit 2
fi

# THE LABEL IS DERIVED, NEVER TYPED HERE. A copy of `macos-26` in this file is a
# list maintained by hand beside the source of truth, and the two drift with no
# symptom: this check would go on reporting confidently about an image CI had
# stopped using (L41).
labels="$(grep -oE '^[[:space:]]*runs-on:[[:space:]]*[A-Za-z0-9._-]+' "$WORKFLOW" \
    | sed -E 's/.*runs-on:[[:space:]]*//' | grep '^macos-' | sort -u)"

if [ -z "$labels" ]; then
    echo "CANNOT MEASURE: no job in $(basename "$WORKFLOW") has a runs-on naming a macOS runner."
    echo "    Nothing builds Ovation on a Mac there, so there is no image whose Xcode"
    echo "    could be compared with the pin. If the Mac jobs moved, this check moves"
    echo "    with them rather than keeping a runner name of its own."
    exit 2
fi

count="$(printf '%s\n' "$labels" | wc -l | tr -d ' ')"
if [ "$count" -ne 1 ]; then
    # MANY IS ITS OWN REFUSAL, never the first one (L521). Two Mac jobs on two
    # images means "the image CI builds on" has no answer, and reporting about
    # whichever sorted first would leave the other drifting unwatched.
    echo "REFUSED: $(basename "$WORKFLOW") names more than one macOS runner, so there is no"
    echo "    single image to compare the pin against. It names:"
    printf '%s\n' "$labels" | sed 's/^/        /'
    echo "    Nothing was compared. Either the jobs should share one runner, or this"
    echo "    check should be told which of them the pin is for."
    exit 1
fi
label="$labels"

# THE ARM64 MANIFEST FIRST, because that is what the label provisions now, and the
# plain one as a FALLBACK rather than an alternative: reaching the wrong one
# silently would compare against an image nothing runs on. Both names are tried
# before giving up, and the failure names both (L173).
manifest=""
tried=""
for name in "${label}-arm64-Readme.md" "${label}-Readme.md"; do
    tried="${tried}${name} "
    if [ -n "$FETCH_COMMAND" ]; then
        manifest="$("$FETCH_COMMAND" "$name" 2>/dev/null)"
    else
        manifest="$(curl -sS --fail --max-time 30 "${MANIFEST_BASE}/${name}" 2>/dev/null)"
    fi
    [ -n "$manifest" ] && break
    manifest=""
done

if [ -z "$manifest" ]; then
    echo "CANNOT MEASURE: could not read what the ${label} image contains."
    echo "    Tried: ${tried% }"
    echo "    from ${MANIFEST_BASE}."
    echo "    Nothing was compared. A fetch that failed is not an image with no"
    echo "    newer Xcode on it (L98)."
    exit 2
fi

# THE XCODE TABLE ONLY, and the reading stops at the next heading rather than at
# the end of the file. Today that costs nothing: the section below the Xcode table
# is Installed SDKs, whose first column reads "macOS 26.0" and matches no version,
# and reading the whole file gives the same seven Xcodes (measured 2026-09-16
# against the published macos-26 manifest). It is here for the manifest whose
# shape changes, because the failure would be silent and in the reassuring
# direction: a stray version anywhere below would become the newest Xcode the
# image offers. Its suite traps it with a table the real manifest does not have,
# and says so, since a guard nothing can make fail is not a guard (L1).
offered="$(printf '%s\n' "$manifest" | awk '
    /^#+[[:space:]]*Xcode[[:space:]]*$/ { inside = 1; next }
    inside && /^#/ { exit }
    inside && /^\|/ {
        split($0, cells, "|")
        v = cells[2]
        gsub(/\(default\)|\(beta\)/, "", v)
        gsub(/[[:space:]]/, "", v)
        if (v ~ /^[0-9]+\.[0-9]+(\.[0-9]+)?$/) print v
    }
')"

if [ -z "$offered" ]; then
    echo "CANNOT MEASURE: the ${label} manifest was read and carried no Xcode table."
    echo "    Nothing was compared. A manifest whose shape changed looks exactly like"
    echo "    an image with no Xcode newer than the pin, and those must not be the"
    echo "    same answer (L98)."
    exit 2
fi

newest=""
holds_pin="no"
while read -r candidate; do
    [ -n "$candidate" ] || continue
    [ "$candidate" = "$version" ] && holds_pin="yes"
    if [ -z "$newest" ] || version_gt "$candidate" "$newest"; then
        newest="$candidate"
    fi
done <<< "$offered"

list_offered() { printf '%s\n' "$offered" | sed 's/^/        /'; }

# THE PINNED VERSION BEING GONE COMES FIRST. When the image has dropped it, it has
# almost always gained something newer too, and reporting that instead would
# describe an upgrade nobody has to make while the build that is about to fail
# went unmentioned.
if [ "$holds_pin" = "no" ]; then
    echo "The ${label} image no longer offers Xcode ${version}, which .xcode-version pins."
    echo "    scripts/select-xcode.sh will refuse on the next CI run, and both Mac jobs"
    echo "    will stop before they build. This is not an upgrade going spare: it is a"
    echo "    red CI that has not happened yet."
    echo "    ${label} now offers:"
    list_offered
    echo "    The fix is one line in .xcode-version, naming one of the versions above."
    exit 4
fi

if version_gt "$newest" "$version"; then
    echo "The ${label} image now offers Xcode ${newest}, newer than the pinned ${version}."
    echo "    ${label} offers:"
    list_offered
    echo "    Ovation pins ${version} because that was the newest the image had when the"
    echo "    pin was last set. If ${newest} is also the Xcode this Mac builds with, moving"
    echo "    the pin closes the gap ovation#320 recorded and retires the note the test"
    echo "    runner prints. Check what this Mac has with xcodebuild -version first:"
    echo "    a pin nothing here can select trades one mismatch for another."
    exit 3
fi

echo "Xcode ${version} is the newest the ${label} image offers, so the pin is current."
echo "    ${label} offers:"
list_offered
exit 0
