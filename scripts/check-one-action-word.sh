#!/bin/bash
# Refuse a second hand rolled copy of the product's word-that-is-a-control.
#
#     check-one-action-word.sh
#
# ovation#450. A control in this product is a WORD carrying an underline at rest,
# which is the design record's own idiom and is deliberate: a control must look
# like a control before anybody points at it (L49). `ActionWord` is that word,
# and it also owns the other half of the pair, the quiet unpressable treatment a
# word gets when nothing does what it says yet.
#
# WHY A SCAN AND NOT A NOTE. There were exactly TWO hand rolled copies of the
# treatment when `ActionWord` was written, the invoice screen's Review and the
# invoice list's action, and they had already drifted: one carried a screen
# reader label saying why it could not be pressed and the other did not. A shared
# component that converts the site in front of whoever built it and leaves the
# rest standing is not consolidation, and the next screen either copies it by eye
# or invents its own (L613). The receipts queue, the review and send screen and
# the Clients screen are all still to be drawn and each of them wants this word.
#
# HOW A COPY IS RECOGNISED. Not by its name, which is the thing a copy changes,
# but by the one modifier it cannot do without: `.underline()`. That is what a
# hand rolled copy has to declare in order to look the same, whatever it calls
# itself, and it is the reason this is checkable at all.
#
# THE LIST OF ALLOWED SITES IS ONE FILE and it is not empty: `ActionWord.swift`
# itself. A guard whose allowed list is empty is one nobody would notice had
# stopped matching anything (L98).
set -uo pipefail

# The tree to judge, overridable so the suite can drive this over a STAGED tree
# rather than only over the repository it lives in: a guard verified against the
# current tree passes for as long as that tree happens to be clean and says
# nothing about what it would catch (L1, L2).
REPO_ROOT="${OVATION_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
OWNER="Ovation/Invoices/ActionWord.swift"

cd "$REPO_ROOT" || exit 1

if [ ! -f "$OWNER" ]; then
    echo "REFUSED: $OWNER is not there, so this guard is checking nothing."
    echo "    It names the one file allowed to draw an underlined control."
    exit 1
fi

# The owner must actually carry the thing, or the guard is exempting a file that
# no longer does the job and every other site is free (L96, L400).
if ! grep -q '\.underline()' "$OWNER"; then
    echo "REFUSED: $OWNER no longer draws an underline, so the shape this guard"
    echo "         recognises is not there and every other file is now exempt by"
    echo "         accident. Either the component moved or the idiom changed;"
    echo "         say which, here."
    exit 1
fi

found=0
while IFS= read -r file; do
    [ "$file" = "$OWNER" ] && continue
    lines="$(grep -n '\.underline()' "$file")" || continue
    [ -z "$lines" ] && continue
    if [ "$found" -eq 0 ]; then
        echo "REFUSED: a second hand rolled copy of the product's word-that-is-a-control."
        echo "         An underlined control is ActionWord and nothing else, so that the"
        echo "         pressable and the quiet treatments cannot drift apart (ovation#450)."
        found=1
    fi
    while IFS= read -r line; do
        echo "    $file:${line%%:*}"
    done <<< "$lines"
done < <(find Ovation -name '*.swift' -type f | sort)

if [ "$found" -eq 1 ]; then
    echo "         Use ActionWord(word:size:press:notYet:) instead."
    exit 1
fi

echo "OK: one underlined control in the app's Swift, and it is $OWNER."
