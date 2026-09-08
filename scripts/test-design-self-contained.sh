#!/bin/bash
# The suite for scripts/check-design-self-contained.sh.
#
# ovation#114. A guard is only real once it has been seen to fail (L1), and this
# one is a source level scanner over files that are mostly base64, which is the
# shape most likely to be subtly wrong in a way that matches nothing.
#
# THE CASE THAT DECIDES WHETHER THIS GUARD WORKS AT ALL is the healthy file: a
# design file is largely one enormous base64 font payload, and a naive search for
# `//` matches thousands of times inside one. So the payload is planted here, at
# a realistic size, and asserted CLEAN, in the same fixture as the reference it
# has to catch.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "design self containment tests" 20

TARGET="scripts/check-design-self-contained.sh"
require_target "$TARGET"
harness_temp_dir WORK

run_on() { OVATION_DESIGN_ROOT="$1" "./$TARGET" 2>&1; }
status_on() {
    OVATION_DESIGN_ROOT="$1" "./$TARGET" >/dev/null 2>&1
    printf '%s' "$?"
}

# A base64 blob shaped like a real font payload: the base64 alphabet only, long
# runs of `//` in it, and the substrings `src=` and `url` occurring by chance,
# every one of which a careless needle would match.
BLOB="$(head -c 60000 /dev/zero | tr '\0' 'A')d4//8AAAsrc=urlimport//////wAA+/+8"

design_file() {
    # $1 destination, $2 whatever goes in the head beyond the embedded face.
    cat > "$1" <<HTML
<!doctype html>
<meta charset="utf-8">
<style>
@font-face { font-family: "Archivo"; src: url(data:font/woff2;base64,$BLOB) format("woff2"); }
body { font-family: "Archivo", sans-serif; }
</style>
$2
<h1>An invoice</h1>
HTML
}

# ---------------------------------------------------------------------------
# The healthy file, which is the case that proves the needles are exact.
# ---------------------------------------------------------------------------
CLEAN="$WORK/clean"
mkdir -p "$CLEAN"
design_file "$CLEAN/invoice-list.html" ""
check "a file whose typefaces are embedded passes" "$(status_on "$CLEAN")" "0"
check "and it says how many files it actually looked at" \
    "$(run_on "$CLEAN" | grep -c 'scanned 1')" "1"

# ---------------------------------------------------------------------------
# THE CASE THE GUARD EXISTS FOR, planted in a file that also has the payload.
# ---------------------------------------------------------------------------
FONTS="$WORK/fonts"
mkdir -p "$FONTS"
design_file "$FONTS/invoice-list.html" \
    '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo">'
check "a stylesheet link to a font service is refused" "$(status_on "$FONTS")" "1"
check "and the refusal says it stops rendering offline" \
    "$(run_on "$FONTS" | grep -c 'stops rendering offline')" "1"
check "and it names the file and the line" \
    "$(run_on "$FONTS" | grep -c 'invoice-list.html:[0-9]')" "1"

# The other constructs that fetch, each its own fixture so no one of them can
# answer for the others.
SCRIPT="$WORK/script"; mkdir -p "$SCRIPT"
design_file "$SCRIPT/a.html" '<script src="https://cdn.example.com/chart.js"></script>'
check "a script from a CDN is refused" "$(status_on "$SCRIPT")" "1"

IMG="$WORK/img"; mkdir -p "$IMG"
design_file "$IMG/a.html" '<img src="https://example.com/logo.png" alt="">'
check "a remote image is refused" "$(status_on "$IMG")" "1"

IMPORTS="$WORK/imports"; mkdir -p "$IMPORTS"
design_file "$IMPORTS/a.html" '<style>@import "https://example.com/x.css";</style>'
check "an @import is refused" "$(status_on "$IMPORTS")" "1"

FETCH="$WORK/fetch"; mkdir -p "$FETCH"
design_file "$FETCH/a.html" '<script>fetch("/api/invoices").then(r => r.json());</script>'
check "a fetch at render time is refused" "$(status_on "$FETCH")" "1"
check "and it is named as a request rather than as a missing file" \
    "$(run_on "$FETCH" | grep -c 'makes a request at render time')" "1"

PROTOCOL="$WORK/protocol"; mkdir -p "$PROTOCOL"
design_file "$PROTOCOL/a.html" '<script src="//cdn.example.com/x.js"></script>'
check "a protocol relative URL is refused, which is the one a naive scan misses" \
    "$(status_on "$PROTOCOL")" "1"

# ---------------------------------------------------------------------------
# A LOCAL file reference is its own failure with its own sentence. It renders
# offline perfectly and still breaks the record, because the record is ONE
# document that opens from anywhere.
# ---------------------------------------------------------------------------
SHARED="$WORK/shared"; mkdir -p "$SHARED"
design_file "$SHARED/a.html" '<link rel="stylesheet" href="shell.css">'
printf 'body { margin: 0; }\n' > "$SHARED/shell.css"
check "a link to a sibling file is refused" "$(status_on "$SHARED")" "1"
check "and it is NOT reported as a network reference" \
    "$(run_on "$SHARED" | grep -c 'reaches the network')" "0"
check "it is reported as no longer being one document" \
    "$(run_on "$SHARED" | grep -c 'one self contained document')" "1"

# ---------------------------------------------------------------------------
# What must NOT be refused, or the guard is a nuisance and gets overridden.
# ---------------------------------------------------------------------------
ALLOWED="$WORK/allowed"; mkdir -p "$ALLOWED"
design_file "$ALLOWED/a.html" \
    '<a href="#totals">Totals</a><img src="data:image/gif;base64,R0lGODlhAQABAAAAACw=" alt="">'
check "a fragment link and a data image are fine" "$(status_on "$ALLOWED")" "0"

PROSE="$WORK/prose"; mkdir -p "$PROSE"
design_file "$PROSE/a.html" ""
printf 'See https://example.com/type for the licence.\n' > "$PROSE/README.md"
check "a URL in the README is not refused, because prose is not the record" \
    "$(status_on "$PROSE")" "0"

# ---------------------------------------------------------------------------
# Nothing to scan is not a pass.
# ---------------------------------------------------------------------------
check "a missing design root cannot measure" "$(status_on "$WORK/nowhere")" "2"
EMPTY="$WORK/empty"; mkdir -p "$EMPTY"
printf 'Only prose here.\n' > "$EMPTY/README.md"
check "a root holding no design files cannot measure" "$(status_on "$EMPTY")" "2"
check "and says so rather than reporting a self contained record" \
    "$(run_on "$EMPTY" | grep -c 'CANNOT SCAN')" "1"

# The real record, so the seam is not the only thing ever exercised.
check "the real design record passes" \
    "$(OVATION_DESIGN_ROOT= "./$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "0"

harness_end
