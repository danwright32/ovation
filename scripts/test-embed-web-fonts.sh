#!/bin/bash
# The suite for scripts/embed-web-fonts.py.
#
# ovation#115. Every refusal the script can make is PRODUCED here, because the
# whole value of this script over doing it by hand is that it refuses a face it
# could not verify, and a refusal that has never been seen to fire is not one
# (L1).
#
# NOTHING HERE TOUCHES THE NETWORK, and that is enforced rather than intended:
# OVATION_FONT_OFFLINE=1 makes the script REFUSE any URL that is not a local
# file, so a fixture written with an http URL by mistake fails loudly instead of
# quietly downloading a typeface (L2). One case asserts that refusal directly, so
# the isolation is itself tested rather than assumed.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "web font embedding tests" 22

TARGET="scripts/embed-web-fonts.py"
require_target "$TARGET"
harness_temp_dir WORK

export OVATION_FONT_OFFLINE=1
run_on() { "./$TARGET" "$1" 2>&1; }
out_of() { "./$TARGET" "$1" 2>/dev/null; }
status_on() { "./$TARGET" "$1" >/dev/null 2>&1; printf '%s' "$?"; }

# A real woff2 file begins `wOF2`. These fixtures are that magic followed by
# filler, which is everything the script actually verifies.
woff2() { { printf 'wOF2'; head -c "${2:-400}" /dev/zero | tr '\0' 'x'; } > "$1"; }
notwoff2() { printf '\x00\x01\x00\x00truetype-ish' > "$1"; }

woff2 "$WORK/archivo-latin.woff2"
woff2 "$WORK/archivo-cyrillic.woff2"
woff2 "$WORK/plex-latin.woff2" 600
notwoff2 "$WORK/archivo-truetype.bin"

# ---------------------------------------------------------------------------
# The ordinary case: several alphabets offered, latin taken.
# ---------------------------------------------------------------------------
cat > "$WORK/two-subsets.css" <<CSS
/* cyrillic */
@font-face {
  font-family: 'Archivo';
  font-style: normal;
  font-weight: 400;
  src: url($WORK/archivo-cyrillic.woff2) format('woff2');
  unicode-range: U+0301, U+0400-045F;
}
/* latin */
@font-face {
  font-family: 'Archivo';
  font-style: normal;
  font-weight: 400;
  font-display: swap;
  src: url($WORK/archivo-latin.woff2) format('woff2');
  unicode-range: U+0000-00FF;
}
CSS
check "a stylesheet with several subsets embeds successfully" \
    "$(status_on "$WORK/two-subsets.css")" "0"
check "and emits exactly one face, not one per alphabet" \
    "$(out_of "$WORK/two-subsets.css" | grep -c '@font-face')" "1"
check "and the face it emitted is a data URL, not a link" \
    "$(out_of "$WORK/two-subsets.css" | grep -c 'src: url(data:font/woff2;base64,')" "1"
check "and it carries no http reference of any kind" \
    "$(out_of "$WORK/two-subsets.css" | grep -c 'http')" "0"
check "and the unicode range travels with it" \
    "$(out_of "$WORK/two-subsets.css" | grep -c 'unicode-range: U+0000-00FF')" "1"
check "and font-display travels with it" \
    "$(out_of "$WORK/two-subsets.css" | grep -c 'font-display: swap')" "1"
check "and the report says how many raw bytes were embedded" \
    "$("./$TARGET" "$WORK/two-subsets.css" 2>&1 >/dev/null | grep -c 'raw byte')" "1"

# ---------------------------------------------------------------------------
# THE VARIABLE FONT. Google serves ONE file for every weight, and embedding it
# per declared weight carries the same bytes four times over.
# ---------------------------------------------------------------------------
cat > "$WORK/variable.css" <<CSS
/* latin */
@font-face {
  font-family: 'Archivo';
  font-style: normal;
  font-weight: 400;
  src: url($WORK/archivo-latin.woff2) format('woff2');
}
/* latin */
@font-face {
  font-family: 'Archivo';
  font-style: normal;
  font-weight: 700;
  src: url($WORK/archivo-latin.woff2) format('woff2');
}
CSS
check "one file serving two weights is embedded ONCE" \
    "$(out_of "$WORK/variable.css" | grep -c '@font-face')" "1"
