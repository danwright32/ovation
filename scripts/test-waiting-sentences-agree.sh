#!/bin/bash
# Whether the waiting sentence guard can actually tell agreement from drift.
#
# ovation#117. The guard holds `ReviewGate.sentence` to the wording settled with
# Dan in `docs/design/rules/waiting.js`. Every case here drives it over a STAGED
# pair of files rather than this repository, because a guard verified only
# against the current tree passes for as long as that tree happens to be clean
# and says nothing about what it would catch (L1, L2). The real pair is asked
# once at the end, which is a different question and gets its own case.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "waiting sentence agreement tests" 14

TARGET="scripts/check-waiting-sentences-agree.sh"
require_target "$TARGET"
harness_temp_dir WORK

run_on() { "./$TARGET" "$1" "$2" 2>&1; }
status_on() { "./$TARGET" "$1" "$2" >/dev/null 2>&1; printf '%s' "$?"; }

# A DESIGN FILE SHAPED LIKE THE REAL ONE: a rule with tips in it, including the
# one built from a constant, which is the case the two languages spell apart.
design() {
    local path="$WORK/$1.js"
    cat > "$path" <<'JS'
function waitingOnFor(start, end, status) {
  if (start === null && end === null) {
    return { reason: "times", says: "Needs the times",
             tip: "Waiting on the shoot's start and end times." };
  }
  if (durationBetween(start, end) === null) {
    return { reason: "duration", says: "Longer than a shoot",
             tip: "That is more than " + CAP_HOURS + " hours, so it prices nothing." };
  }
  return null;
}
JS
    printf '%s' "$path"
}

app() {
    # app <name> <swift body>: a file shaped like ReviewGate's switch
    local path="$WORK/$1.swift"
    printf 'enum ReviewGate {\n    static func sentence(for refusal: InvoiceRefusal) -> String {\n        switch refusal {\n%s\n        }\n    }\n}\n' "$2" > "$path"
    printf '%s' "$path"
}

D="$(design agreeing)"

AGREES="$(app agreeing '        case .times:
            return "Waiting on the shoot'"'"'s start and end times."
        case .duration:
            return "That is more than \(ShootDuration.cap.hundredths / 100) hours, so it prices nothing."')"

check "a pair saying the same thing passes" "$(status_on "$D" "$AGREES")" "0"
check "and it says how many it compared, rather than only that it passed" \
    "$(run_on "$D" "$AGREES" | grep -c '2 design tip')" "1"

# THE CASE THE GUARD EXISTS FOR.
MISSING="$(app missing '        case .duration:
            return "That is more than \(ShootDuration.cap.hundredths / 100) hours, so it prices nothing."')"
check "a tip the app never says is refused" "$(status_on "$D" "$MISSING")" "1"
check "and the refusal names the sentence that is missing" \
    "$(run_on "$D" "$MISSING" | grep -c "Waiting on the shoot's start and end times.")" "1"

# THE INTERPOLATION IS MASKED, not compared. Each language says its own constant
# its own way, and the guard is about the WORDS around it.
REWORDED="$(app reworded '        case .times:
            return "Waiting on the shoot'"'"'s start and end times."
        case .duration:
            return "That is more than \(ShootDuration.cap.hundredths / 100) hours, so nothing is priced."')"
check "a sentence whose WORDS drifted around the constant is refused" \
    "$(status_on "$D" "$REWORDED")" "1"

SPELLED="$(app spelled '        case .times:
            return "Waiting on the shoot'"'"'s start and end times."
        case .duration:
            return "That is more than \(Self.cap) hours, so it prices nothing."')"
check "and one spelling the SAME constant differently is not" \
    "$(status_on "$D" "$SPELLED")" "0"

# A sentence written across two lines, which is how the real file writes the
# long one, must be read as one sentence rather than as two fragments.
WRAPPED="$(app wrapped '        case .times:
            return "Waiting on the shoot'"'"'s start and end times."
        case .duration:
            return "That is more than \(ShootDuration.cap.hundredths / 100) hours, "
                + "so it prices nothing."')"
check "a sentence continued onto a second line is read whole" \
    "$(status_on "$D" "$WRAPPED")" "0"

# THE APP MAY SAY MORE THAN THE DESIGN. Four of its refusals are not states of
# waiting and waiting.js has never had a word for them.
EXTRA="$(app extra '        case .times:
            return "Waiting on the shoot'"'"'s start and end times."
        case .duration:
            return "That is more than \(ShootDuration.cap.hundredths / 100) hours, so it prices nothing."
        case .paymentInstructionsNotSet:
            return "Settings has no payment instructions, so no invoice can be sent."')"
check "a sentence the design has no tip for is allowed" "$(status_on "$D" "$EXTRA")" "0"

# NOTHING TO COMPARE IS NOT A PASS, and each cause is its own outcome (L11, L98).
check "a design file that is not there cannot be compared" \
    "$(status_on "$WORK/absent.js" "$AGREES")" "2"
check "an app file that is not there cannot be compared either" \
    "$(status_on "$D" "$WORK/absent.swift")" "2"

EMPTY_D="$WORK/empty.js"; printf 'function nothing() { return null; }\n' > "$EMPTY_D"
check "a design file holding no tips is refused rather than passed" \
    "$(status_on "$EMPTY_D" "$AGREES")" "2"
check "and it says the comparison found nothing, rather than implying agreement" \
    "$(run_on "$EMPTY_D" "$AGREES" | grep -c 'CANNOT COMPARE')" "1"

EMPTY_A="$WORK/empty.swift"; printf 'enum ReviewGate {}\n' > "$EMPTY_A"
check "an app file holding no sentences is refused too" \
    "$(status_on "$D" "$EMPTY_A")" "2"

# AND THE REAL PAIR, which is a different question from every case above: those
# ask what the guard CAN catch, this asks whether the tree is clean today.
check "the committed design record and the committed app agree" \
    "$(status_on docs/design/rules/waiting.js Ovation/Document/ReviewGate.swift)" "0"

harness_end
