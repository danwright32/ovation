#!/bin/bash
# Whether the review sheet's samples can reach the installed app.
#
# ovation#318 B5. The sheet is looked at over invented invoices, because not one of
# the 31 real clients has a genuine override and nothing in the store is past its
# due date on purpose. Those samples are `#if DEBUG`, and `#if DEBUG` is a claim
# nobody checks: it is right until somebody moves a file, and the failure is
# invented client names and addresses inside the app Dan actually runs (L3, L535).
#
# THE TERMS COME FROM THE SOURCES, never a list written beside them, so a sample
# added tomorrow is covered without anybody remembering (L41, L96).
#
# AND THE CHECK IS PROVED ON THE DEBUG PRODUCT FIRST. A scan whose terms are wrong
# finds nothing in either build and reports the Release one clean, which is the
# reassuring direction (L159, L178). So the same terms must be FOUND in Debug.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "review samples absent tests" 15

TARGET="scripts/check-review-samples-absent.sh"
require_target "$TARGET"
harness_temp_dir WORK

# A tree with the two sources the terms are read from, and a place for products.
stage() {
    [ -n "$WORK" ] || exit 1
    local r="$WORK/$1"
    rm -rf "$r"
    mkdir -p "$r/Ovation/Document" "$r/products/Debug/Ovation.app/Contents/MacOS" \
             "$r/products/Release/Ovation.app/Contents/MacOS"
    cat > "$r/Ovation/Document/ReviewSamples.swift" <<'SOURCE'
#if DEBUG
enum ReviewSample: String, CaseIterable {
    var says: String {
        switch self {
        case .ordinary: return "Ordinary"
        case .pastDue: return "Past its due date"
        }
    }
}
#endif
SOURCE
    cat > "$r/Ovation/Document/ReviewSampleWorld.swift" <<'SOURCE'
#if DEBUG
enum ReviewSampleWorld {
    static let sampleClient = "A Client"
    static let sampleShoot = "Autumn Concert"
    static let sampleAddress = "booker@example.com"
}
#endif
SOURCE
    printf '%s' "$r"
}

# What a Debug binary holds: every term. What a Release binary holds: none.
write_binary() {
    local path="$1"; shift
    : > "$path"
    local term
    for term in "$@"; do printf 'x%sx\n' "$term" >> "$path"; done
    chmod +x "$path"
}

DEBUG_TERMS=("Past its due date" "Autumn Concert" "booker@example.com" "A Client")

run() {
    ( OVATION_REPO_ROOT="$1" OVATION_PRODUCTS_DIR="$1/products" \
        bash "$REPO_ROOT/$TARGET" 2>&1 )
}
REPO_ROOT="$PWD"

# ---------------------------------------------------------------------------
# THE GOOD CASE: Debug carries the samples, Release does not.
R1="$(stage clean)"
write_binary "$R1/products/Debug/Ovation.app/Contents/MacOS/Ovation" "${DEBUG_TERMS[@]}"  # never empty: DEBUG_TERMS is a literal of four
write_binary "$R1/products/Release/Ovation.app/Contents/MacOS/Ovation" "nothing to see"
OUT1="$(run "$R1")"; ST1=$?
check "a Release product with none of the samples passes" "$ST1" "0"
check "and it says how many terms it looked for, so a scan of nothing is visible" \
    "$(printf '%s' "$OUT1" | grep -cE '[0-9]+ sample term')" "1"

# ---------------------------------------------------------------------------
# THE FAULT: a sample reached the Release product.
R2="$(stage leaked)"
write_binary "$R2/products/Debug/Ovation.app/Contents/MacOS/Ovation" "${DEBUG_TERMS[@]}"  # never empty: DEBUG_TERMS is a literal of four
write_binary "$R2/products/Release/Ovation.app/Contents/MacOS/Ovation" "Autumn Concert"
OUT2="$(run "$R2")"; ST2=$?
check "a sample in the Release product refuses the run" \
    "$([ "$ST2" -ne 0 ] && echo refused || echo allowed)" "refused"
# NAMED BY WHERE IT IS DECLARED, never echoed: this runs in CI of a public
# repository and the terms are read out of source files (L222).
check "and it names where the term it found is declared" \
    "$(printf '%s' "$OUT2" | grep -c 'ReviewSampleWorld.swift line')" "1"