check "and it is emitted as a weight RANGE rather than one of the two" \
    "$(out_of "$WORK/variable.css" | grep -c 'font-weight: 400 700')" "1"

# ---------------------------------------------------------------------------
# THE REFUSALS, each produced rather than reasoned about.
# ---------------------------------------------------------------------------
cat > "$WORK/no-latin.css" <<CSS
/* cyrillic */
@font-face {
  font-family: 'Archivo';
  font-style: normal;
  font-weight: 400;
  src: url($WORK/archivo-cyrillic.woff2) format('woff2');
}
CSS
check "a stylesheet with no latin subset is refused" "$(status_on "$WORK/no-latin.css")" "1"
check "and it says nothing was emitted rather than embedding another alphabet" \
    "$(run_on "$WORK/no-latin.css" | grep -c 'another alphabet')" "1"
check "and it emits no font-face at all" \
    "$(out_of "$WORK/no-latin.css" | grep -c '@font-face')" "0"

# THREE WAYS TO FIND NO LATIN FACE, and they need three sentences, because the
# remedies are opposite: a different URL against this script needing teaching.
cat > "$WORK/unlabelled.css" <<CSS
@font-face {
  font-family: 'Archivo';
  font-style: normal;
  font-weight: 400;
  src: url($WORK/archivo-latin.woff2) format('woff2');
}
CSS
check "faces with no subset comment at all are refused" \
    "$(status_on "$WORK/unlabelled.css")" "1"
check "and NOT as a family with no latin subset, which is different work" \
    "$(run_on "$WORK/unlabelled.css" | grep -c 'not one carries a subset comment')" "1"

printf 'body { margin: 0; }\n' > "$WORK/nofaces.css"
check "a stylesheet declaring no face at all says THAT" \
    "$(run_on "$WORK/nofaces.css" | grep -c 'declares no @font-face at all')" "1"

cat > "$WORK/not-woff2.css" <<CSS
/* latin */
@font-face {
  font-family: 'Archivo';
  font-style: normal;
  font-weight: 400;
  src: url($WORK/archivo-truetype.bin) format('woff2');
}
CSS
check "a payload that is not woff2 is refused" "$(status_on "$WORK/not-woff2.css")" "1"
check "and the refusal says WHY it is not merely emitted" \
    "$(run_on "$WORK/not-woff2.css" | grep -c 'still looks finished')" "1"

cat > "$WORK/two-files.css" <<CSS
/* latin */
@font-face {
  font-family: 'Archivo';
  font-style: normal;
  font-weight: 400;
  src: url($WORK/archivo-latin.woff2) format('woff2');
}
/* latin */
@font-face {
  font-family: 'Archivo';
  font-style: normal;
  font-weight: 400;
  src: url($WORK/plex-latin.woff2) format('woff2');
}
CSS
check "one family, weight and style served by two files is refused" \
    "$(status_on "$WORK/two-files.css")" "1"
check "and it says to narrow the request rather than choosing one" \
    "$(run_on "$WORK/two-files.css" | grep -c 'nobody chose')" "1"

# ---------------------------------------------------------------------------
# THE ISOLATION ITSELF. A seam a test is merely expected to set is not
# isolation, so the refusal that enforces it is exercised (L2, L246).
# ---------------------------------------------------------------------------
cat > "$WORK/remote.css" <<CSS
/* latin */
@font-face {
  font-family: 'Archivo';
  font-style: normal;
  font-weight: 400;
  src: url(https://fonts.gstatic.com/s/archivo/v19/latin.woff2) format('woff2');
}
CSS
# THE SECOND ASSERTION IS THE LOAD BEARING ONE, and that was measured rather
# than assumed: deleting the offline guard and re-running leaves the exit code at
# 1, because the fetch then really happens and can fail on its own. A test
# satisfied by any failure is satisfied by its own fixture failing (L140), so the
# refusal is identified by what it SAYS.
check "a remote payload is REFUSED offline rather than downloaded" \
    "$(status_on "$WORK/remote.css")" "1"
check "and it names the reason it refused rather than a network error" \
    "$(run_on "$WORK/remote.css" | grep -c 'OVATION_FONT_OFFLINE is set')" "1"

check "a stylesheet that is not there cannot be read" "$(status_on "$WORK/nowhere.css")" "2"

harness_end
