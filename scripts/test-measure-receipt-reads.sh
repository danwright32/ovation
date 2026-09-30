#!/bin/bash
# ovation-runs-on: macos
# It drives Apple's Vision text recognition, which exists only on a Mac, so it
# cannot measure on Linux and the macOS build job runs it (ovation#161).
#
# The suite for scripts/measure-receipt-reads.py, the photographed receipt
# probe of ovation#74.
#
# EVERY RECEIPT HERE IS DRAWN BY THE SUITE, by scripts/lib/render-receipt-fixture.swift,
# for a stationer that does not exist. The probe's real subject is Dan's own
# receipts in the custody folder, and those can never be a fixture
# (docs/PRIVACY-FLOOR.md). Nothing here reads the custody folder.
#
# THE FOUR RECEIPTS are the shapes the probe has to tell apart: one whose lines
# sum and which carries a QR code, one whose lines do NOT sum, one with no line
# items at all, and the first one turned on its side. The counts asserted below
# are what those four must produce, so a probe that answered "computable" for a
# receipt with nothing to add up, or "held" for one whose sum is wrong, is red
# here rather than flattering the pilot (L543, L400).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "photographed receipt probe tests" 61

TARGET="scripts/measure-receipt-reads.py"
require_target "$TARGET"
require_target "scripts/receipt-reader.swift"
require_target "scripts/lib/render-receipt-fixture.swift"
harness_temp_dir WORK

if [ "$(uname -s)" != "Darwin" ] || ! command -v swiftc >/dev/null 2>&1 || ! command -v sips >/dev/null 2>&1; then
    harness_cannot_measure "The probe reads receipts with Apple's Vision framework, which needs a Mac with swiftc and sips." \
        "Run this suite on a Mac; the macOS build job does."
fi
if ! swiftc -O -o "$WORK/render" scripts/lib/render-receipt-fixture.swift >"$WORK/render-build.log" 2>&1; then
    harness_cannot_measure "The fixture renderer did not compile, so no receipt could be drawn to test with." \
        "$(head -n 5 "$WORK/render-build.log")"
fi

# THE PROBE'S DEFAULTS ARE DAN'S REAL CUSTODY FOLDER, so every run here passes
# its own folders AND runs under a throwaway home, so that a case which forgot
# an argument reads and writes nothing real (L2).
mkdir -p "$WORK/home"
export HOME="$WORK/home"

VENDOR="QUILLFEATHER TEST STATIONERS"
DATE="03/14/2026"
draw() {
    # draw <name> then the spec on stdin. Refuses loudly: a receipt that was not
    # drawn would shrink n and every count below would describe other receipts.
    cat > "$WORK/$1.spec"
    "$WORK/render" "$WORK/$1.spec" "$WORK/$1.png" || { echo "could not draw $1"; exit 1; }
}
T=$'\t'
draw good <<SPEC
C${T}${VENDOR}
C${T}${DATE}
L${T}Notebook${T}12.50
L${T}Pen set${T}8.25
L${T}Folder${T}4.00
L${T}SUBTOTAL${T}24.75
L${T}TAX${T}2.20
L${T}TOTAL${T}26.95
QR${T}TOTAL 26.95
SPEC
# The lines add to 24.75 and the receipt claims 27.75, while subtotal plus tax
# still equals the total. So one check must fail and the other must hold.
draw badsum <<SPEC
C${T}${VENDOR}
C${T}${DATE}
L${T}Notebook${T}12.50
L${T}Pen set${T}8.25
L${T}Folder${T}4.00
L${T}SUBTOTAL${T}27.75
L${T}TAX${T}2.20
L${T}TOTAL${T}29.95
SPEC
draw nolines <<SPEC
C${T}${VENDOR}
C${T}${DATE}
L${T}TOTAL${T}18.40
SPEC
draw upright <<SPEC
C${T}${VENDOR}
C${T}${DATE}
L${T}Notebook${T}12.50
L${T}Pen set${T}8.25
L${T}Folder${T}4.00
L${T}SUBTOTAL${T}24.75
L${T}TAX${T}2.20
L${T}TOTAL${T}26.95
SPEC

