#!/bin/bash
# Whether the footer source check can actually tell the two apart.
#
# ovation#319. The check refuses a drawing or sending path that reads
# `InvoiceFooter.fixed` instead of what Dan wrote in Settings. Every case here
# drives it over a STAGED tree rather than this repository, because a guard
# verified only against the current tree passes for as long as that tree happens
# to be clean and says nothing about what it would catch (L1, L2).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "invoice footer source tests" 13

TARGET="scripts/check-invoice-footer-source.sh"
require_target "$TARGET"
harness_temp_dir WORK

# A STAGED TREE SHAPED LIKE THE REAL ONE: the three allowed files in the places
# the check names, plus whatever a case adds.
stage() {
    # stage <name>: prints the root of a fresh tree holding only the allowed files
    local root="$WORK/$1"
    rm -rf "$root"
    mkdir -p "$root/Ovation/Document" "$root/Ovation/App"
    printf 'struct InvoiceFooter { static let fixed = InvoiceFooter() }\n' \
        > "$root/Ovation/Document/InvoiceDocument.swift"
    printf 'let f = InvoiceFooter.fixed\n' \
        > "$root/Ovation/Document/InvoiceFooterSetting.swift"
    printf 'let d = try InvoiceDocument(invoice: i, footer: .fixed)\n' \
        > "$root/Ovation/Document/ReviewSampleWorld.swift"
    printf '%s' "$root"
}

run_check() {
    OVATION_REPO_ROOT="$1" "./$TARGET" 2>&1
}
says() { if grep -qF -- "$2" <<< "$1"; then echo yes; else echo no; fi; }

# ---------------------------------------------------------------------------
# 1. THE TREE AS IT SHOULD BE. Only the three allowed files mention it.
# ---------------------------------------------------------------------------
CLEAN="$(stage clean)"
OUT_CLEAN="$(run_check "$CLEAN")"; ST_CLEAN=$?
check "a tree where only the allowed files read the shipped text passes" "$ST_CLEAN" "0"
check "and it says how many files it actually scanned, so a scan of nothing is visible" \
    "$(says "$OUT_CLEAN" "Swift file(s) scanned")" "yes"

# ---------------------------------------------------------------------------
# 2. THE DEFECT. A view builds its page from the shipped text, which renders
#    perfectly and silently ignores everything Dan typed.
# ---------------------------------------------------------------------------
DIRTY="$(stage dirty)"
printf 'let document = try InvoiceDocument(invoice: invoice, footer: InvoiceFooter.fixed)\n' \
    > "$DIRTY/Ovation/App/InvoiceScreen.swift"
OUT_DIRTY="$(run_check "$DIRTY")"; ST_DIRTY=$?
check "a drawing path reading the shipped text is refused" "$ST_DIRTY" "1"
check "and the refusal names the file, so it can be found" \
    "$(says "$OUT_DIRTY" "App/InvoiceScreen.swift")" "yes"
check "and it names the remedy rather than only the fault" \
    "$(says "$OUT_DIRTY" "InvoiceFooterSetting")" "yes"

# 2b. THE SHORT SPELLING TOO. `footer: .fixed` is the same reference with the type
#     inferred, and a check matching only the long one would pass the commonest
#     way of writing it (L103).
SHORT="$(stage short)"
printf 'let document = try InvoiceDocument(invoice: invoice, footer: .fixed)\n' \
    > "$SHORT/Ovation/App/SendCommand.swift"
OUT_SHORT="$(run_check "$SHORT")"; ST_SHORT=$?
check "the inferred spelling is caught as well as the fully written one" "$ST_SHORT" "1"
check "and that refusal names its own file" \
    "$(says "$OUT_SHORT" "App/SendCommand.swift")" "yes"

# ---------------------------------------------------------------------------
# 3. EVERY ALLOWED FILE IS ALLOWED FOR ITS OWN REASON, so a list that had
#    quietly stopped covering one of them is caught here rather than by a
#    refusal on an untouched tree (L96).
# ---------------------------------------------------------------------------
for allowed in Document/InvoiceDocument.swift Document/InvoiceFooterSetting.swift \
               Document/ReviewSampleWorld.swift; do
    ONE="$(stage "allow-$(basename "$allowed" .swift)")"
    # Emptied of the others, so this case rests on THIS file being allowed rather
    # than on one of its neighbours carrying the reference (L135).
    : > "$ONE/Ovation/Document/InvoiceDocument.swift"
    : > "$ONE/Ovation/Document/InvoiceFooterSetting.swift"
    : > "$ONE/Ovation/Document/ReviewSampleWorld.swift"
    printf 'let f = InvoiceFooter.fixed\n' > "$ONE/Ovation/$allowed"
    run_check "$ONE" >/dev/null
    check "$allowed may read the shipped text" "$?" "0"
done

# ---------------------------------------------------------------------------
# 4. A TREE IT CANNOT READ IS NOT A CLEAN TREE. Both are their own outcome, and
#    neither may be mistaken for a pass: a scan that examined nothing reports
#    exactly what a scan that found nothing reports, unless it refuses (L98).
# ---------------------------------------------------------------------------
OUT_ABSENT="$(run_check "$WORK/no-such-tree")"; ST_ABSENT=$?
check "a missing source directory cannot be measured" "$ST_ABSENT" "2"
check "and it says nothing was scanned, rather than reporting a clean tree" \
    "$(says "$OUT_ABSENT" "CANNOT MEASURE")" "yes"

EMPTY="$WORK/empty-tree"
mkdir -p "$EMPTY/Ovation"
OUT_EMPTY="$(run_check "$EMPTY")"; ST_EMPTY=$?
check "a source directory holding no Swift files cannot be measured either" "$ST_EMPTY" "2"

harness_end
