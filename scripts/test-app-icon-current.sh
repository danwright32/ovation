#!/bin/bash
# The suite for scripts/check-app-icon-current.sh.
#
# ovation#102. Every case runs against a THROWAWAY artwork and a THROWAWAY
# catalog through the script's own seams, so nothing here can touch the committed
# icon (L2, L5). The real pair is checked once, deliberately, because a seam that
# hides the real thing from every test leaves the real thing untested (L246).
#
# THE TWO DEFECTS THE GUARD EXISTS FOR ARE BOTH PLANTED: the artwork replaced
# without the script being re-run, and a generated file edited by hand. Neither
# is visible to scripts/test-built-bundle-icon.sh, which asserts the bundle
# carries an icon and never that it is the icon the artwork specifies.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "app icon currency tests" 24

TARGET="scripts/check-app-icon-current.sh"
require_target "$TARGET"
harness_temp_dir WORK

if ! python3 -c 'import PIL' 2>/dev/null; then
    harness_cannot_measure "Pillow is not installed, so no catalog can be derived here" \
        "install it with: python3 -m pip install --user Pillow"
fi

# EACH SCENARIO IS RUN ONCE AND ITS OUTPUT KEPT. Every invocation re-derives the
# whole catalog, about a second, and the first version of this suite ran one per
# assertion and took ten. A pure check called once per assertion is mostly
# repeats, and the fix is to count the distinct INPUTS rather than the questions
# (L573). Caching on the exact pair is what keeps it correct: a coarser key would
# be faster and silently wrong.
LAST_OUT=""
LAST_STATUS=""
measure() {
    LAST_OUT="$(OVATION_ICON_SOURCE="$1" OVATION_ICON_CATALOG="$2" "./$TARGET" 2>&1)"
    LAST_STATUS="$?"
}
said() { printf '%s\n' "$LAST_OUT" | grep -c "$1"; }

# Two different pieces of artwork, both valid, so "the artwork moved on" can be
# staged without touching anything real.
python3 - "$WORK" <<'PY'
import sys
from PIL import Image
work = sys.argv[1]
Image.new("RGB", (1254, 1254), (12, 34, 56)).save(f"{work}/blue.png")
Image.new("RGB", (1254, 1254), (200, 60, 30)).save(f"{work}/red.png")
PY

# The catalog the blue artwork produces, built through the builder's own seam.
BLUE_SET="$WORK/blue-iconset"
OVATION_ICON_SOURCE="$WORK/blue.png" OVATION_ICONSET_OUT="$BLUE_SET" \
    bash scripts/build-app-icon.sh >/dev/null 2>&1
check "the fixture catalog was actually built, so the cases below mean something" \
    "$([ -f "$BLUE_SET/icon_512x512@2x.png" ] && echo yes || echo no)" "yes"

measure "$WORK/blue.png" "$BLUE_SET"
check "a catalog its artwork produces passes" "$LAST_STATUS" "0"
check "and it says how many files it compared" "$(said '11 file(s)')" "1"
check "and reports byte equality as information rather than as the verdict" \
    "$(said 'not the verdict')" "1"

# DEFECT ONE: the artwork is replaced and the script is not re-run.
measure "$WORK/red.png" "$BLUE_SET"
check "artwork that moved on without the script being re-run is refused" "$LAST_STATUS" "1"
check "and EVERY generated image is named, because every one of them changed" \
    "$(said 'is a different picture')" "10"
check "and it names the command that fixes it" \
    "$(said 'bash scripts/build-app-icon.sh')" "1"

# DEFECT TWO: one generated file is replaced by hand, the rest left alone.
HAND="$WORK/hand-edited"
cp -R "$BLUE_SET" "$HAND"
python3 - "$HAND" <<'PY'
import sys
from PIL import Image
Image.new("RGB", (512, 512), (0, 200, 0)).save(f"{sys.argv[1]}/icon_256x256@2x.png")
PY
measure "$WORK/blue.png" "$HAND"
check "one generated file edited by hand is refused" "$LAST_STATUS" "1"
check "and ONLY that file is named, not the nine that are fine" \
    "$(said 'is a different picture')" "1"
check "and it is the one that was edited" "$(said 'icon_256x256@2x.png:')" "1"