# Named the way the real ones are, with the vendor in the filename, so the
# assertion that no filename reaches the output has something to find.
RECEIPTS="$WORK/receipts"
mkdir -p "$RECEIPTS"
cp "$WORK/good.png" "$RECEIPTS/quillfeather-a.png"
cp "$WORK/badsum.png" "$RECEIPTS/quillfeather-b.png"
cp "$WORK/nolines.png" "$RECEIPTS/quillfeather-c.png"
sips -r 90 "$WORK/upright.png" --out "$RECEIPTS/quillfeather-d.png" >/dev/null 2>&1
# A hidden file is Finder's, not a receipt, and must not count toward n.
printf 'x' > "$RECEIPTS/.DS_Store"

RESULTS="$WORK/results"
# THE READER CAN BE REPLACED only so this suite can drive its own UNMEASURED
# path below; empty means the real one, compiled from source.
OUT="$(OVATION_RECEIPT_READER="${OVATION_TEST_RECEIPT_READER:-}" \
    ./"$TARGET" --folder "$RECEIPTS" --results "$RESULTS" 2>&1)"; STATUS=$?
# VISION THAT CANNOT RUN HERE IS UNMEASURED, BY NAME, never a pass and never a
# failure of every case after it (L411). Asked before any assertion, so no
# earlier verdict is swallowed by the exit.
if [ "$STATUS" = "2" ] && grep -q '^CANNOT MEASURE: Vision text recognition' <<< "$OUT"; then
    harness_cannot_measure "Vision text recognition refused to run on this machine, so no drawn receipt was read." \
        "$(head -n 3 <<< "$OUT")"
fi
check "the probe measures four drawn receipts successfully" "$STATUS" "0"
[ "$STATUS" = "0" ] || printf '%s\n' "$OUT" | head -n 30 | sed 's/^/        /'

says() { printf '%s\n' "$OUT" | grep -cE -- "$1"; }
check "it says in its own output that this is a pilot and not a verdict" \
    "$(says '^PILOT, n=4, NOT A VERDICT$')" "1"
check "the amount was read on all four, the turned one included" \
    "$(says '^  amount +read 4 of 4 +would fill 4 of 4$')" "1"
check "the date was read on all four" "$(says '^  date +read 4 of 4 +would fill 4 of 4$')" "1"
check "the vendor was read on all four" "$(says '^  vendor +read 4 of 4 +would fill 4 of 4$')" "1"
check "line items could be summed on three, never on the receipt that has none" \
    "$(says '^  line items sum to the subtotal: +computable 3 of 4, held 2 of 3$')" "1"
check "subtotal plus tax could be checked on three and held on all three" \
    "$(says '^  subtotal plus tax equals the total: +computable 3 of 4, held 3 of 3$')" "1"
check "either check was resolvable on three" "$(says '^  either check computable: +3 of 4$')" "1"
check "a QR code was found on the one receipt that carries one" \
    "$(says '^  barcode or QR present: +1 of 4$')" "1"
check "the second pass, with language correction, is reported beside the first and compared with it" \
    "$(says '^  amount +read 4 of 4 +would fill [0-4] of 4 +same as the first pass 4 of 4$')" "1"
# MEASURED 2026-09-29: with correction off, text revision 3 gives one candidate
# per observation, so PRD 18a's signal cannot fire in that pass. Asserted, so an
# OS update that changes it is noticed rather than silently changing what
# "would fill" means.
check "and the output says how often each pass offered a disagreeing alternative at all" \
    "$(says '^  correction off +0 of [1-9][0-9]*$'):$(says '^  correction on +[0-9]+ of [1-9][0-9]*$')" "1:1"
check "and the turned receipt is counted as read turned" "$(says '^  read turned from upright: +1 of 4$')" "1"
check "the reader it measured with is recorded, since a system update can change it (PRD 18c)" \
    "$(says '^Reader: .*text recognition revision [0-9]+, barcode revision [0-9]+$')" "1"

# THE PRIVACY FLOOR. The probe reads real receipts by construction and prints
# counts only (docs/PRIVACY-FLOOR.md, L222).
check "no vendor reaches the output" "$(printf '%s' "$OUT" | grep -ci 'quillfeather\|stationers')" "0"
check "no amount reaches the output" "$(printf '%s' "$OUT" | grep -cE '26\.95|29\.95|18\.40|24\.75')" "0"
check "no date reaches the output" "$(printf '%s' "$OUT" | grep -cF "$DATE")" "0"

