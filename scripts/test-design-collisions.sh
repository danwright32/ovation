#!/bin/bash
# The suite for scripts/check-design-collisions.py.
#
# ovation#132. This script's own docstring records that the fault it catches
# shipped FOUR TIMES IN ONE DAY, and that a 24 entry reuse list was found to be
# passing five rounds while the real overlap was seven names: the list had not
# been checked, it had merely been long. Nothing ran it and nothing tested it.
# Both completeness rules were blind to it twice over, because they match
# `check-*.sh` and this is Python.
#
# ITS JUDGEMENTS ARE THE KIND THAT GO SUBTLY WRONG, which is why every outcome
# below is driven and named rather than only the refusal.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "design collision tests" 22

TARGET="scripts/check-design-collisions.py"
require_target "$TARGET"
harness_temp_dir WORK

SETTLED="$WORK/settled.css"
ROUND="$WORK/round.css"

run() { python3 "$TARGET" "$@" 2>&1; }
status() { python3 "$TARGET" "$@" >/dev/null 2>&1; printf '%s' "$?"; }

cat > "$SETTLED" <<'CSS'
/* The settled stylesheet. The comment names .fromacomment, which is not a
   declaration and must never be read as one. */
.row { display: grid; }
.nrow { padding: 7px 16px; }
.titlebar { height: 38px; }
CSS

# ---------------------------------------------------------------------------
# 1. A COLLISION THE ROUND DID NOT DECLARE, refused by name.
# ---------------------------------------------------------------------------
cat > "$ROUND" <<'CSS'
.nrow { padding: 0; }
.myown { color: red; }
CSS
check "a class the settled sheet already defines is refused" \
    "$(status "$SETTLED" "$ROUND")" "1"
check "and it is named" "$(run "$SETTLED" "$ROUND" | grep -c '^  \.nrow$')" "1"
check "and the round's own class is not accused" \
    "$(run "$SETTLED" "$ROUND" | grep -c '^  \.myown$')" "0"
check "and the refusal says what to do about it" \
    "$(run "$SETTLED" "$ROUND" | grep -c 'Rename them, or declare them')" "1"

# ---------------------------------------------------------------------------
# 2. THE SAME CLASS, DECLARED. Reusing the settled design on purpose is how a
#    round inherits it.
# ---------------------------------------------------------------------------
check "the same collision declared as deliberate is accepted" \
    "$(status "$SETTLED" "$ROUND" --reuse nrow)" "0"
check "and the count says how many were shared and declared" \
    "$(run "$SETTLED" "$ROUND" --reuse nrow | grep -c '1 shared and every one of them declared')" "1"

# ---------------------------------------------------------------------------
# 3. A REUSE ENTRY THAT EXCUSES NOTHING. The long list this script's header
#    warns about, one entry at a time (L96, L233).
# ---------------------------------------------------------------------------
check "a reuse entry naming a class neither sheet defines is refused" \
    "$(status "$SETTLED" "$ROUND" --reuse nrow,neverheardofit)" "3"
check "and it has its own exit code, not the collision one" \
    "$([ "$(status "$SETTLED" "$ROUND" --reuse nrow,neverheardofit)" != "1" ] && echo different)" "different"
check "and the stale entry is named" \
    "$(run "$SETTLED" "$ROUND" --reuse nrow,neverheardofit | grep -c '^  \.neverheardofit$')" "1"
check "an entry the ROUND defines but the settled sheet does not is stale too" \
    "$(status "$SETTLED" "$ROUND" --reuse nrow,myown)" "3"
check "a collision is reported BEFORE a stale entry, because it is what stops the round" \
    "$(status "$SETTLED" "$ROUND" --reuse neverheardofit)" "1"

# ---------------------------------------------------------------------------
# 4. A ROUND WITH NO COLLISIONS AT ALL, and it says how much it compared,
#    because a comparison of nothing reads exactly like a clean one (L98).
# ---------------------------------------------------------------------------
cat > "$ROUND" <<'CSS'
.mine { color: red; }
.alsomine { color: blue; }
CSS
check "a round that collides with nothing is accepted" "$(status "$SETTLED" "$ROUND")" "0"
check "and says how many classes were on each side" \
    "$(run "$SETTLED" "$ROUND" | grep -c '2 class(es) in the round against 3 in the settled')" "1"

EMPTY="$WORK/empty.css"
printf '/* nothing but a comment */\n' > "$EMPTY"
check "a round defining nothing is accepted, and says so with a zero" \
    "$(run "$SETTLED" "$EMPTY" | grep -c '0 class(es) in the round')" "1"
check "and a settled sheet defining nothing says that too, rather than reading as clean" \
    "$(run "$EMPTY" "$ROUND" | grep -c 'against 0 in the settled')" "1"

# A CLASS NAMED IN A COMMENT IS NOT A DECLARATION. The stripper is the one thing
# here that can be silently wrong in the direction of passing.
cat > "$ROUND" <<'CSS'
.fromacomment { color: red; }
CSS
check "a class named only in the settled sheet's comments is not a collision" \
    "$(status "$SETTLED" "$ROUND")" "0"

# ---------------------------------------------------------------------------
# 5. A STYLESHEET THAT IS NOT THERE. An absent sheet defines nothing, so it
#    collides with nothing, and a mistyped path would report exactly what a
#    clean round reports (L98, L320).
# ---------------------------------------------------------------------------
check "a settled sheet that is not there is refused, never read as empty" \
    "$(status "$WORK/nowhere.css" "$ROUND")" "2"
check "and so is a round that is not there" \
    "$(status "$SETTLED" "$WORK/nowhere.css")" "2"
check "and the refusal names the path" \
    "$(run "$WORK/nowhere.css" "$ROUND" | grep -c 'no stylesheet at')" "1"
check "and says why that is not a clean round" \
    "$(run "$WORK/nowhere.css" "$ROUND" | grep -c 'That is not a clean round')" "1"

check "called with no arguments it says how to call it" "$(status)" "2"
check "and --reuse with nothing after it is used wrongly rather than empty" \
    "$(status "$SETTLED" "$ROUND" --reuse)" "2"

harness_end