# Contents.json differing only in FORMATTING is not a difference. The first
# version appended it as a problem carrying a blank explanation, which is a
# refusal saying nothing about what it measured (L11).
REFORMATTED="$WORK/reformatted"
cp -R "$BLUE_SET" "$REFORMATTED"
python3 -c 'import json, sys
with open(sys.argv[1] + "/Contents.json") as h:
    data = json.load(h)
with open(sys.argv[1] + "/Contents.json", "w") as h:
    json.dump(data, h, indent=8, sort_keys=True)' "$REFORMATTED"
check "the fixture really did change the bytes of Contents.json" \
    "$(cmp -s "$REFORMATTED/Contents.json" "$BLUE_SET/Contents.json" && echo same || echo differs)" \
    "differs"
measure "$WORK/blue.png" "$REFORMATTED"
check "a Contents.json that is the same JSON differently formatted passes" "$LAST_STATUS" "0"

# One that declares something DIFFERENT is refused, so the case above is not the
# check having stopped reading it.
CHANGED_JSON="$WORK/changed-json"
cp -R "$BLUE_SET" "$CHANGED_JSON"
python3 -c 'import json, sys
with open(sys.argv[1] + "/Contents.json") as h:
    data = json.load(h)
data["images"][0]["size"] = "9x9"
with open(sys.argv[1] + "/Contents.json", "w") as h:
    json.dump(data, h)' "$CHANGED_JSON"
measure "$WORK/blue.png" "$CHANGED_JSON"
check "a Contents.json declaring different images is refused" "$LAST_STATUS" "1"
check "and the refusal says what is wrong rather than nothing at all" \
    "$(said 'declares different images or sizes')" "1"

# A file of the right picture at the wrong SIZE is its own sentence, because the
# remedy is the same but the diagnosis is not.
SIZED="$WORK/wrong-size"
cp -R "$BLUE_SET" "$SIZED"
python3 - "$SIZED" <<'PY'
import sys
from PIL import Image
Image.new("RGB", (64, 64), (12, 34, 56)).save(f"{sys.argv[1]}/icon_512x512.png")
PY
measure "$WORK/blue.png" "$SIZED"
check "a generated file at the wrong size is refused" "$LAST_STATUS" "1"
check "and it says the size rather than calling it a different picture" \
    "$(said '64x64 where the artwork produces')" "1"

# A file missing, and a file that no derivation produces, are two more outcomes.
MISSING="$WORK/missing"
cp -R "$BLUE_SET" "$MISSING"
rm "$MISSING/icon_16x16.png"
measure "$WORK/blue.png" "$MISSING"
check "a catalog missing a generated file is refused" "$LAST_STATUS" "1"
check "and it says the artwork produces one the catalog does not have" \
    "$(said 'the catalog does not have it')" "1"

EXTRA="$WORK/extra"
cp -R "$BLUE_SET" "$EXTRA"
cp "$EXTRA/icon_16x16.png" "$EXTRA/icon_1x1.png"
measure "$WORK/blue.png" "$EXTRA"
check "a catalog carrying a file no derivation produces is refused" "$LAST_STATUS" "1"
check "and it says the artwork produces no such file" \
    "$(said 'produces no such file')" "1"

# Nothing to measure is neither a pass nor a failure.
measure "$WORK/nowhere.png" "$BLUE_SET"
check "a missing artwork cannot be measured" "$LAST_STATUS" "2"
measure "$WORK/blue.png" "$WORK/nowhere"
check "a missing catalog cannot be measured" "$LAST_STATUS" "2"

# The real pair, once. BOTH catalogs, since ovation#103, because the check reads
# both when it is not pointed at one.
#
# ITS OWN OUTPUT IS KEPT, and that is not decoration. This assertion went red on
# the Linux CI runner and nowhere else, and all the log said was `expected 0,
# got 1`: the check had named the file and the difference and the suite threw
# them away, so the only way to find out what had happened was to reproduce it
# by hand. A guard whose failure says nothing about what it measured leaves the
# reader facing the same command (L148).
REAL="$WORK/real-pair.txt"
OVATION_ICON_SOURCE= OVATION_ICON_CATALOG= "./$TARGET" > "$REAL" 2>&1
REAL_STATUS=$?
if [ "$REAL_STATUS" != "0" ]; then
    echo "      what the check actually said:"
    sed 's/^/      /' "$REAL"
fi
check "the committed catalogs are what the real artwork produces" "$REAL_STATUS" "0"
check "and both variants were compared, not only the Release one" \
    "$(grep -cE '^  (release|debug): ' "$REAL")" "2"

harness_end