# THE LOCAL RESULTS, which Dan reads against the receipts themselves.
JSON="$(ls "$RESULTS"/results-*.json 2>/dev/null)"
HTML="$(ls "$RESULTS"/results-*.html 2>/dev/null)"
check "exactly one results file was written" "$(printf '%s\n' "$JSON" | grep -c 'results-')" "1"
check "and one page to read it on" "$(printf '%s\n' "$HTML" | grep -c 'results-')" "1"
check "the output says how to open that page" \
    "$(says "^  open -a \"Google Chrome\" \"$HTML\"$")" "1"
check "the results are readable by Dan alone" "$(stat -f '%Lp' "$JSON"):$(stat -f '%Lp' "$HTML")" "600:600"
check "and so is the folder holding them" "$(stat -f '%Lp' "$RESULTS")" "700"

field() {
    python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
receipt = data["receipts"][int(sys.argv[2]) - 1]
value = receipt
for key in sys.argv[3].split("."):
    value = value[int(key)] if isinstance(value, list) else value[key]
print(json.dumps(value) if isinstance(value, (bool, type(None), list, dict)) else value)
' "$JSON" "$@" 2>&1
}
check "each receipt is recorded under its own filename, for Dan" "$(field 1 file)" "quillfeather-a.png"
check "the amount read is the total" "$(field 1 amount.value)" "26.95"
check "with Vision's confidence beside it" "$(field 1 amount.confidence | grep -cE '^[01](\.[0-9]+)?$')" "1"
check "and the alternatives Vision offered, even when there are none" "$(field 1 amount.alternatives)" "[]"
check "the date is recorded as read" "$(field 1 date.value)" "$DATE"
check "the vendor is recorded as read" "$(field 1 vendor.value)" "$VENDOR"
check "the QR payload is recorded, with whether it carries the amount" \
    "$(field 1 barcodes.0.payloadContainsAmount)" "true"
check "lines that sum are recorded as held" "$(field 1 arithmetic.lineItems.held)" "true"
check "lines that do not sum are recorded as failing" "$(field 2 arithmetic.lineItems.held)" "false"
check "with both sides of the sum, so Dan can see by how much" \
    "$(field 2 arithmetic.lineItems.sum):$(field 2 arithmetic.lineItems.against)" "24.75:27.75"
check "a receipt with no line items is not computable, and says why" \
    "$(field 3 arithmetic.lineItems.computable):$(field 3 arithmetic.lineItems.reason)" "false:no line items"
check "the second pass's reading is recorded per receipt, with whether it agrees" \
    "$(field 1 withLanguageCorrection.amount.value):$(field 1 passesAgree.amount)" "26.95:true"
check "the turned receipt reads the same total as the upright one" "$(field 4 amount.value)" "26.95"
check "and records how far it was turned" "$(field 4 turnedDegrees)" "90"

# THE AMBIGUITY SIGNAL, PRD 18a's own example. When Vision's alternative reading
# of the amount disagrees with its best one, 38.20 against 88.20, the field is
# not filled and both readings are kept. No drawn receipt makes Vision hesitate,
# so this drives the interpretation directly with a reading that does.
AMBIGUOUS="$(python3 - "$TARGET" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("probe", sys.argv[1])
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
def seen(texts, x, y):
    return {"candidates": [{"text": t, "confidence": 0.5} for t in texts],
            "topLeft": [x, y + 0.05], "topRight": [x + 0.2, y + 0.05],
            "bottomLeft": [x, y], "bottomRight": [x + 0.2, y]}
raw = {"index": 1, "readable": True, "pixelWidth": 900, "pixelHeight": 900, "barcodes": [],
       "observations": [seen(["QUILLFEATHER TEST STATIONERS", "QUILLFEATHER TEST STATIONER"], 0.2, 0.9),
                        seen(["TOTAL"], 0.05, 0.5), seen(["38.20", "88.20", "3.20"], 0.75, 0.5)]}
read = probe.interpret(raw, "a.png", "0")
amount = read["amount"]
print(amount["value"], "|".join(a["value"] for a in amount["alternatives"]), amount["wouldFill"],
      read["vendor"]["wouldFill"])
