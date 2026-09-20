#!/bin/bash
# The suite for scripts/write-design-embedded-page.sh and the check it answers,
# scripts/check-design-embedded-page.sh.
#
# ovation#167. review-send.html carries the whole invoice PDF design as one
# escaped string, PDF_PAGE, and hands it to a frame, so its preview runs that
# file's own code (PRD 10c). Nothing compared the two. Measured on 2026-09-14 the
# embedded page was an older copy: it still carried the builder that blanks the
# whole page on a line with no hours, fixed in invoice-pdf.html by ovation#170,
# and it still printed a phone number the design had since dropped (L613, L370).
#
# THE SHAPE OF EVERY CASE IS DAMAGE, WRITE, THEN JUDGE WITH THE CHECKER, and the
# page is decoded HERE rather than through the library both scripts share, so no
# case is one tool marking its own work (L70). Every case runs on a fresh copy of
# the committed record, so nothing a case writes reaches the repository.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "embedded page writer tests" 13

TARGET="scripts/write-design-embedded-page.sh"
CHECKER="scripts/check-design-embedded-page.sh"
require_target "$TARGET"
require_target "$CHECKER"
harness_temp_dir WORK

fresh() {
    local at="$WORK/$1"
    rm -rf "$at" && mkdir -p "$at" && cp -R docs/design/. "$at/"
    printf '%s' "$at"
}
write_status() { OVATION_DESIGN_ROOT="$1" python3 "$TARGET" "${@:2}" >/dev/null 2>&1; printf '%s' "$?"; }
check_status() { OVATION_DESIGN_ROOT="$1" python3 "$CHECKER" >/dev/null 2>&1; printf '%s' "$?"; }
check_output() { OVATION_DESIGN_ROOT="$1" python3 "$CHECKER" 2>&1; }

# The page inside the host, decoded independently of the scripts under test.
embedded() {
    python3 - "$1/review-send.html" <<'PYDECODE'
import json, sys
for line in open(sys.argv[1], encoding="utf-8").read().split("\n"):
    if line.startswith("var PDF_PAGE = "):
        print(json.loads(line[len("var PDF_PAGE = "):].rstrip().rstrip(";")))
        break
PYDECODE
}
# How many times a fixed string occurs in the decoded page.
count_in_page() { embedded "$1" | grep -cF -- "$2"; }

damage() {
    # $1 root, $2 file, $3 exact text, $4 replacement
    python3 - "$1/$2" "$3" "$4" <<'PYDAMAGE'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()
assert old in text, "the mutation matched nothing, so this case tests nothing"
open(path, "w", encoding="utf-8").write(text.replace(old, new, 1))
PYDAMAGE
}

# 1. THE COMMITTED RECORD IS IN STEP. The case that goes red the day somebody
#    edits invoice-pdf.html and does not run the writer.
check "the committed review-send.html carries the committed invoice PDF design" \
    "$(check_status docs/design)" "0"

# 2. DRIFT IS FOUND, AND THE WRITER IS THE REMEDY.
D2="$(fresh drift)"
damage "$D2" invoice-pdf.html 'settled ? "Paid in full" : "Amount due"' 'settled ? "Paid in full" : "Amount owed"'
check "a change to the design's page builder is drift in the host" "$(check_status "$D2")" "1"
write_status "$D2" >/dev/null
check "and after the writer runs, the checker passes" "$(check_status "$D2")" "0"
check "and the change is really inside the embedded page" "$(count_in_page "$D2" 'Amount owed')" "1"

# 3. A DECLARATION BELONGS TO THE FILE THAT MAKES IT. invoice-pdf.html says it
#    carries none of the shell; carried into the host, that sentence would read as
#    review-send.html declaring it, and the shell check would judge the wrong file.
D3="$(fresh markers)"; write_status "$D3" >/dev/null
check "no declaration marker is carried into the embedded page" \
    "$(count_in_page "$D3" 'NOT SHELLED:')" "0"

# 4. THE HOST'S OWN SCRIPT IS NOT ENDED EARLY. The page ends with a closing script
#    tag, and a raw one inside the string would end the host's script there.
check "the embedded string never holds a raw closing script tag" \
    "$(grep -F 'var PDF_PAGE = ' "$D3/review-send.html" | grep -cF '</script>')" "0"

# 5. THE HOST'S OWN INVOICE SURVIVES, because it is what the preview draws.
check "the preview's own invoice is kept when the page is regenerated" \
    "$(count_in_page "$D3" 'document.body.replaceChildren(buildPage(CEDAR));')" "1"

# 6. THE FIX THE STALE COPY LACKED REACHES THE PREVIEW (ovation#170).
check "the builder that tolerates a line with no hours is the one the preview runs" \
    "$(count_in_page "$D3" 'l.hours == null')" "1"

# 7. EACH ANCHOR THAT CANNOT BE FOUND IS REFUSED BY NAME (L100, L11).
D7A="$(fresh noliteral)"
damage "$D7A" review-send.html 'var PDF_PAGE = ' 'var PDF_PAGE_GONE = '
check "a host with no embedded page is nothing to compare, not a pass" "$(check_status "$D7A")" "2"
D7B="$(fresh nocut)"
damage "$D7B" invoice-pdf.html 'var bar = document.getElementById("fixbar");' 'var bar = null;'
check "a design whose chooser cannot be found is refused, not guessed at" "$(write_status "$D7B")" "1"
D7C="$(fresh notail)"
python3 - "$D7C/review-send.html" <<'PYTAIL'
import json, sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().split("\n")
for i, line in enumerate(lines):
    if line.startswith("var PDF_PAGE = "):
        page = json.loads(line[len("var PDF_PAGE = "):].rstrip().rstrip(";"))
        page = page.replace("var CEDAR = {", "var SOMETHING_ELSE = {")
        lines[i] = "var PDF_PAGE = " + json.dumps(page).replace("</", "<\\/") + ";"
open(path, "w", encoding="utf-8").write("\n".join(lines))
PYTAIL
check "a host whose own invoice cannot be found is refused, never dropped" "$(write_status "$D7C")" "1"

# 8. --check REPORTS DRIFT WITHOUT WRITING.
D8="$(fresh checkonly)"
damage "$D8" invoice-pdf.html 'settled ? "Paid in full" : "Amount due"' 'settled ? "Paid in full" : "Amount owed"'
BEFORE8="$(shasum -a 256 "$D8/review-send.html")"
check "--check exits 3 on drift" "$(write_status "$D8" --check)" "3"
check "and writes nothing" "$([ "$BEFORE8" = "$(shasum -a 256 "$D8/review-send.html")" ] && echo unchanged || echo changed)" "unchanged"

harness_end
