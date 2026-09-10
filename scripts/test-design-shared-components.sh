#!/bin/bash
# The suite for scripts/check-design-shared-components.sh.
#
# ovation#149. This guard exists because a shared component created to end N
# copies converts the site in front of whoever built it and leaves the rest
# standing (L613), and it recognises a copy by its SHAPE rather than its name,
# which is the thing a copy changes. So the cases that decide whether it is
# worth anything are the near misses: something absolutely positioned that holds
# no choices, and a list of choices that is not positioned. Neither is a popup
# list, and a guard that accused either would be one people learn to skip.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "shared component tests" 18

TARGET="scripts/check-design-shared-components.sh"
require_target "$TARGET"
harness_temp_dir WORK

run_on() { OVATION_DESIGN_ROOT="$1" python3 "$TARGET" 2>&1; }
status_on() {
    OVATION_DESIGN_ROOT="$1" python3 "$TARGET" >/dev/null 2>&1
    printf '%s' "$?"
}

record() {
    # $1 name, $2 the CSS the design file carries. Returns the root.
    local at="$WORK/$1"
    mkdir -p "$at"
    { printf '<!doctype html>\n<meta charset="utf-8">\n<style>\n'
      printf '%s' "$2"
      printf '\n</style>\n<div class="screen"></div>\n'
    } > "$at/screen.html"
    printf '%s' "$at"
}

# ---------------------------------------------------------------------------
# The shared one, used, which must never be accused.
# ---------------------------------------------------------------------------
SHARED="$(record shared '
.poplist { position: absolute; z-index: 6; background: #F7F4F1; }
.poplist button { display: block; width: 100%; text-align: left; }
')"
check "the shared component itself passes" "$(status_on "$SHARED")" "0"
check "and the count says it was found in use" \
    "$(run_on "$SHARED" | grep -c '1 use(s) of the shared one')" "1"

# ---------------------------------------------------------------------------
# THE CASE THIS EXISTS FOR: a second one, under a different name.
# ---------------------------------------------------------------------------
SECOND="$(record second '
.poplist { position: absolute; z-index: 6; }
.poplist button { display: block; }
.choicelist { position: absolute; border-radius: 6px; }
.choicelist button { display: block; text-align: left; }
')"
check "a second popup list under another name is refused" "$(status_on "$SECOND")" "1"
check "and it is named" "$(run_on "$SECOND" | grep -c '\.choicelist')" "1"
check "and the shared one is not accused alongside it" \
    "$(run_on "$SECOND" | grep -c 'is \.poplist and is not the shared')" "0"
check "and the refusal names the shared one to use instead" \
    "$(run_on "$SECOND" | grep -c 'is not the shared one, `.poplist`')" "1"
check "and it says why, rather than only that a rule was broken" \
    "$(run_on "$SECOND" | grep -c 'merged them into `.poplist` in the same change')" "1"

# A copy that keeps the SHAPE and changes everything else is still caught, which
# is the whole reason the shape is what is matched.
RENAMED="$(record renamed '
.duelist { position: absolute; inset-block-end: 100%; padding: 5px 0; }
.duelist a { display: block; padding: 4px 16px; }
')"
check "a copy using another element for its choices is caught too" \
    "$(status_on "$RENAMED")" "1"
check "and named, once, in the line that reports it" \
    "$(run_on "$RENAMED" | grep -c '^  screen.html: `.duelist`')" "1"

# ---------------------------------------------------------------------------
# THE NEAR MISSES. A guard that accused either of these is one people skip.
# ---------------------------------------------------------------------------
PANEL="$(record panel '
.sheetveil { position: absolute; inset: 0; background: rgba(31,24,18,.14); }
.sheetveil p { margin: 0; }
')"
check "something absolutely positioned that holds no choices is not a popup list" \
    "$(status_on "$PANEL")" "0"

INFLOW="$(record inflow '
.sidebar { display: flex; flex-direction: column; }
.sidebar button { display: block; width: 100%; }
')"
check "a list of choices that is not positioned is not one either" \
    "$(status_on "$INFLOW")" "0"

COMMENTED="$(record commented '
/* .choicelist { position: absolute; } and .choicelist button, in a comment. */
.poplist { position: absolute; }
.poplist button { display: block; }
')"
check "a class named only in a comment is not an implementation" \
    "$(status_on "$COMMENTED")" "0"

# A SECOND DOCUMENT CARRIED INSIDE A SCRIPT is not this page's CSS.
# `review-send.html` embeds the whole invoice PDF as a string (PRD 10c).
EMBEDDED="$WORK/embedded"
mkdir -p "$EMBEDDED"
cat > "$EMBEDDED/screen.html" <<'HTML'
<!doctype html>
<meta charset="utf-8">
<style>
.poplist { position: absolute; }
.poplist button { display: block; }
</style>
<script>
var OTHER_PAGE = "<style>.otherlist { position: absolute; } .otherlist button { display: block; }</style>";
</script>
HTML
check "a document embedded in a script is not read as this page's CSS" \
    "$(status_on "$EMBEDDED")" "0"

# ---------------------------------------------------------------------------
# NOTHING SCANNED IS NOT A PASS (L98).
# ---------------------------------------------------------------------------
check "an empty design root cannot measure" "$(status_on "$WORK/nowhere")" "2"
check "and says so rather than reporting health" \
    "$(run_on "$WORK/nowhere" | grep -c 'CANNOT MEASURE')" "1"
check "a named file that is not there is refused, never skipped" \
    "$(python3 "$TARGET" "$WORK/nowhere.html" >/dev/null 2>&1; printf '%s' "$?")" "2"

# ---------------------------------------------------------------------------
# The committed record, which is the run the push gate makes.
# ---------------------------------------------------------------------------
check "the committed design record passes" \
    "$(python3 "$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "0"
check "and it scanned every file rather than one" \
    "$(python3 "$TARGET" 2>&1 | grep -c '5 design file(s) scanned')" "1"

harness_end
