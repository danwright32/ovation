#!/bin/bash
# The suite for scripts/build-invoice-pdf-text.sh.
#
# ovation#167. The app's invoice PDF is checked against the settled design by
# the TEXT the design draws: every figure, label and line of its eight fixture
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
harness_begin "invoice PDF text tests" 21

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
elif which == "inputs":
    keys = ("number", "issued", "due", "client", "exempt", "lines")
    print(sum(1 for f in fixtures
              if all(k in f.get("input", {}) for k in keys) and f["input"]["lines"]))
elif which == "paid-in-full-head":
    # ovation#326. The receipt head, which is outbound copy a client may read.
    sample = [f for f in fixtures if f.get("label") == "Paid in full"]
    head = sample[0]["head"] if len(sample) == 1 else {}
    print("%s / %s / %s" % (head.get("label", ""), head.get("amount", ""), head.get("due", "")))
elif which == "paid-in-full-paid-on":
    sample = [f for f in fixtures if f.get("label") == "Paid in full"]
    print(sample[0].get("input", {}).get("paidOn", "") if len(sample) == 1 else "")
elif which == "every-element-input":
    sample = [f for f in fixtures if f.get("label") == "Every element"]
    given = sample[0].get("input", {}) if len(sample) == 1 else {}
    print("credit %s, discount %s%%, %d lines" % (given.get("credit"),
          (given.get("discount") or {}).get("percent"), len(given.get("lines", []))))
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
    "$(run_in "$(pwd)/docs/design" --check | grep -c '8 fixture(s)')" "1"
# EIGHT SINCE ovation#326, which added the settled receipt. It is one fixture and
# not two: Dan settled that the page says NOTHING about money left held, and
# PaymentAllocator refuses to allocate past what an invoice owes, so a deposit
# LARGER than the bill is paid exactly and draws this same page.
check "the committed file holds all eight fixture invoices" \
    "$(fact docs/design/invoice-pdf.expected.json count)" "8"
check "and the Every element invoice totals its lines above the referral credit (PRD 8)" \
    "$(fact docs/design/invoice-pdf.expected.json every-element-money)" \
    'Services $725.00 / Referral credit -$250.00 / Subtotal $475.00'

# ONE SET OF INPUTS FOR BOTH SIDES (L26). The app's test builds the same eight
# invoices and compares what it writes with what the design draws. If it typed
# those invoices out again it would hold a second copy of the fixtures, and the
# two copies would drift, so each fixture's INPUT travels in the same file as the
# text it produces.
check "each fixture carries the inputs the design builds it from" \
    "$(fact docs/design/invoice-pdf.expected.json inputs)" "8"
# THE RECEIPT (ovation#326), pinned HERE because this file is where the design's
# own text is judged, so a change to the wording fails by name rather than only
# as a diff somewhere downstream.
#
# It reads `Paid in full`, WHAT THE INVOICE CAME TO, and the day the money
# arrived. Each of the three was chosen from renderings against alternatives: a
# head still saying `Amount due $0.00`, a figure showing what was handed over
# rather than what the invoice was for, and a date the money is wanted by, which
# is a demand when nothing is being demanded.
check "the settled receipt says paid in full, the invoice's own total, and the day it was paid" \
    "$(fact docs/design/invoice-pdf.expected.json paid-in-full-head)" \
    'Paid in full / $272.19 / paid February 12, 2027'
# THE DATE TRAVELS AS AN INPUT, so the app dates its receipt from the same day
# rather than from the invoice date, which is a different day: a deposit arrives
# BEFORE the shoot. Without this the two sides would disagree by weeks.
check "and the day the money arrived travels with the fixture's inputs" \
    "$(fact docs/design/invoice-pdf.expected.json paid-in-full-paid-on)" "February 12, 2027"
check "and the Every element inputs carry its credit, its discount and its three lines" \
    "$(fact docs/design/invoice-pdf.expected.json every-element-input)" "credit 250, discount 10%, 3 lines"

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
    "Balance due,Balance due,Balance due,Balance due,Balance due,Balance due,Balance due,Balance due"

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

# A FIXTURE DATE THE PAGE CANNOT READ IS A REFUSAL, NOT A PAGE (L50). Parsed as
# NaN it would reach the terms rule and be written as "within NaN days", which
# reads as text rather than as a fault.
D5="$(fresh baddate)"
damage "$D5/invoice-pdf.html" 'due: "March 20, 2027"' 'due: "Smarch 20, 2027"'
check "a fixture date the page cannot read is refused, never written as a term" "$(status_in "$D5")" "4"
check "and it names the date it could not read" \
    "$(run_in "$D5" | grep -c 'Smarch 20, 2027 is not a date')" "1"

D4="$WORK/nodesign"; mkdir -p "$D4"
check "a record with no design file is nothing to render, not a pass" "$(status_in "$D4" --check)" "2"
check "an argument it does not take is refused" "$(status_in "$(pwd)/docs/design" --bogus)" "2"

harness_end