check "and it does not print the term itself" \
    "$(printf '%s' "$OUT2" | grep -c 'Autumn Concert')" "0"
check "and it is a fault here, not a cannot measure" "$ST2" "1"

# ---------------------------------------------------------------------------
# THE POSITIVE CONTROL IS PART OF THE CHECK (L159, L178). Terms that are in neither
# build prove nothing, and the Release product would pass for the wrong reason.
R3="$(stage terms-not-in-debug)"
write_binary "$R3/products/Debug/Ovation.app/Contents/MacOS/Ovation" "nothing at all"
write_binary "$R3/products/Release/Ovation.app/Contents/MacOS/Ovation" "nothing at all"
OUT3="$(run "$R3")"; ST3=$?
check "terms absent from the Debug product refuse, rather than passing quietly" \
    "$([ "$ST3" -ne 0 ] && echo refused || echo allowed)" "refused"
check "and it says the scan proved nothing rather than that Release is clean" \
    "$(printf '%s' "$OUT3" | grep -ci 'proves nothing\|could not be proved')" "1"

# ---------------------------------------------------------------------------
# NOTHING TO MEASURE IS ITS OWN ANSWER, and it is the gate's cannot measure code,
# because a machine that has not built anything is not a tree with a fault (L411).
R4="$(stage no-products)"
rm -rf "$R4/products"
OUT4="$(run "$R4")"; ST4=$?
check "with no products at all it answers cannot measure" "$ST4" "2"
check "and it says what would make it measurable" \
    "$(printf '%s' "$OUT4" | grep -c 'build-products.sh')" "1"

R5="$(stage no-release)"
write_binary "$R5/products/Debug/Ovation.app/Contents/MacOS/Ovation" "${DEBUG_TERMS[@]}"  # never empty: DEBUG_TERMS is a literal of four
rm -rf "$R5/products/Release"
OUT5="$(run "$R5")"; ST5=$?
check "with no Release product it answers cannot measure, not clean" "$ST5" "2"

# ---------------------------------------------------------------------------
# THE TERMS ARE DERIVED FROM THE SOURCES. A sample added to the app and not to any
# list has to be covered, which is the whole reason this reads the files (L41).
R6="$(stage derived)"
cat >> "$R6/Ovation/Document/ReviewSamples.swift" <<'SOURCE'
// A sample added later, with its own words.
let extra = "Brand new sample state"
SOURCE
write_binary "$R6/products/Debug/Ovation.app/Contents/MacOS/Ovation" \
    "${DEBUG_TERMS[@]}" "Brand new sample state"  # never empty: DEBUG_TERMS is a literal of four
write_binary "$R6/products/Release/Ovation.app/Contents/MacOS/Ovation" "Brand new sample state"
OUT6="$(run "$R6")"; ST6=$?
check "a term added to the sources is scanned for without being listed anywhere" \
    "$([ "$ST6" -ne 0 ] && echo refused || echo allowed)" "refused"
check "and the new term is named by its own line in the source" \
    "$(printf '%s' "$OUT6" | grep -c 'ReviewSamples.swift line')" "1"

# ---------------------------------------------------------------------------
# A TREE WITH NO SAMPLE SOURCES CANNOT BE JUDGED. Reporting a clean Release there
# would be a scan for nothing reported as a guarantee (L98).
R7="$(stage no-sources)"
rm -f "$R7/Ovation/Document/ReviewSamples.swift" "$R7/Ovation/Document/ReviewSampleWorld.swift"
write_binary "$R7/products/Debug/Ovation.app/Contents/MacOS/Ovation" "anything"
write_binary "$R7/products/Release/Ovation.app/Contents/MacOS/Ovation" "anything"
OUT7="$(run "$R7")"; ST7=$?
check "a tree with no sample sources refuses rather than reporting clean" \
    "$([ "$ST7" -ne 0 ] && echo refused || echo allowed)" "refused"
check "and it names the sources it could not read" \
    "$(printf '%s' "$OUT7" | grep -c 'ReviewSamples.swift')" "1"

harness_end
