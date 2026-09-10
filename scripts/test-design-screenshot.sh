#!/bin/bash
# The suite for scripts/build-design-screenshot.sh.
#
# ovation#178. What has to be right about this is the STALENESS answer, because
# the picture it renders is a convenience and the claim beside it is not: a
# derived artifact committed next to its source is a standing claim that it is
# current, and nothing enforced that claim (L422). So every case below drives
# the check into one of its outcomes and asserts the outcome by name.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "design screenshot tests" 18

TARGET="scripts/build-design-screenshot.sh"
require_target "$TARGET"
require_target "docs/design/invoice-list.html"
harness_temp_dir WORK

# It answers 3 when it has nothing to render in or nothing to crop with, and
# that is the first thing to establish: every assertion below would otherwise be
# measuring the absence of a tool rather than the presence of a defect. The
# status is captured on its own line, because `if ! cmd` makes `$?` the
# negation's status.
python3 "$TARGET" --check >/dev/null 2>&1
PROBE=$?
if [ "$PROBE" = "3" ]; then
    harness_cannot_measure \
        "no headless browser or no Pillow, so nothing can be rendered or cropped" \
        "npx playwright install chromium, and python3 -m pip install Pillow"
fi

fresh() {
    local at="$WORK/$1"
    rm -rf "$at" && mkdir -p "$at" && cp -R docs/design/. "$at/"
    printf '%s' "$at"
}
run_in() { OVATION_DESIGN_ROOT="$1" python3 "$TARGET" "${@:2}" 2>&1; }
status_in() { OVATION_DESIGN_ROOT="$1" python3 "$TARGET" "${@:2}" >/dev/null 2>&1; printf '%s' "$?"; }

# ---------------------------------------------------------------------------
# The committed picture, which must be current.
# ---------------------------------------------------------------------------
check "the committed picture is the layout the file draws" "$(status_in "$(pwd)/docs/design" --check)" "0"
check "and the answer says how much it compared" \
    "$(run_in "$(pwd)/docs/design" --check | grep -c 'element(s) inside the screen')" "1"

# ---------------------------------------------------------------------------
# THE CASE THIS EXISTS FOR: the design file's SCREEN changes and the picture
# does not. On 2026-09-09 that state stood for four settled rounds.
# ---------------------------------------------------------------------------
MOVED="$(fresh moved)"
python3 - "$MOVED" <<'PYEOF'
import sys
path = sys.argv[1] + "/invoice-list.html"
text = open(path).read()
old = ".row { display: grid; grid-template-columns: var(--cols); gap: 14px; align-items: baseline; padding: 8px 24px;"
assert old in text, "the mutation matched nothing, so this case tests nothing"
open(path, "w").write(text.replace(
    old, ".row { display: grid; grid-template-columns: var(--cols); gap: 14px; "
         "align-items: baseline; padding: 18px 24px;", 1))
PYEOF
check "a screen drawn differently makes the picture stale" "$(status_in "$MOVED" --check)" "1"
check "and the answer says STALE rather than refusing for some other reason" \
    "$(run_in "$MOVED" --check | grep -c '^STALE: ')" "1"
check "and it names the remedy" \
    "$(run_in "$MOVED" --check | grep -c 'Re-render with')" "1"
check "re-rendering makes it current again" "$(status_in "$MOVED")" "0"
check "and the check then passes" "$(status_in "$MOVED" --check)" "0"

# ---------------------------------------------------------------------------
# EDITING THE RECORD'S PROSE IS NOT STALENESS. This is what makes the check
# worth having rather than one people learn to skip: the file is a page of
# writing wrapped around a rendering, and the prose changes far more often than
# the screen does. A stamp on the FILE would fire on every one of those.
# ---------------------------------------------------------------------------
PROSE="$(fresh prose)"
python3 - "$PROSE" <<'PYEOF'
import sys
path = sys.argv[1] + "/invoice-list.html"
text = open(path).read()
old = "<div class=\"stage\" id=\"stage\">"
assert old in text, "the mutation matched nothing, so this case tests nothing"
open(path, "w").write(text.replace(
    old, "<p>A sentence added to the record, outside the screen.</p>\n" + old, 1))
PYEOF
check "editing the record's prose leaves the picture current" "$(status_in "$PROSE" --check)" "0"

# ---------------------------------------------------------------------------
# THE PICTURE AND ITS SIDECAR ARE TWO FILES, and nothing else would notice one
# of them being replaced by hand.
# ---------------------------------------------------------------------------
NOPIC="$(fresh nopic)"
rm -f "$NOPIC/invoice-list.png"
check "a picture that is not there at all is stale" "$(status_in "$NOPIC" --check)" "1"
check "and says so in its own words" \
    "$(run_in "$NOPIC" --check | grep -c 'is not there at all')" "1"

NOSIDE="$(fresh noside)"
rm -f "$NOSIDE/invoice-list.png.layout"
check "a picture with nothing recording what it came from is stale" \
    "$(status_in "$NOSIDE" --check)" "1"
check "and that cause has its own sentence" \
    "$(run_in "$NOSIDE" --check | grep -c 'nothing records which layout')" "1"

RESIZED="$(fresh resized)"
python3 - "$RESIZED" <<'PYEOF'
import sys
from PIL import Image
path = sys.argv[1] + "/invoice-list.png"
with Image.open(path) as image:
    image.resize((image.width // 2, image.height // 2)).save(path)
PYEOF
check "a picture replaced by one of a different size is stale" \
    "$(status_in "$RESIZED" --check)" "1"
check "and the size is the cause it names" \
    "$(run_in "$RESIZED" --check | grep -c 'one of the two was replaced without the other')" "1"

# ---------------------------------------------------------------------------
# THE CROP COMES FROM THE PAGE, not from typed offsets, which is the fragility
# the issue names. A screen of a different width produces a picture of a
# different width, with nothing adjusted by hand.
# ---------------------------------------------------------------------------
NARROW="$(fresh narrow)"
python3 - "$NARROW" <<'PYEOF'
import sys
path = sys.argv[1] + "/invoice-list.html"
text = open(path).read()
old = ".screen { width: 1120px;"
assert old in text, "the mutation matched nothing"
open(path, "w").write(text.replace(old, ".screen { width: 900px;", 1))
PYEOF
check "a narrower screen renders a narrower picture" "$(status_in "$NARROW")" "0"
check "at twice the width the page reported, with nothing typed" \
    "$(run_in "$NARROW" | sed -n 's/.*at \([0-9]*\)x.*/\1/p')" "1800"

# ---------------------------------------------------------------------------
# NOTHING TO RENDER IS NOT A PASS (L98).
# ---------------------------------------------------------------------------
check "a design root with no such file cannot measure" \
    "$(OVATION_DESIGN_ROOT="$WORK/nowhere" python3 "$TARGET" --check >/dev/null 2>&1; printf '%s' "$?")" "2"
check "and a browser that is not there cannot measure either" \
    "$(OVATION_HEADLESS_BROWSER="$WORK/no-such-browser" python3 "$TARGET" --check \
        >/dev/null 2>&1; printf '%s' "$?")" "3"

harness_end
