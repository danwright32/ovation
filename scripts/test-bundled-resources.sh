#!/bin/bash
# The fonts, their licences and Dan's mark INSIDE the built apps are the files the
# manifest pins (ovation#167, plan A1).
#
# Ovation/Resources/bundled-resources.sha256 records the SHA-256 of every file
# bundled from outside this repository: the Lato and Merriweather fonts from
# google/fonts at a pinned commit, their OFL licences, and the cleaned vector
# mark. A manifest only checked against the source tree says what was committed,
# never what shipped, and the invoice PDF is drawn from whatever the BUNDLE holds
# (L416, L25). So this reads the copy inside each built app.
#
# THE MANIFEST IS THE ONLY LIST. The count below is derived from it, and a bundle
# missing a listed file fails by name rather than being skipped (L70, L96).
#
# SEEN TO FAIL (L1). Both bundles on this machine are correct, so a comparison only
# ever seen to pass has not been seen to work. One case copies a listed file, flips
# a single byte, and asserts the same comparison calls it different.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
. "$(dirname "$0")/lib/built-product.sh"

MANIFEST="Ovation/Resources/bundled-resources.sha256"
require_target "$MANIFEST"

# Every "<hash>  <path>" line, comments and blanks dropped.
ENTRIES="$(grep -Ev '^[[:space:]]*(#|$)' "$MANIFEST")"
NENTRIES="$(printf '%s\n' "$ENTRIES" | grep -c .)"
NCONFIGS=0
for _c in $BUILT_PRODUCT_CONFIGURATIONS; do NCONFIGS=$((NCONFIGS+1)); done

# One per entry against the tree, one per entry per built configuration, and the
# two cases that prove the comparison can say no.
harness_begin "bundled resource tests (${BUILT_PRODUCT_CONFIGURATIONS// /, })" \
    "$((NENTRIES + NENTRIES * NCONFIGS + 2))"
harness_temp_dir WORK

# A manifest that lists nothing checks nothing (L98).
if [ "$NENTRIES" -lt 1 ]; then
    harness_cannot_measure "$MANIFEST lists no files, so there is nothing to compare" \
        "restore the manifest from git"
fi

for CONFIG in $BUILT_PRODUCT_CONFIGURATIONS; do
    built_product_require "$CONFIG" "$(built_product_path "$CONFIG")/Ovation.app"
done

# The hash of a file, or a word that can never equal a hash when it is absent, so
# a missing file is a mismatch that names itself rather than an empty match.
hash_of() {
    if [ -f "$1" ]; then shasum -a 256 "$1" | awk '{ print $1 }'; else printf 'MISSING:%s' "$1"; fi
}

# THE COMMITTED FILES, so a resource changed without its manifest line fails here
# rather than first inside a bundle.
while read -r expected path; do
    check "the committed $path is the file the manifest pins" "$(hash_of "$path")" "$expected"
done <<< "$ENTRIES"

# THE BUILT COPIES. Xcode copies each resource flat into Contents/Resources, so the
# copy is found by its name alone.
for CONFIG in $BUILT_PRODUCT_CONFIGURATIONS; do
    RESOURCES="$(built_product_path "$CONFIG")/Ovation.app/Contents/Resources"
    while read -r expected path; do
        check "the $CONFIG app carries $(basename "$path") exactly as pinned" \
            "$(hash_of "$RESOURCES/$(basename "$path")")" "$expected"
    done <<< "$ENTRIES"
done

# THE COMPARISON CAN SAY NO. A single flipped byte and an absent file each read as
# different from the pinned hash.
read -r first_hash first_path <<< "$(printf '%s\n' "$ENTRIES" | head -1)"
cp "$first_path" "$WORK/flipped"
python3 - "$WORK/flipped" <<'PYFLIP'
import sys
path = sys.argv[1]
data = bytearray(open(path, "rb").read())
data[len(data) // 2] ^= 0x01
open(path, "wb").write(bytes(data))
PYFLIP
check "a copy with one byte flipped does not match the pinned hash" \
    "$([ "$(hash_of "$WORK/flipped")" = "$first_hash" ] && echo matched || echo different)" "different"
check "and an absent copy does not match it either" \
    "$([ "$(hash_of "$WORK/not-there")" = "$first_hash" ] && echo matched || echo different)" "different"

harness_end
