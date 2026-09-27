#!/bin/bash
# Whether the one-tax-chip check can actually tell a second treatment from none.
#
# ovation#480, PRD 5a2. Every case drives the check over a STAGED tree rather
# than this repository, because a guard verified only against the current tree
# passes for as long as that tree happens to be clean and says nothing about
# what it would catch (L1, L2).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "one tax chip tests" 21

TARGET="scripts/check-one-tax-chip.sh"
require_target "$TARGET"
harness_temp_dir WORK

OWNER_BODY='struct TaxAnswerChips: View {
    let answers: [TaxStatus]
    var body: some View { HStack { ForEach(answers, id: \.self) { a in Text(a.exportLabel) } } }
}'

TAXPICK='.taxpick { font: inherit; font-size: 12px;
           padding: 2px 9px; border-radius: 5px; }
.taxpick:hover { background: var(--selbg); }
.taxpick:focus-visible { outline: 2px solid var(--accent); outline-offset: 1px; }'

# A STAGED TREE SHAPED LIKE THE REAL ONE: the Swift component and the design file
# that owns the chip's look, where the check expects them, plus whatever a case adds.
stage() {
    local root="$WORK/$1"
    rm -rf "$root"
    mkdir -p "$root/Ovation/Invoices" "$root/Ovation/Roster" "$root/docs/design"
    printf '%s\n' "$OWNER_BODY" > "$root/Ovation/Invoices/TaxAnswerChips.swift"
    printf '<!doctype html>\n<style>\n/* the one chip */\n%s\n</style>\n' "$TAXPICK" \
        > "$root/docs/design/invoice.html"
    printf '%s' "$root"
}

run_check() { OVATION_REPO_ROOT="$1" "./$TARGET" 2>&1; }
says() { if grep -qF -- "$2" <<< "$1"; then echo yes; else echo no; fi; }

# ---------------------------------------------------------------------------
# 1. THE TREE AS IT SHOULD BE: both screens use the component, and a second
#    design file carries the rule verbatim.
ROOT="$(stage clean)"
printf 'TaxAnswerChips(answers: TaxStatus.answers) { record($0) }\n' \
    > "$ROOT/Ovation/Roster/RosterPassView.swift"
printf '<!doctype html>\n<style>\n%s\n</style>\n' "$TAXPICK" > "$ROOT/docs/design/clients.html"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a tree with one chip passes" "$STATUS" "0"
check "and it names the component it allowed" "$(says "$OUT" "TaxAnswerChips.swift")" "yes"
check "and the design file whose chip is the one" "$(says "$OUT" "invoice.html")" "yes"

# ---------------------------------------------------------------------------
# 2. A SECOND SWIFT TREATMENT, which is the whole point: a screen drawing the
#    answers itself, whatever it calls its chip.
ROOT="$(stage second)"
printf 'HStack {\n    ForEach(TaxStatus.answers, id: \\.self) { s in\n        Button(s.exportLabel) {}\n    }\n}\n' \
    > "$ROOT/Ovation/Roster/RosterPassView.swift"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a screen drawing the answers itself is refused" "$STATUS" "1"
check "and the refusal names the file" "$(says "$OUT" "RosterPassView.swift")" "yes"
check "and the line it is on" "$(says "$OUT" "RosterPassView.swift:2")" "yes"
check "and what to use instead" "$(says "$OUT" "TaxAnswerChips(answers:press:)")" "yes"

# 3. THE SAME, REACHED THROUGH A QUESTION'S OWN LIST, which is how the invoice
#    screen holds its answers, and through the enum's whole list.
ROOT="$(stage question)"
printf 'ForEach(question.answers, id: \\.self) { a in chip(a) }\n' \
    > "$ROOT/Ovation/Invoices/InvoiceScreenView.swift"
printf 'ForEach(TaxStatus.allCases, id: \\.self) { a in chip(a) }\n' \
    > "$ROOT/Ovation/Roster/RosterPassView.swift"
OUT="$(run_check "$ROOT")"
check "a question's answers drawn by hand are named" "$(says "$OUT" "InvoiceScreenView.swift:1")" "yes"
check "and so are the enum's whole list drawn by hand" "$(says "$OUT" "RosterPassView.swift:1")" "yes"

# 4. A NEAR MISS IS NOT ACCUSED. A list of other answers drawn by hand, the
#    payment methods, is a different question and must pass, or the guard is one
#    people learn to skip.
ROOT="$(stage nearmiss)"
printf 'ForEach(PaymentMethod.allCases, id: \\.self) { m in Text(m.exportLabel) }\n' \
    > "$ROOT/Ovation/Invoices/PaymentSheet.swift"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "another question's list is not accused" "$STATUS" "0"

# ---------------------------------------------------------------------------
# 5. A DESIGN FILE WHOSE CHIP HAS DRIFTED from the owner's.
ROOT="$(stage drifted)"
printf '<!doctype html>\n<style>\n%s\n</style>\n' "${TAXPICK/2px 9px/3px 11px}" \
    > "$ROOT/docs/design/clients.html"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a design file whose chip differs is refused" "$STATUS" "1"
check "and the refusal names that file" "$(says "$OUT" "clients.html")" "yes"
check "and the rule that differs" "$(says "$OUT" ".taxpick")" "yes"

# 6. THE ROSTER'S RETIRED CHIP COMING BACK in any design file. A comment that
#    merely mentions chips is prose and is not accused.
ROOT="$(stage retired)"
printf '<!doctype html>\n<style>\n/* NO CHIPS: the chip said SEND */\n.chip { font-size: 12px; }\n.chip.on { color: red; }\n</style>\n' \
    > "$ROOT/docs/design/clients.html"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "the retired chip rule is refused" "$STATUS" "1"
check "and named with its file" "$(says "$OUT" "clients.html: .chip")" "yes"

ROOT="$(stage prose)"
printf '<!doctype html>\n<style>\n/* NO CHIPS: the chip said SEND */\n.row { color: red; }\n</style>\n' \
    > "$ROOT/docs/design/invoice-list.html"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a comment about chips is not a chip" "$STATUS" "0"

# ---------------------------------------------------------------------------
# 7. THE OWNERS MUST STILL CARRY THE SHAPE. An owner that has stopped matching is
#    exempting everything by accident (L96, L98, L400).
ROOT="$(stage gutted)"
printf 'struct TaxAnswerChips: View { var body: some View { EmptyView() } }\n' \
    > "$ROOT/Ovation/Invoices/TaxAnswerChips.swift"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a component that no longer draws the answers is refused" "$STATUS" "1"
check "and it says every other file is now exempt by accident" "$(says "$OUT" "exempt by")" "yes"

ROOT="$(stage nolook)"
printf '<!doctype html>\n<style>\n.other { color: red; }\n</style>\n' > "$ROOT/docs/design/invoice.html"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a design owner that no longer defines the chip is refused" "$STATUS" "1"
check "and it names the file that should" "$(says "$OUT" "invoice.html")" "yes"

# 8. AND A TREE WITH NO COMPONENT AT ALL IS REFUSED, rather than passing because
#    there is nothing left to compare against.
ROOT="$WORK/empty"
rm -rf "$ROOT"
mkdir -p "$ROOT/Ovation" "$ROOT/docs/design"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a tree with no component is refused" "$STATUS" "1"

harness_end
