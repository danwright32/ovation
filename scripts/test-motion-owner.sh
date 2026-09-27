#!/bin/bash
# The suite for scripts/check-motion-owner.sh.
#
# ovation#124. Every case runs against a THROWAWAY scan root through the script's
# own seams, and the real sources are scanned once, deliberately, because a seam
# that hides the real path from every test leaves the real path untested (L246).
#
# THE TOKENS ARE NOT LISTED HERE. They are read from the check itself, so a token
# added to it is exercised by this suite without anybody remembering to come back,
# and a token cannot be forbidden by a rule nothing drives (L41, L217).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "motion owner tests" 25

TARGET="scripts/check-motion-owner.sh"
require_target "$TARGET"
harness_temp_dir WORK

OWNER="Roster/OvationMotion.swift"

run_on() {
    OVATION_MOTION_SCAN_ROOT="$1" OVATION_MOTION_OWNER="${2:-$OWNER}" "./$TARGET" 2>&1
}
status_on() {
    OVATION_MOTION_SCAN_ROOT="$1" OVATION_MOTION_OWNER="${2:-$OWNER}" "./$TARGET"
}

# A tree with an owner that owns motion, the way the real one does.
stage_owner() {
    mkdir -p "$1/Roster"
    cat > "$1/$OWNER" <<'SWIFT'
enum OvationMotion {
    static func animation(_ kind: Kind, reduceMotion: Bool) -> Animation? { nil }
}
struct Reader {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func run(_ kind: OvationMotion.Kind, _ change: () -> Void) {
        withAnimation(OvationMotion.animation(kind, reduceMotion: reduceMotion), change)
    }
}
SWIFT
}

# A screen that asks for motion the way it is supposed to.
stage_good_screen() {
    mkdir -p "$1/App"
    printf 'struct Panel: View {\n    var body: some View { list.ovationMotion(.slide, value: open) }\n}\n' \
        > "$1/App/Panel.swift"
}

# ---------------------------------------------------------------------------
# The clean case.
# ---------------------------------------------------------------------------
CLEAN="$WORK/clean"
stage_owner "$CLEAN"
stage_good_screen "$CLEAN"
check_exit "a tree where only the owner writes motion passes" 0 status_on "$CLEAN"
check "and it says how many files it scanned" \
    "$(run_on "$CLEAN" | grep -c 'scanned 2 Swift file')" "1"
check "and it NAMES the owner, so a pass says what it was measured against" \
    "$(run_on "$CLEAN" | grep -c "$OWNER")" "1"

# ---------------------------------------------------------------------------
# THE CASE THE CHECK EXISTS FOR: motion written on a screen.
# ---------------------------------------------------------------------------
RAW="$WORK/raw"
stage_owner "$RAW"
mkdir -p "$RAW/App"
printf 'func open() {\n    withAnimation(.easeInOut(duration: 0.3)) { showing = true }\n}\n' \
    > "$RAW/App/Screen.swift"
check_exit "withAnimation on a screen is refused" 1 status_on "$RAW"
check "the refusal names the file, the line and the construct" \
    "$(run_on "$RAW" | grep -c 'App/Screen.swift:2: withAnimation')" "1"
check "the refusal does NOT print the source line" \
    "$(run_on "$RAW" | grep -c 'easeInOut')" "0"
check "and it names the component to use instead" \
    "$(run_on "$RAW" | grep -c 'OvationMotion')" "1"

MODIFIER="$WORK/modifier"
stage_owner "$MODIFIER"
mkdir -p "$MODIFIER/App"
printf 'var body: some View { list.animation(.default, value: open) }\n' \
    > "$MODIFIER/App/Screen.swift"
check_exit ".animation on a screen is refused too" 1 status_on "$MODIFIER"

TRANSITION="$WORK/transition"
stage_owner "$TRANSITION"
mkdir -p "$TRANSITION/App"
printf 'var body: some View { pane.transition(.move(edge: .trailing)) }\n' \
    > "$TRANSITION/App/Screen.swift"
check_exit ".transition on a screen is refused too" 1 status_on "$TRANSITION"

# ---------------------------------------------------------------------------
# THE REDUCE MOTION ANSWER IS THE OWNER'S TOO, and it is its own finding with its
# own sentence, because a screen reading the setting itself is a different mistake
# from a screen animating: it is how a second, quieter answer to the same question
# gets written (L11).
# ---------------------------------------------------------------------------
SETTING="$WORK/setting"
stage_owner "$SETTING"
mkdir -p "$SETTING/App"
printf 'struct Screen: View {\n    @Environment(\\.accessibilityReduceMotion) private var reduced\n}\n' \
    > "$SETTING/App/Screen.swift"