PY
)"
check "a disagreeing alternative reading keeps the best one as read" "$(printf '%s' "$AMBIGUOUS" | cut -d' ' -f1)" "38.20"
check "and records every alternative beside it, a dropped digit included, since that is a different amount" \
    "$(printf '%s' "$AMBIGUOUS" | cut -d' ' -f2)" "88.20|3.20"
check "and does not fill the field" "$(printf '%s' "$AMBIGUOUS" | cut -d' ' -f3)" "False"
check "while a vendor whose alternative only drops a letter is still filled" \
    "$(printf '%s' "$AMBIGUOUS" | cut -d' ' -f4)" "True"

# RE-PRINTING from a results file gives the same summary without re-reading.
AGAIN="$(./"$TARGET" --summarise "$JSON" 2>&1)"
check "re-summarising the results file prints the same counts" \
    "$(printf '%s\n' "$AGAIN" | grep -E '^  ' | grep -v 'open -a' )" \
    "$(printf '%s\n' "$OUT" | grep -E '^  ' | grep -v 'open -a' )"

# AT TWENTY IT STOPS CALLING ITSELF A PILOT, and still never calls itself a
# verdict, because correctness is judged against the receipts by Dan.
python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
data["receipts"] = data["receipts"] * 5
json.dump(data, open(sys.argv[2], "w"))
' "$JSON" "$WORK/twenty.json"
TWENTY="$(./"$TARGET" --summarise "$WORK/twenty.json" 2>&1)"
check "twenty receipts are no longer a pilot, and are still not a verdict" \
    "$(printf '%s\n' "$TWENTY" | grep -c PILOT):$(printf '%s\n' "$TWENTY" | grep -c '^n=20, NOT A VERDICT$')" "0:1"

# THE REFUSALS, each named, and none of them writing a results file.
check_exit "a folder that does not exist is refused" 1 ./"$TARGET" --folder "$WORK/nowhere" --results "$WORK/r1"
check "and the refusal says so" \
    "$(./"$TARGET" --folder "$WORK/nowhere" --results "$WORK/r1" 2>&1 | grep -c '^REFUSED: the receipt folder does not exist')" "1"
mkdir -p "$WORK/empty"
printf 'x' > "$WORK/empty/.DS_Store"
check "a folder holding no receipts is refused rather than measured as zero" \
    "$(./"$TARGET" --folder "$WORK/empty" --results "$WORK/r2" 2>&1 | grep -c '^REFUSED: the receipt folder holds no receipts'):$(status_or_words 1 ./"$TARGET" --folder "$WORK/empty" --results "$WORK/r2")" "1:1"
mkdir -p "$WORK/bad"
cp "$WORK/good.png" "$WORK/bad/quillfeather-a.png"
printf 'not an image' > "$WORK/bad/quillfeather-z.png"
BAD="$(./"$TARGET" --folder "$WORK/bad" --results "$WORK/r3" 2>&1)"; BAD_STATUS=$?
check "an unreadable image refuses the run, naming it by position and never by filename" \
    "$BAD_STATUS:$(printf '%s' "$BAD" | grep -c '^REFUSED: receipt 2 of 2 could not be read as an image'):$(printf '%s' "$BAD" | grep -ci quillfeather)" "1:1:0"
mkdir -p "$WORK/repo"
git -C "$WORK/repo" init -q
check "results are refused a home inside a git repository, where they could be committed" \
    "$(./"$TARGET" --folder "$RECEIPTS" --results "$WORK/repo/out" 2>&1 | grep -c '^REFUSED: the results folder is inside a git repository')" "1"
check "and no refusal wrote a results file" \
    "$(ls "$WORK/r1" "$WORK/r2" "$WORK/r3" "$WORK/repo/out" 2>/dev/null | grep -c results-)" "0"
check_exit "a Mac without the Swift compiler answers CANNOT MEASURE, not a result" 2 \
    env PATH="$WORK/no-tools" "$(command -v python3)" "$TARGET" --folder "$RECEIPTS" --results "$WORK/r4"

# STAND IN READERS, so each shape of bad output can be produced on purpose. A
# reader is called as `reader --out <file> <image>...` and writes its JSON to
# that file; stdout is not its channel (see the next case for why).
stand_in() {
    { printf '#!/bin/bash\nout="$2"\n'; cat; } > "$WORK/$1"
    chmod +x "$WORK/$1"
}
ONE_RECEIPT='{"osVersion": "x", "textRecognitionRevision": 3, "barcodeRevision": 4, "receipts": [{"index": 1, "readable": true, "pixelWidth": 900, "pixelHeight": 900, "observations": [], "observationsWithCorrection": [], "barcodes": []}]}'
mkdir -p "$WORK/one"
cp "$WORK/good.png" "$WORK/one/a.png"

