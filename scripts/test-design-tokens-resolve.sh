#!/bin/bash
# The suite for scripts/check-design-tokens-resolve.sh.
#
# ovation#120. The palette lived on `.win` until 2026-09-08, so every rule
# OUTSIDE the app window resolved `var(--anything)` to nothing: the Edit chip in
# the menu bar and the highlighted row in its menu both declare
# `background: var(--accent)` and both computed to `rgba(0, 0, 0, 0)`, so neither
# had ever painted. It was fixed in invoice.html and NOT in the two older files,
# which carried the fault for as long as nothing compared them.
#
# NO SOURCE READING CAN SEE THIS. Both halves are present and both are spelled
# correctly: a rule defines the token and a rule uses it. What is wrong is the
# RELATIONSHIP between the two elements at render time, and a token that is
# referenced but never defined leaves no error and no mark, so the declaration
# goes on reading as correct (L585). The only way to know is to render the page
# and ask the element what the token resolved to.
#
# WHAT IT ASSERTS. For every declaration in a design file that reads
# `var(--token)`, every element that rule matches must have that token resolve to
# something. An empty value means the definition is not on an ancestor.
#
# IT WOULD NOT HAVE CAUGHT THE FAULT ABOVE, and that was measured rather than
# assumed. Both older files were rebuilt with the palette back on `.win` and the
# check passed on each: invoice-list.html because nothing outside the window
# names a token, and invoice.html because the Edit chip that named var(--accent)
# is only in the DOM while the menu is OPEN. A rule matching no element resolves
# nothing, which is why this suite asserts those are REPORTED rather than passed
# over. Saying the check covers more than it does is how a gap becomes permanent
# (L400), so it is written here, in the suite, where the claim is made.
#
# IT NEEDS A BROWSER, and cannot pretend otherwise. With none it reports CANNOT
# MEASURE and exits 2, rather than running zero assertions and reading as a pass
# (L98, L411).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "design token resolution tests" 14

TARGET="scripts/check-design-tokens-resolve.sh"
require_target "$TARGET"
harness_temp_dir WORK

# The check answers 3 when it has nothing to render in, and that is established
# FIRST, or every assertion below would be measuring the absence of a browser
# rather than the presence of a defect. The status is captured on its own line:
# written as `if ! cmd; then [ "$?" = 3 ]` the `$?` is the negation's status.
OVATION_DESIGN_ROOT="$WORK/nothing-here" "./$TARGET" >/dev/null 2>&1
BROWSER_PROBE=$?
if [ "$BROWSER_PROBE" = "3" ]; then
    harness_cannot_measure \
        "no headless browser, so nothing can be rendered and no claim here proves anything" \
        "npx playwright install chromium, or set OVATION_HEADLESS_BROWSER"
fi

# EACH RECORD IS RENDERED ONCE (ovation#282), and its status and every sentence
# asked of it are read from that one run, which is quoted when an answer does not
# match. The run is kept beside the record it rendered, as <record>.out.
. "$(dirname "$0")/lib/rendered-run.sh"
judge() { rendered_run "$1" env OVATION_DESIGN_ROOT="$1" "./$TARGET"; }

# ---------------------------------------------------------------------------
# THE FAULT, exactly as it shipped: the token is defined on the window and used
# by a chip that is NOT inside the window. Both halves read as correct.
# ---------------------------------------------------------------------------
BROKEN="$WORK/broken"
mkdir -p "$BROKEN"
cat > "$BROKEN/invoice-list.html" <<'HTML'
<meta charset="utf-8">
<style>
.win { --accent: #3B2B21; }
.chip { background: var(--accent); }
.name { color: var(--accent); }
</style>
<div class="screen">
  <div class="menubar"><span class="chip">Edit</span></div>
  <div class="win"><span class="name">inside</span></div>
</div>
HTML
judge "$BROKEN"
check_rendered_status "a token used outside the element that defines it is refused" "$BROKEN" "1"
check_rendered_count "and the refusal names the token that did not resolve" \
    "$BROKEN" '--accent' "1"
check_rendered_count "and the refusal itself names the design file, not just the tally above it" \
    "$BROKEN" 'invoice-list.html: UNRESOLVED' "1"
check_rendered_count "and it names the rule whose element could not see it" \
    "$BROKEN" '\.chip' "1"
check_rendered_count "and it does not accuse the rule that CAN see it" \
    "$BROKEN" '\.name' "0"

# ---------------------------------------------------------------------------
# THE FIX, which is the same page with the palette moved up one element. This is
# the case that proves the check is not simply always refusing.
# ---------------------------------------------------------------------------
FIXED="$WORK/fixed"
mkdir -p "$FIXED"
cat > "$FIXED/invoice-list.html" <<'HTML'
<meta charset="utf-8">
<style>
.screen { --accent: #3B2B21; }
.chip { background: var(--accent); }
.name { color: var(--accent); }
</style>
<div class="screen">
  <div class="menubar"><span class="chip">Edit</span></div>
  <div class="win"><span class="name">inside</span></div>
</div>
HTML
judge "$FIXED"
check_rendered_status "the same page with the palette one element up passes" "$FIXED" "0"
check_rendered_count "and it says how many references it actually resolved" \
    "$FIXED" '[0-9][0-9]* token reference' "1"

# A page that uses no tokens at all measured nothing, and nothing measured is not
# a pass: it reports exactly what a page in perfect health reports (L98).
NOTOKENS="$WORK/notokens"
mkdir -p "$NOTOKENS"
printf '<meta charset="utf-8">\n<style>\n.chip { color: red; }\n</style>\n<span class="chip">x</span>\n' \
    > "$NOTOKENS/invoice-list.html"
judge "$NOTOKENS"
check_rendered_status "a design file referencing no token at all cannot measure" "$NOTOKENS" "2"
check_rendered_count "and says so rather than reporting every reference resolved" \
    "$NOTOKENS" 'CANNOT SCAN' "1"

# A rule that matches NO element resolves nothing, and treating that as a pass is
# how a check goes green over a page it never looked at.
UNMATCHED="$WORK/unmatched"
mkdir -p "$UNMATCHED"
cat > "$UNMATCHED/invoice-list.html" <<'HTML'
<meta charset="utf-8">
<style>
.screen { --accent: #3B2B21; }
.nothinghasthis { background: var(--accent); }
</style>
<div class="screen">x</div>
HTML
judge "$UNMATCHED"
check_rendered_count "a rule that matches no element is reported rather than passed over" \
    "$UNMATCHED" 'DRAWN BY NOTHING' "1"

# ---------------------------------------------------------------------------
# Nothing to compare is not a pass, and the two ways of having nothing are
# different faults with different remedies (L11).
# ---------------------------------------------------------------------------
judge "$WORK/nowhere"
check_rendered_status "a missing design root cannot measure" "$WORK/nowhere" "2"

NOHTML="$WORK/nohtml"
mkdir -p "$NOHTML"
judge "$NOHTML"
check_rendered_status "a record with no design file cannot measure" "$NOHTML" "2"
check_rendered_count "and names that as its own cause" "$NOHTML" 'no design file' "1"

# ---------------------------------------------------------------------------
# The real record, so the fixtures above are not the only thing ever measured. It
# holds the committed files to what they draw TODAY, at rest, which is a real
# guarantee and a smaller one than the note at the top of this file describes.
# ---------------------------------------------------------------------------
rendered_run "$WORK/committed" env OVATION_DESIGN_ROOT= "./$TARGET"
check_rendered_status "every token every committed design file references resolves where it is used" \
    "$WORK/committed" "0"

harness_end
