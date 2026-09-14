#!/bin/bash
# The suite for scripts/build-invoice-pdf-text.sh.
#
# ovation#167. The app's invoice PDF is checked against the settled design by
# the TEXT the design draws: every figure, label and line of its six fixture
# invoices, rendered in a browser and committed as
# docs/design/invoice-pdf.expected.json, which OvationTests reads. A test that
# asserts agreement with a designed artifact has to READ that artifact, never a
# rule somebody believes produced it (L638), and a derived file committed beside
# its source is a standing claim that it is current, so the check that
# regenerates and compares ships with it (L422).
#
# So what has to be right here is the STALENESS answer, and every case below
# drives the tool into one outcome and asserts that outcome by name. The file is
# decoded HERE rather than through the tool, so no case is the tool marking its
# own work (L70). Every damaging case runs on a fresh copy of the design record.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "invoice PDF text tests" 15

TARGET="scripts/build-invoice-pdf-text.sh"
require_target "$TARGET"
require_target "docs/design/invoice-pdf.html"
harness_temp_dir WORK

# It answers 3 when it has nothing to render in, and that is established FIRST,
# or every assertion below would be measuring the absence of a browser rather
# than the presence of a defect. The status is captured on its own line.
python3 "$TARGET" --check >/dev/null 2>&1
PROBE=$?
if [ "$PROBE" = "3" ]; then
    harness_cannot_measure \
        "no headless browser, so the design cannot be rendered and nothing here proves anything" \
        "npx playwright install chromium, or set OVATION_HEADLESS_BROWSER"
fi

fresh() {
    local at="$WORK/$1"
    rm -rf "$at" && mkdir -p "$at" && cp -R docs/design/. "$at/"
    printf '%s' "$at"
}
run_in() { OVATION_DESIGN_ROOT="$1" python3 "$TARGET" "${@:2}" 2>&1; }
status_in() { OVATION_DESIGN_ROOT="$1" python3 "$TARGET" "${@:2}" >/dev/null 2>&1; printf '%s' "$?"; }

# A fact read out of an expected file by this suite, not by the tool.
fact() {
    python3 - "$1" "$2" <<'PYFACT'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
fixtures = data.get("fixtures", [])
which = sys.argv[2]
if which == "count":
    print(len(fixtures))
elif which == "every-element-money":
    sample = [f for f in fixtures if f.get("label") == "Every element"]
    rows = sample[0]["money"][:3] if len(sample) == 1 else []
    print(" / ".join("%s %s" % (label, value) for label, value in rows))
elif which == "last-money-labels":
    print(",".join(f["money"][-1][0] for f in fixtures))
PYFACT
}

damage() {
    # $1 file, $2 exact text, $3 replacement
    python3 - "$1" "$2" "$3" <<'PYDAMAGE'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()
assert old in text, "the mutation matched nothing, so this case tests nothing"
open(path, "w", encoding="utf-8").write(text.replace(old, new, 1))
PYDAMAGE
}

# ---------------------------------------------------------------------------
# THE COMMITTED FILE, which must be the text the design draws.
# ---------------------------------------------------------------------------
check "the committed expected text is what the design draws" "$(status_in "$(pwd)/docs/design" --check)" "0"
check "and the answer says how much it compared" \
    "$(run_in "$(pwd)/docs/design" --check | grep -c '6 fixture(s)')" "1"
check "the committed file holds all six fixture invoices" \
    "$(fact docs/design/invoice-pdf.expected.json count)" "6"
check "and the Every element invoice totals its lines above the referral credit (PRD 8)" \
    "$(fact docs/design/invoice-pdf.expected.json every-element-money)" \
    'Services $725.00 / Referral credit -$250.00 / Subtotal $475.00'

# ---------------------------------------------------------------------------
# THE CASE THIS EXISTS FOR: the design changes and the committed text does not.
# ---------------------------------------------------------------------------
D1="$(fresh designmoved)"
damage "$D1/invoice-pdf.html" 'tot.append(mk("span", null, "Total due"));' 'tot.append(mk("span", null, "Balance due"));'
check "a design drawn differently makes the committed text stale" "$(status_in "$D1" --check)" "1"
check "and the answer says STALE rather than refusing for another reason" \
    "$(run_in "$D1" --check | grep -c '^STALE: ')" "1"
check "and it names the remedy" \
    "$(run_in "$D1" --check | grep -c 'build-invoice-pdf-text.sh')" "1"
check "rewriting it makes it current again" "$(status_in "$D1")" "0"
check "and every fixture now carries the design's new wording" \
    "$(fact "$D1/invoice-pdf.expected.json" last-money-labels)" \
    "Balance due,Balance due,Balance due,Balance due,Balance due,Balance due"

# ---------------------------------------------------------------------------
# A HAND EDIT TO THE COMMITTED FILE IS CAUGHT TOO, because the file is judged
# against the rendering and never against itself.
# ---------------------------------------------------------------------------
D2="$(fresh handedit)"
damage "$D2/invoice-pdf.expected.json" '"Subtotal", "$475.00"' '"Subtotal", "$476.00"'
check "a figure changed by hand in the committed file is stale" "$(status_in "$D2" --check)" "1"
check "and it is reported as STALE" "$(run_in "$D2" --check | grep -c '^STALE: ')" "1"

# ---------------------------------------------------------------------------
# EACH WAY OF HAVING NOTHING TRUSTWORTHY IS ITS OWN OUTCOME (L11, L98).
# ---------------------------------------------------------------------------
D3="$(fresh unreadable)"
damage "$D3/invoice-pdf.html" 'function buildPage(inv) {' 'function buildPageGone(inv) {'
check "a design page the tool cannot read is refused, never written from" "$(status_in "$D3")" "4"
check "and it says the design could not be read" \
    "$(run_in "$D3" | grep -c 'could not be read')" "1"

D4="$WORK/nodesign"; mkdir -p "$D4"
check "a record with no design file is nothing to render, not a pass" "$(status_in "$D4" --check)" "2"
check "an argument it does not take is refused" "$(status_in "$(pwd)/docs/design" --bogus)" "2"

harness_end