# THE CAUSE OF THE FIRST CI FAILURE. In a virtual machine Apple's own model
# runtime prints its exceptions to STDOUT ("E5RT encountered an STL exception
# ... On-device compilation within a VM only supports CPU currently"), after
# the reader's JSON, so a reading that had worked was refused as not JSON.
# The JSON therefore goes to a file, and chatter on stdout spoils nothing.
stand_in chatty-reader <<SH
printf '%s' '$ONE_RECEIPT' > "\$out"
echo "E5RT encountered an STL exception. msg = On-device compilation within a VM only supports CPU currently."
SH
check_exit "a framework printing to stdout does not spoil a reading written to the reader's file" 0 \
    env OVATION_RECEIPT_READER="$WORK/chatty-reader" ./"$TARGET" --folder "$WORK/one" --results "$WORK/r8"

# WHAT THE READER SAID, WHEN ITS FILE WAS NOT ITS JSON (L11). On CI the only
# words were "not its JSON", which named no cause.
stand_in junk-reader <<'SH'
printf '{"x":' > "$out"
echo "objc[1]: a framework warning"
echo "a note on stderr" >&2
SH
stand_in cut-reader <<'SH'
printf '{"receipts": [{"text": "QUILLFEATHER' > "$out"
SH
JUNK="$(OVATION_RECEIPT_READER="$WORK/junk-reader" ./"$TARGET" --folder "$RECEIPTS" --results "$WORK/r5" 2>&1)"; JUNK_STATUS=$?
check "output that is not the reader's JSON is refused" \
    "$JUNK_STATUS:$(grep -c '^REFUSED: the Vision reader wrote something that is not its JSON' <<< "$JUNK")" "1:1"
check "and the refusal names the reader's exit status and what it wrote to stderr" \
    "$(grep -c 'exit status 0' <<< "$JUNK"):$(grep -c 'a note on stderr' <<< "$JUNK")" "1:1"
check "and quotes the first line of stdout, where no receipt text is ever written" \
    "$(grep -c 'objc\[1\]: a framework warning' <<< "$JUNK"):$(grep -c 'the parser said: Expecting value' <<< "$JUNK")" "1:1"
CUT="$(OVATION_RECEIPT_READER="$WORK/cut-reader" ./"$TARGET" --folder "$RECEIPTS" --results "$WORK/r6" 2>&1)"
check "JSON cut short is refused by its size, never quoted, since it can carry a receipt's text" \
    "$(grep -c 'bytes of JSON that do not parse' <<< "$CUT"):$(grep -ci quillfeather <<< "$CUT")" "1:0"

# VISION REFUSING IS ITS OWN CAUSE, not an unreadable image and not a result.
stand_in refusing-reader <<'SH'
printf '%s' '{"osVersion": "x", "textRecognitionRevision": 3, "barcodeRevision": 4, "receipts": [{"index": 1, "readable": false, "visionRefused": true, "error": "Vision refused: no model", "pixelWidth": 0, "pixelHeight": 0, "observations": [], "observationsWithCorrection": [], "barcodes": []}]}' > "$out"
SH
REFUSING="$(OVATION_RECEIPT_READER="$WORK/refusing-reader" ./"$TARGET" --folder "$RECEIPTS" --results "$WORK/r7" 2>&1)"; REFUSING_STATUS=$?
check "Vision refusing to recognise text answers CANNOT MEASURE, naming Vision's own words" \
    "$REFUSING_STATUS:$(grep -c '^CANNOT MEASURE: Vision text recognition refused on this machine: Vision refused: no model' <<< "$REFUSING")" "2:1"
# And THIS SUITE, run where Vision refuses, says UNMEASURED rather than failing
# every case or passing. Run once, nested, with the refusing reader standing in.
if [ -z "${OVATION_TEST_RECEIPT_READER:-}" ]; then
    NESTED="$(OVATION_TEST_RECEIPT_READER="$WORK/refusing-reader" "$0" 2>&1)"; NESTED_STATUS=$?
    check "the suite, where Vision cannot run, exits CANNOT MEASURE and says why" \
        "$NESTED_STATUS:$(grep -c 'Vision text recognition refused to run on this machine' <<< "$NESTED")" "2:1"