check_exit "reading accessibilityReduceMotion on a screen is refused" 1 status_on "$SETTING"
check "and that refusal is worded as its own finding, not as an animation" \
    "$(run_on "$SETTING" | grep -c 'reduce motion answer')" "1"

# ---------------------------------------------------------------------------
# What is NOT a finding.
# ---------------------------------------------------------------------------
COMMENT="$WORK/comment"
stage_owner "$COMMENT"
mkdir -p "$COMMENT/App"
printf '// Never call withAnimation here: go through OvationMotion (ovation#124).\n' \
    > "$COMMENT/App/Screen.swift"
check_exit "a comment naming the construct is not a finding" 0 status_on "$COMMENT"

STRING="$WORK/string"
stage_owner "$STRING"
mkdir -p "$STRING/App"
printf 'let hint = "withAnimation belongs in OvationMotion"\n' > "$STRING/App/Screen.swift"
check_exit "a construct spelled only inside a string is not a finding" 0 status_on "$STRING"

WORD="$WORK/word"
stage_owner "$WORD"
mkdir -p "$WORD/App"
printf 'let animationless = true\nfunc withAnimationDisabled() {}\n' > "$WORD/App/Screen.swift"
check_exit "a longer name that merely contains the word is not a finding" 0 status_on "$WORD"

# The owner may write whatever it likes, which is the point of it existing.
ONLYOWNER="$WORK/only-owner"
stage_owner "$ONLYOWNER"
check_exit "the owner writing every forbidden construct passes" 0 status_on "$ONLYOWNER"

# ---------------------------------------------------------------------------
# THE TOKENS ARE DRIVEN FROM THE CHECK'S OWN LIST (L41, L217). Each one is put on
# a screen and must be refused, so a token added to the check cannot be forbidden
# by a rule this suite never exercises.
# ---------------------------------------------------------------------------
EVERY="$WORK/every"
stage_owner "$EVERY"
mkdir -p "$EVERY/App"
MISSED=""
while IFS= read -r token; do
    [ -n "$token" ] || continue
    printf 'let x = thing.%s()\n' "$token" > "$EVERY/App/Screen.swift"
    said="$(status_on "$EVERY" 2>&1)"; [ "$?" = "1" ] || MISSED="$MISSED $token"
done < <("./$TARGET" --list)
check "every construct the check lists is refused when a screen writes it" \
    "$(printf '%s' "$MISSED")" ""
check "and the list is not empty, so that case compared something" \
    "$([ "$("./$TARGET" --list | grep -c .)" -ge 4 ] && echo listed || echo empty)" "listed"

# ---------------------------------------------------------------------------
# NOTHING SCANNED IS NOT A PASS (L98), and NEITHER IS AN OWNER THAT IS NOT THERE.
# ---------------------------------------------------------------------------
EMPTY="$WORK/empty"
mkdir -p "$EMPTY"
check_exit "a root holding no Swift files refuses rather than passing" 2 status_on "$EMPTY"
check_exit "a root that is not there refuses with the same exit code" \
    2 status_on "$WORK/not-here"

GONE="$WORK/gone"
mkdir -p "$GONE/App"
printf 'struct Screen: View {}\n' > "$GONE/App/Screen.swift"
check_exit "an owner that is not there is its own refusal, never a clean tree" \
    3 status_on "$GONE"
check "and it says the owner is missing rather than reporting a clean scan" \
    "$(run_on "$GONE" | grep -c 'owns motion, is not there')" "1"

INERT="$WORK/inert"
mkdir -p "$INERT/Roster"
printf 'enum OvationMotion {\n    static let slideMilliseconds = 280\n}\n' > "$INERT/$OWNER"
check_exit "an owner that writes no motion at all refuses too, since nothing is owned" \
    3 status_on "$INERT"
check "and it says THAT rather than saying the owner is missing" \
    "$(run_on "$INERT" | grep -c 'holds no motion')" "1"

# ---------------------------------------------------------------------------
# The real root, once, so the seam is not the only thing ever measured (L246).
# ---------------------------------------------------------------------------
check_exit "Ovation's own sources pass, scanned at the real default root" \
    0 "./$TARGET"
check "and the real run really scanned the tree rather than finding nothing" \
    "$("./$TARGET" 2>&1 | grep -cE 'scanned [0-9]+ Swift file')" "1"

harness_end
