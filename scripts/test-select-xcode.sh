#!/bin/bash
# Whether CI selects the Xcode this repository names, and stops BY NAME when the
# runner image does not have it.
#
# ovation#270. Both Mac jobs built with whatever Xcode the runner image shipped as
# its default, and nothing named a version, so an image update could move the
# compiler with no change in this repository and the push gate on Dan's Mac would
# stop predicting CI without anybody being told (L25, L376).
#
# Every case drives the script against a staged Applications folder, a stub
# `xcode-select` and a stub `xcodebuild`, because the real ones change which Xcode
# this whole Mac builds with and need sudo (L2, L196).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "xcode selection tests" 17

TARGET="scripts/select-xcode.sh"
require_target "$TARGET"
harness_temp_dir WORK

APPS="$WORK/Applications"
mkdir -p "$APPS/Xcode_26.5.app" "$APPS/Xcode_26.6.app"
PIN="$WORK/xcode-version"
printf '26.6\n' > "$PIN"

# The stub selector records what it was asked to select, and the stub xcodebuild
# reports whichever Xcode was last selected, so a case can only pass when the
# selection actually landed (L12).
SELECTED="$WORK/selected"
cat > "$WORK/select" <<SH
#!/bin/bash
printf '%s' "\$1" > "$SELECTED"
SH
cat > "$WORK/xcodebuild" <<SH
#!/bin/bash
v="\$(basename "\$(cat "$SELECTED" 2>/dev/null)" .app)"
v="\${v#Xcode_}"
[ -n "\$v" ] || { echo "xcode-select: error: no developer directory" >&2; exit 1; }
printf 'Xcode %s\nBuild version 17F113\n' "\$v"
SH
chmod +x "$WORK/select" "$WORK/xcodebuild"

run_select() {
    rm -f "$SELECTED"
    OVATION_XCODE_VERSION_FILE="${PIN_OVERRIDE:-$PIN}" \
    OVATION_XCODE_APPS_DIR="${APPS_OVERRIDE:-$APPS}" \
    OVATION_XCODE_SELECT_COMMAND="${SELECT_OVERRIDE:-$WORK/select}" \
    OVATION_XCODEBUILD="${XCODEBUILD_OVERRIDE:-$WORK/xcodebuild}" \
        "./$TARGET" 2>&1
}
status_select() { run_select >/dev/null 2>&1; printf '%s' "$?"; }
says() { if printf '%s' "$1" | grep -qF -- "$2"; then echo yes; else echo no; fi; }

# ---------------------------------------------------------------------------
# 1. THE PINNED XCODE IS PRESENT: it is selected, and the selection is proved.
# ---------------------------------------------------------------------------
OUT_OK="$(run_select)"; ST_OK=$?
check "a pinned Xcode that is present is selected" "$ST_OK" "0"
check "and it is the pinned one that was selected, not the image default" \
    "$(cat "$SELECTED" 2>/dev/null)" "$APPS/Xcode_26.6.app"
# THE LINE THE PULL REQUEST QUOTES. A CI log that does not name its compiler is
# how ovation#270 could not say which Xcode had failed.
check "and the log names the version xcodebuild now reports" \
    "$(says "$OUT_OK" "Xcode 26.6")" "yes"

# ---------------------------------------------------------------------------
# 2. THE PINNED XCODE IS ABSENT: stop at selection, by name, never fall back.
#    This is the outcome the issue asked to see fail.
# ---------------------------------------------------------------------------
printf '26.9\n' > "$WORK/absent-pin"
PIN_OVERRIDE="$WORK/absent-pin"
OUT_ABSENT="$(run_select)"; ST_ABSENT=$?
check "a pinned Xcode the image does not have is refused" "$ST_ABSENT" "1"
check "and the refusal names the pinned version" "$(says "$OUT_ABSENT" "26.9")" "yes"
check "and it lists what the image does have, so the next pin is a choice" \
    "$(says "$OUT_ABSENT" "Xcode_26.5.app")" "yes"
check "and nothing was selected, so no default Xcode quietly builds instead" \
    "$([ -e "$SELECTED" ] && echo selected || echo nothing)" "nothing"
unset PIN_OVERRIDE

# ---------------------------------------------------------------------------
# 3. THE PIN ITSELF CANNOT BE READ. Nothing to select is not a selection (L98).
# ---------------------------------------------------------------------------
PIN_OVERRIDE="$WORK/no-such-pin"
check "a pin file that is not there cannot be measured" "$(status_select)" "2"
check "and it names the file it looked for" \
    "$(says "$(run_select)" "$WORK/no-such-pin")" "yes"
unset PIN_OVERRIDE

printf 'latest\n' > "$WORK/bad-pin"
PIN_OVERRIDE="$WORK/bad-pin"
OUT_BADPIN="$(run_select)"; ST_BADPIN=$?
# A MOVING NAME IS THE THING BEING REMOVED. `latest` would restore exactly the
# behaviour ovation#270 was filed about, under a file that looks like a pin.
check "a pin that is not a version number cannot be measured" "$ST_BADPIN" "2"
# IT SAYS WHAT A PIN MUST LOOK LIKE, AND DOES NOT QUOTE THIS ONE. The pin is text
# a person typed, and this prints into the log of a public repository, so a
# refusal that echoed the file would print whatever was in it (L222). The shape
# is the remedy anyway (L399).
check "and it says what a pin must look like" "$(says "$OUT_BADPIN" "like 26.6")" "yes"
check "and does not quote the pin back" "$(says "$OUT_BADPIN" "latest")" "no"
unset PIN_OVERRIDE

# ---------------------------------------------------------------------------
# 4. THE SELECTION DID NOT LAND. A selector that reported success is not an
#    Xcode xcodebuild uses (L12).
# ---------------------------------------------------------------------------
cat > "$WORK/select-noop" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$WORK/select-noop"
SELECT_OVERRIDE="$WORK/select-noop"
check "a selection xcodebuild does not report is refused" "$(status_select)" "1"
unset SELECT_OVERRIDE

cat > "$WORK/select-fails" <<'SH'
#!/bin/bash
echo "xcode-select: error: staged refusal" >&2
exit 1
SH
chmod +x "$WORK/select-fails"
SELECT_OVERRIDE="$WORK/select-fails"
OUT_SELFAIL="$(run_select)"; ST_SELFAIL=$?
check "a selector that fails is refused" "$ST_SELFAIL" "1"
check "and the selector's own error is shown" "$(says "$OUT_SELFAIL" "staged refusal")" "yes"
unset SELECT_OVERRIDE

# ---------------------------------------------------------------------------
# 5. CI RUNS IT IN EVERY MAC JOB, and the local runner reads the same pin.
# ---------------------------------------------------------------------------
check "the repository records one pinned Xcode" \
    "$(grep -cE '^[0-9]+\.[0-9]+(\.[0-9]+)?$' .xcode-version 2>/dev/null)" "1"
check "and CI selects it" \
    "$(grep -v '^[[:space:]]*#' .github/workflows/ci.yml | grep -c 'bash scripts/select-xcode.sh')" \
    "$(grep -v '^[[:space:]]*#' .github/workflows/ci.yml | grep -cE 'runs-on: macos')"

harness_end