else
    check "the nested run does not nest again" "nested" "nested"
fi

# A REPLACED READER IS SAID OUT LOUD, and kept out of Dan's custody folder. The
# seam is honoured whenever it is set, so a value left exported from a test
# would otherwise put a stand in's numbers where Vision's belong, looking like a
# normal run (L169, review of ovation#636).
stand_in fine-reader <<SH
printf '%s' '$ONE_RECEIPT' > "\$out"
SH
STOOD="$(OVATION_RECEIPT_READER="$WORK/fine-reader" ./"$TARGET" --folder "$WORK/one" --results "$WORK/r9" 2>&1)"
check "a run with a stand in reader says so in its summary" \
    "$(grep -c "^READER REPLACED: OVATION_RECEIPT_READER=$WORK/fine-reader stood in for Vision" <<< "$STOOD")" "1"
check "and in its results file" \
    "$(python3 -c 'import json,sys,glob; print(json.load(open(glob.glob(sys.argv[1]+"/results-*.json")[0]))["reader"]["standIn"])' "$WORK/r9" 2>&1)" \
    "$WORK/fine-reader"
CUSTODY_RESULTS="$HOME/Library/Application Support/Ovation/custody/receipt-probe"
check "and a stand in reader is refused the real custody folder" \
    "$(OVATION_RECEIPT_READER="$WORK/fine-reader" ./"$TARGET" --folder "$WORK/one" --results "$CUSTODY_RESULTS" 2>&1 | grep -c '^REFUSED: OVATION_RECEIPT_READER is set'):$(ls "$CUSTODY_RESULTS" 2>/dev/null | grep -c results-)" "1:0"

# A LINE ITEM IS NOT A PAYMENT because a word inside it looks like one. The
# payment words matched bare substrings, so Postcard, Cardstock, Author copy,
# Prepaid and Exchange fee were all taken for payment lines and dropped from
# the sum (review of ovation#636).
WORDS="$(python3 - "$TARGET" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("probe", sys.argv[1])
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
rows = [("Postcard", "3.00"), ("Cardstock", "2.00"), ("Author copy", "4.00"), ("Prepaid stamp", "1.00"),
        ("Exchange fee", "0.50"), ("Promotional poster", "1.25"), ("SUBTOTAL", "11.75"),
        ("TOTAL", "11.75"), ("VISA", "11.75"), ("CHANGE", "0.00")]
observations = []
for n, (label, amount) in enumerate(rows):
    y = 0.9 - n * 0.06
    for text, x in ((label, 0.05), (amount, 0.75)):
        observations.append({"candidates": [{"text": text, "confidence": 1.0}],
                             "topLeft": [x, y + 0.03], "topRight": [x + 0.2, y + 0.03],
                             "bottomLeft": [x, y], "bottomRight": [x + 0.2, y]})
raw = {"index": 1, "readable": True, "pixelWidth": 900, "pixelHeight": 900, "barcodes": [],
       "observations": observations, "observationsWithCorrection": []}
check = probe.interpret(raw, "a.png", "0")["arithmetic"]["lineItems"]
kinds = [line["kind"] for line in probe.interpret(raw, "a.png", "0")["lines"]]
print(check["lineItems"], check["held"], kinds[-2], kinds[-1])
PY
)"
check "item lines whose words only contain a payment word are summed as items" "$WORDS" "6 True payment payment"

# --summarise TAKES A RESULTS .json, and says so rather than guessing a page.
printf '{}' > "$WORK/results.txt"
check "a --summarise file that is not .json is refused by name" \
    "$(./"$TARGET" --summarise "$WORK/results.txt" 2>&1 | grep -c '^REFUSED: --summarise takes a results .json file')" "1"
cp "$JSON" "$WORK/Results.JSON"
cp "$HTML" "$WORK/Results.html"
check "and the page beside a results file is found whatever the case of its extension" \
    "$(./"$TARGET" --summarise "$WORK/Results.JSON" 2>&1 | grep -cF "open -a \"Google Chrome\" \"$WORK/Results.html\"")" "1"

harness_end
