#!/bin/bash
# Whether the one-action-word check can actually tell a second copy from none.
#
# ovation#450. Every case here drives the check over a STAGED tree rather than
# this repository, because a guard verified only against the current tree passes
# for as long as that tree happens to be clean and says nothing at all about what
# it would catch (L1, L2).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "one action word tests" 11

TARGET="scripts/check-one-action-word.sh"
require_target "$TARGET"
harness_temp_dir WORK

OWNER_BODY='struct ActionWord: View { var body: some View { Text("x").underline() } }'

# A STAGED TREE SHAPED LIKE THE REAL ONE: the component where the check expects
# it, plus whatever a case adds.
stage() {
    local root="$WORK/$1"
    rm -rf "$root"
    mkdir -p "$root/Ovation/Invoices"
    printf '%s\n' "$OWNER_BODY" > "$root/Ovation/Invoices/ActionWord.swift"
    printf '%s' "$root"
}

run_check() { OVATION_REPO_ROOT="$1" "./$TARGET" 2>&1; }
says() { if printf '%s' "$1" | grep -qF -- "$2"; then echo yes; else echo no; fi; }

# ---------------------------------------------------------------------------
# 1. THE TREE AS IT SHOULD BE.
ROOT="$(stage clean)"
mkdir -p "$ROOT/Ovation/Roster"
printf 'Text("Send").font(.system(size: 12))\n' > "$ROOT/Ovation/Roster/ShellView.swift"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a tree with one underlined control passes" "$STATUS" "0"
check "and it names the file it allowed" "$(says "$OUT" "ActionWord.swift")" "yes"

# ---------------------------------------------------------------------------
# 2. A SECOND COPY, WHICH IS THE WHOLE POINT.
ROOT="$(stage second)"
printf 'Text(action)\n    .underline()\n' > "$ROOT/Ovation/Invoices/InvoiceListView.swift"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a second underlined control is refused" "$STATUS" "1"
check "and the refusal names the file" "$(says "$OUT" "InvoiceListView.swift")" "yes"
check "and the line it is on" "$(says "$OUT" "InvoiceListView.swift:2")" "yes"
check "and what to use instead" "$(says "$OUT" "ActionWord(word:size:press:notYet:)")" "yes"

# ---------------------------------------------------------------------------
# 3. MORE THAN ONE COPY IS ALL REPORTED, not only the first. A guard that stops
#    at the first sends somebody back round once for each one.
ROOT="$(stage several)"
mkdir -p "$ROOT/Ovation/Document"
printf 'Text(a).underline()\n' > "$ROOT/Ovation/Invoices/InvoiceListView.swift"
printf 'Text(b).underline()\n' > "$ROOT/Ovation/Document/ReviewSheet.swift"
OUT="$(run_check "$ROOT")"
check "the first of two copies is named" "$(says "$OUT" "InvoiceListView.swift")" "yes"
check "and so is the second" "$(says "$OUT" "ReviewSheet.swift")" "yes"

# ---------------------------------------------------------------------------
# 4. THE OWNER MUST STILL CARRY THE SHAPE. A guard whose allowed file has stopped
#    matching is exempting everything by accident, and it would pass a tree in
#    which nothing draws a control at all (L96, L98, L400).
ROOT="$(stage gutted)"
printf 'struct ActionWord: View { var body: some View { Text("x") } }\n' \
    > "$ROOT/Ovation/Invoices/ActionWord.swift"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "an owner that no longer draws the shape is refused" "$STATUS" "1"
check "and it says every other file is now exempt by accident" \
      "$(says "$OUT" "exempt by")" "yes"

# ---------------------------------------------------------------------------
# 5. AND A TREE WITH NO COMPONENT AT ALL IS REFUSED, rather than passing because
#    there is nothing left to compare against.
ROOT="$WORK/empty"
rm -rf "$ROOT"
mkdir -p "$ROOT/Ovation"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a tree with no component is refused" "$STATUS" "1"

harness_end
