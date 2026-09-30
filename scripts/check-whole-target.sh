#!/bin/bash
# Refuse a plain style button anywhere but the one style that gives it a hit area.
#
#     check-whole-target.sh
#
# ovation#615. A plain style button hit tests only what its label paints, so a
# row with a clear background answers a click on its words and nothing to the
# right of them. Dan met it in the rail on 2026-09-28, and the same dead space
# could sit behind every one of the app's 21 plain buttons, of which only the
# ones whose author happened to remember carried a content shape.
#
# WHY A SCAN AND A STYLE, NOT A SCAN FOR THE SHAPE. Whether a given button's
# label carries a content shape is a question about Swift's structure, and a
# line scan reading for it would be satisfied by a shape anywhere near the button
# rather than on its label (L135, L178). A behaviour each call site has to opt
# into cannot be enforced by reading the call sites at all (L621). So the shape
# lives in `WholeTarget`, which is the plain style with the label's content shape
# added, and what this refuses is the one thing a site cannot do without to skip
# it: naming the plain style itself (L613).
#
# NO SITE IS EXEMPT, and that was decided site by site rather than assumed: a
# word meant to be pressed on the word has a label whose frame IS the word, so
# the style costs it nothing. A future site that genuinely wants hit testing by
# what is painted is a change to this file with its reason, not a quiet line.
#
# COMMENTS ARE NOT READ. A line whose first characters are `//` is prose about
# the construct, and refusing it would refuse the explanation (L673).
#
# THE ALLOWED LIST IS ONE FILE and it must still do the job, or every other file
# is exempt by accident (L96, L98, L400).
set -uo pipefail

# The tree to judge, overridable so the suite can drive this over a STAGED tree
# rather than only over the repository it lives in (L1, L2).
REPO_ROOT="${OVATION_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
OWNER="Ovation/App/WholeTarget.swift"
# The plain style, however it is named: the shorthand, with or without spaces
# inside the parentheses, and the type itself.
PLAIN='buttonStyle\([[:space:]]*\.plain[[:space:]]*\)|PlainButtonStyle'

cd "$REPO_ROOT" || exit 1

if [ ! -f "$OWNER" ]; then
    echo "REFUSED: $OWNER is not there, so this guard is checking nothing."
    echo "    It names the one file allowed to use the plain button style."
    exit 1
fi

# The owner must still be the plain style WITH a content shape, or the guard is
# sending every site to a style that no longer gives them one.
if ! grep -Eq "$PLAIN" "$OWNER" || ! grep -q '\.contentShape(' "$OWNER"; then
    echo "REFUSED: $OWNER no longer draws the plain style with a content shape on"
    echo "         its label, so the style this guard sends every button to does not"
    echo "         do what it is for, and every other file is now exempt by accident."
    echo "         Either the component moved or its job changed; say which, here."
    exit 1
fi

found=0
while IFS= read -r file; do
    [ "$file" = "$OWNER" ] && continue
    lines="$(grep -nE "$PLAIN" "$file" | grep -vE '^[0-9]+:[[:space:]]*//')" || continue
    [ -z "$lines" ] && continue
    if [ "$found" -eq 0 ]; then
        echo "REFUSED: a plain style button outside WholeTarget. A plain button hit tests"
        echo "         only what its label paints, so a row with a clear background"
        echo "         answers on its words and nowhere else (ovation#615)."
        found=1
    fi
    while IFS= read -r line; do
        echo "    $file:${line%%:*}"
    done <<< "$lines"
done < <(find Ovation -name '*.swift' -type f | sort)

if [ "$found" -eq 1 ]; then
    echo "         Use .buttonStyle(WholeTarget()), or WholeTarget(shape) where the"
    echo "         label draws a shape of its own."
    exit 1
fi

echo "OK: every chromeless button in the app's Swift takes its clicks across its label, through $OWNER."
