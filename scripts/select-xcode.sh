#!/bin/bash
# Make this machine build with the Xcode .xcode-version names, or stop by name.
#
# ovation#270. Both Mac jobs in .github/workflows/ci.yml built with whatever Xcode
# the runner image shipped as its default, and nothing named a version. An image
# update could move the compiler with no change in this repository, the push gate
# on Dan's Mac would stop predicting CI, and a CI log did not even say which
# Xcode it had used (L25, L376).
#
# RUN BY THE WORKFLOW, NEVER BY A PERSON OR THE PUSH GATE. It changes which Xcode
# the whole machine builds with and it needs sudo, which is right on an ephemeral
# runner and wrong on Dan's Mac. That is also why it is not called check-: a name
# that reads like an inspection must not change anything (L206).
#
# THREE OUTCOMES:
#
#   0  the pinned Xcode was selected, and xcodebuild now reports that version
#   1  REFUSED: the pinned Xcode is not on this machine, or selecting it did not
#      land; nothing builds with the image default instead
#   2  CANNOT MEASURE: the pin itself could not be read
#
# SELECTED IS PROVED, NOT ASSUMED. A selector that exited 0 is not an Xcode
# xcodebuild uses, so the version is read back and compared (L12).
#
# Seams, so its suite needs no sudo and no second Xcode (L2, L196):
#
#   OVATION_XCODE_VERSION_FILE     the pin, defaulting to .xcode-version
#   OVATION_XCODE_APPS_DIR         where Xcode_<version>.app lives, /Applications
#   OVATION_XCODE_SELECT_COMMAND   the selector, `sudo xcode-select -s`, split on
#                                  spaces and handed the app path
#   OVATION_XCODEBUILD             the xcodebuild whose -version is read back
set -uo pipefail
# ovation#399: every library is loaded through require_lib, which refuses by name
# rather than carrying on without it. See scripts/lib/require.sh.
. "$(dirname "${BASH_SOURCE[0]}")/lib/require.sh" 2>/dev/null || { echo "REFUSED: scripts/lib/require.sh is missing, so nothing was checked." >&2; exit 2; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/xcode-pin.sh
require_lib "$REPO_ROOT/scripts/lib/xcode-pin.sh"

PIN_FILE="${OVATION_XCODE_VERSION_FILE:-$REPO_ROOT/.xcode-version}"
APPS_DIR="${OVATION_XCODE_APPS_DIR:-/Applications}"
SELECT_COMMAND="${OVATION_XCODE_SELECT_COMMAND:-sudo xcode-select -s}"
XCODEBUILD="${OVATION_XCODEBUILD:-xcodebuild}"

version="$(xcode_pin_read "$PIN_FILE")"
case $? in
    0) ;;
    1)
        echo "CANNOT MEASURE: there is no Xcode pin at $PIN_FILE."
        echo "    Nothing was selected, and the job must not build with the image"
        echo "    default in its place. The pin is one line holding a version, like 26.6."
        exit 2
        ;;
    *)
        # NOT QUOTED. The pin is text a person typed and this prints into a public
        # log (L222); the shape it should have is the remedy (L399).
        echo "CANNOT MEASURE: $PIN_FILE does not hold a version number like 26.6."
        echo "    Nothing was selected. A moving name in place of a version would restore"
        echo "    the behaviour this exists to remove (ovation#270)."
        exit 2
        ;;
esac

app="$APPS_DIR/Xcode_${version}.app"
if [ ! -d "$app" ]; then
    echo "REFUSED: Xcode ${version}, which .xcode-version pins, is not on this machine."
    echo "    Looked for: $app"
    have=""
    for candidate in "$APPS_DIR"/Xcode_*.app; do
        [ -d "$candidate" ] || continue
        have="${have}$(basename "$candidate") "
    done
    echo "    $APPS_DIR holds: ${have:-no Xcode_<version>.app at all}"
    echo "    This job stops here rather than building with the image's default Xcode."
    echo "    Runner images keep only the newest patch of each version, so this is"
    echo "    expected when a patch release replaces the pinned one: pin one of the"
    echo "    versions above in .xcode-version."
    exit 1
fi

# SPLIT ON PURPOSE: the default is a command and its arguments.
# shellcheck disable=SC2086
if ! $SELECT_COMMAND "$app"; then
    echo "REFUSED: selecting $app failed (see the selector's own message above)."
    echo "    Nothing about which Xcode builds here can be trusted."
    exit 1
fi

if ! reported="$(xcode_active_version "$XCODEBUILD")"; then
    echo "REFUSED: $app was selected, and xcodebuild then reported no version at all."
    echo "    A selection that did not land is not a selection (L12)."
    exit 1
fi
if [ "$reported" != "$version" ]; then
    echo "REFUSED: $app was selected, and xcodebuild reports Xcode ${reported}, not ${version}."
    echo "    The job would build with an Xcode nobody chose."
    exit 1
fi

echo "Selected Xcode ${version} from $app"
"$XCODEBUILD" -version 2>/dev/null | sed 's/^/    /'
exit 0
