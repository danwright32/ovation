#!/bin/bash
# The suite for scripts/check-forbidden-constructs.sh.
#
# ovation#53, plan 1.4. Money is Int64 minor units and the type carries no
# floating point constructor, which makes the mistake impossible to write INSIDE
# the money type. It does nothing about a `Double` declared anywhere else in the
# app, and a rule that lives only in a header is enforced by nothing (L27, L407).
#
# Every case runs against a THROWAWAY scan root through the script's own seam.
# The real default root is exercised once, deliberately, because a seam that
# hides the real path from every test leaves the real path untested (L246).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"

TARGET="scripts/check-forbidden-constructs.sh"

# The per type cases are DERIVED from the script's own list, so a type added
# there arrives with a case rather than being forbidden by a check nothing
# exercises (L41, L217). The declared total is derived from the same count, so
# the two numbers cannot drift (L70).
FORBIDDEN="$([ -x "./$TARGET" ] && "./$TARGET" --list 2>/dev/null)"
FORBIDDEN_COUNT="$(printf '%s\n' "$FORBIDDEN" | grep -c .)"
# The drawing rule's readers are a SECOND list, one call per line as it would be
# written, because that rule only applies inside the code that draws a screen and
# a bare token in a struct is exactly where it must NOT fire (ovation#255).
DRAWING="$([ -x "./$TARGET" ] && "./$TARGET" --list-drawing 2>/dev/null)"
DRAWING_COUNT="$(printf '%s\n' "$DRAWING" | grep -c .)"

harness_begin "forbidden construct tests" $((32 + FORBIDDEN_COUNT + 16 + 2 * DRAWING_COUNT))
require_target "$TARGET"
harness_temp_dir WORK

run_on() {
    OVATION_CONSTRUCT_SCAN_ROOT="$1" OVATION_CONSTRUCT_ALLOWLIST="${2-}" "./$TARGET" 2>&1
}
status_on() {
    OVATION_CONSTRUCT_SCAN_ROOT="$1" OVATION_CONSTRUCT_ALLOWLIST="${2-}" "./$TARGET" >/dev/null 2>&1
    printf '%s' "$?"
}

# ---------------------------------------------------------------------------
# DISK WORK WHILE DRAWING (ovation#255).
#
# Written after the same mistake was made twice in one file in one evening, in
# the Settings window (ovation#247): the archive list, which VERIFIES every
# backup by hashing every file in it, was read from a view's body, and an
# archive's manifest was read from a confirmation dialog's message. A body is
# re-evaluated constantly, so both put disk work on the drawing thread on every
# redraw, which on a folder that syncs to a NAS is a frozen window. Neither was
# caught by anything; both were found by reading the code back (L27).
#
# THE LINE IS WHERE THE CODE RUNS, not what file it is in. An action closure runs
# once per press, which is where this work belongs, so the same call is refused in
# a body and allowed in a Button action, and every case below is one of the two.
# ---------------------------------------------------------------------------
check "the drawing rule still names the archive list" \
    "$(printf '%s\n' "$DRAWING" | grep -c 'archives()')" "1"
check "the drawing rule still names the manifest read behind a confirmation" \
    "$(printf '%s\n' "$DRAWING" | grep -c 'consequence(of:')" "1"

n=0
while IFS= read -r SNIPPET; do
    [ -n "$SNIPPET" ] || continue
    n=$((n + 1))
    INBODY="$WORK/drawing-body-$n"
    INACTION="$WORK/drawing-action-$n"
    mkdir -p "$INBODY" "$INACTION"
    printf 'import SwiftUI\nstruct Pane: View {\n    var body: some View {\n        let _ = %s\n        Text("pane")\n    }\n}\n' \
        "$SNIPPET" > "$INBODY/Pane.swift"
    printf 'import SwiftUI\nstruct Pane: View {\n    var body: some View {\n        Button("Go") {\n            _ = %s\n        }\n    }\n}\n' \
        "$SNIPPET" > "$INACTION/Pane.swift"
    check "$SNIPPET in a view's body is refused" "$(status_on "$INBODY")" "1"
    check "$SNIPPET in a Button's action is allowed" "$(status_on "$INACTION")" "0"
done <<< "$DRAWING"

# The two real instances, in the shapes they were written in.
LISTED="$WORK/drawing-listed"
mkdir -p "$LISTED"
cat > "$LISTED/Settings.swift" <<'SWIFT'
import SwiftUI
struct Settings: View {
    var restore: Restore?
    var body: some View {
        ForEach((try? restore?.archives()) ?? []) { row in
            Text(row.name)
        }
    }
}
SWIFT
check "the archive list read while drawing is refused" "$(status_on "$LISTED")" "1"
check "and the refusal names the file and the line" \
    "$(run_on "$LISTED" | grep -c 'Settings.swift:5')" "1"
check "and names the rule, which forbids something the others do not" \
    "$(run_on "$LISTED" | grep -c '^disk work while drawing: ')" "1"
check "and does not print the source line" \
    "$(run_on "$LISTED" | grep -c 'ForEach')" "0"

DIALOG="$WORK/drawing-dialog"
mkdir -p "$DIALOG"
cat > "$DIALOG/Settings.swift" <<'SWIFT'
import SwiftUI
struct Settings: View {
    var restore: Restore
    @State private var confirming: String?
    var body: some View {
        Text("pane")
            .confirmationDialog("Put this back?", isPresented: .constant(true),
                                presenting: confirming) { name in
                Button("Restore", role: .destructive) { restore.restore(name) }
            } message: { name in
                Text((try? restore.consequence(of: name)) ?? "")
            }
    }
}
SWIFT
check "a manifest read inside a dialog's message is refused, though its button's action is not" \
    "$(run_on "$DIALOG" | grep -cE 'Settings.swift:[0-9]+: ')" "1"

COMPUTED="$WORK/drawing-computed"
mkdir -p "$COMPUTED"
cat > "$COMPUTED/Pane.swift" <<'SWIFT'
import SwiftUI
struct Pane: View {
    private var exists: Bool {
        FileManager.default.fileExists(atPath: "/tmp")
    }
    var body: some View {
        Text(exists ? "yes" : "no")
    }
}
SWIFT
check "a computed property the body reads is part of drawing" "$(status_on "$COMPUTED")" "1"

BUILDER="$WORK/drawing-builder"
mkdir -p "$BUILDER"
cat > "$BUILDER/Pane.swift" <<'SWIFT'
import SwiftUI
struct Pane: View {
    var body: some View { row(URL(fileURLWithPath: "/tmp")) }
    private func row(_ url: URL) -> some View {
        Text(String(decoding: (try? Data(contentsOf: url)) ?? Data(), as: UTF8.self))
    }
}
SWIFT
check "a function that returns some View is part of drawing" "$(status_on "$BUILDER")" "1"

LABEL="$WORK/drawing-label"
mkdir -p "$LABEL"
cat > "$LABEL/Pane.swift" <<'SWIFT'
import SwiftUI
struct Pane: View {
    var restore: Restore
    var body: some View {
        Button {
            restore.restore("x")
        } label: {
            Text((try? restore.consequence(of: "x")) ?? "")
        }
    }
}
SWIFT
check "a Button's LABEL is drawing even though its action is not" \
    "$(run_on "$LABEL" | grep -cE 'Pane.swift:[0-9]+: ')" "1"

BRACE="$WORK/drawing-brace"
mkdir -p "$BRACE"
cat > "$BRACE/Pane.swift" <<'SWIFT'
import SwiftUI
struct Pane: View {
    var body: some View {
        Text("}")
        Text((try? String(contentsOf: URL(fileURLWithPath: "/tmp"))) ?? "")
    }
}
SWIFT
check "a brace inside a string does not end the body early" "$(status_on "$BRACE")" "1"

for MODIFIER in 'task' 'onAppear' 'onChange(of: tick)'; do
    SAFE="$WORK/drawing-$(printf '%s' "$MODIFIER" | tr -cd 'A-Za-z')"
    mkdir -p "$SAFE"
    printf 'import SwiftUI\nstruct Pane: View {\n    var tick: Int\n    var restore: Restore\n    var body: some View {\n        Text("pane")\n            .%s {\n                _ = try? restore.archives()\n            }\n    }\n}\n' \
        "$MODIFIER" > "$SAFE/Pane.swift"
    check "the same read inside .$MODIFIER runs once, not per redraw, so it is allowed" \
        "$(status_on "$SAFE")" "0"
done

SERVICE="$WORK/drawing-service"
mkdir -p "$SERVICE"
cat > "$SERVICE/Reader.swift" <<'SWIFT'
import Foundation
struct Reader {
    var body: Data? { try? Data(contentsOf: URL(fileURLWithPath: "/tmp")) }
}
SWIFT
check "a file declaring no view is not drawing, whatever its members are called" \
    "$(status_on "$SERVICE")" "0"

MENTION="$WORK/drawing-mention"
mkdir -p "$MENTION"
cat > "$MENTION/Pane.swift" <<'SWIFT'
import SwiftUI
struct Pane: View {
    var body: some View {
        // Never call restore.archives() here: it verifies every backup.
        Text("pane")
    }
}
SWIFT
check "a comment inside a body naming a reader is not a finding" "$(status_on "$MENTION")" "0"

# ---------------------------------------------------------------------------
# A clean tree.
# ---------------------------------------------------------------------------
CLEAN="$WORK/clean"
mkdir -p "$CLEAN/Domain"
cat > "$CLEAN/Domain/Money.swift" <<'SWIFT'
struct Money {
    let cents: Int64
}
SWIFT
cat > "$CLEAN/Domain/Hours.swift" <<'SWIFT'
struct Hours {
    let tenths: Int64
}
SWIFT

# THE RULES THEMSELVES ARE ASSERTED, not only the cases derived from them.
# Deriving both the loop and the declared total from the script's own list means
# DELETING a rule shrinks the coverage and the expectation together, and the run
# stays green while the rule is gone (L70). These two are the floor.
check "the money rule is still declared" \
    "$(printf '%s\n' "$FORBIDDEN" | grep -c '^Double$')" "1"
check "the calendar rule is still declared" \
    "$(printf '%s\n' "$FORBIDDEN" | grep -c '^Calendar\.current$')" "1"
check "the cooperative pool rule is still declared" \
    "$(printf '%s\n' "$FORBIDDEN" | grep -c '^Task\.detached$')" "1"
check "the send gate rule is still declared" \
    "$(printf '%s\n' "$FORBIDDEN" | grep -c '^maySend$')" "1"

check "a tree with no floating point types passes" "$(status_on "$CLEAN")" "0"
check "and it says how many files it actually looked at" \
    "$(run_on "$CLEAN" | grep -c 'scanned 2')" "1"

# ---------------------------------------------------------------------------
# Each forbidden type, one case each, because a check written for one of them
# is satisfied by finding any of them.
# ---------------------------------------------------------------------------
for TYPE in $FORBIDDEN; do
    BAD="$WORK/bad-$TYPE"
    mkdir -p "$BAD"
    printf 'struct Charge {\n    let amount: %s\n}\n' "$TYPE" > "$BAD/Charge.swift"
    check "a $TYPE in the sources is refused" "$(status_on "$BAD")" "1"
done

BAD="$WORK/bad-Double"
check "the refusal names the file and the line" \
    "$(run_on "$BAD" | grep -c 'Charge.swift:2')" "1"
check "the refusal names the type it found" \
    "$(run_on "$BAD" | grep -c 'Double')" "1"
check "the refusal names WHICH rule fired, because the two forbid different things" \
    "$(run_on "$BAD" | grep -c '^floating point money: ')" "1"
check "and says nothing about the rule that did not fire" \
    "$(run_on "$BAD" | grep -c '^ambient calendar: ')" "0"
check "the refusal does NOT print the source line, which is how a comment would leak" \
    "$(run_on "$BAD" | grep -c 'struct Charge')" "0"

# ---------------------------------------------------------------------------
# Comments. The scanner has to NAME the types it forbids in order to forbid
# them, and so does every file explaining the rule, so prose is not code (L245).
# It is stripped from INSIDE the line rather than the whole line being judged by
# how it starts, because one line routinely mixes the two (L361).
# ---------------------------------------------------------------------------
COMMENTS="$WORK/comments"
mkdir -p "$COMMENTS"
cat > "$COMMENTS/Notes.swift" <<'SWIFT'
// There is deliberately no Double constructor on Money.
/* Nor any Decimal, for the same reason.
   Nor Float. */
struct Money {
    let cents: Int64 // never a Double
}
SWIFT
check "a mention in a line comment is not a finding" "$(status_on "$COMMENTS")" "0"

TRAILING="$WORK/trailing"
mkdir -p "$TRAILING"
printf 'let amount: Double = 1 // a comment\n' > "$TRAILING/Bad.swift"
check "code before a comment on the same line is still scanned" \
    "$(status_on "$TRAILING")" "1"

IDENT="$WORK/identifiers"
mkdir -p "$IDENT"
printf 'struct DoubleEntryLedger {\n    let myDoubleCheck: Int64\n    let floatingDock: Int64\n}\n' \
    > "$IDENT/Ledger.swift"
check "a longer identifier that merely contains the word is not a finding" \
    "$(status_on "$IDENT")" "0"

# ---------------------------------------------------------------------------
# NOTHING SCANNED IS NOT A PASS (L98).
# ---------------------------------------------------------------------------
EMPTY="$WORK/empty"
mkdir -p "$EMPTY"
check "a root holding no Swift files refuses rather than passing" "$(status_on "$EMPTY")" "2"
check "and says that it scanned nothing" \
    "$(run_on "$EMPTY" | grep -c 'no Swift files')" "1"
check "a root that is not there refuses with its own exit code" \
    "$(status_on "$WORK/not-here")" "2"

# ---------------------------------------------------------------------------
# The allowlist. An entry names a FILE AND THE RULE it is exempt from
# (ovation#210), carries a written reason (L233), and names a file that is there
# and a rule that exists, or it has outlived its reason.
#
# An entry used to name only a file, and the scan skipped that file entirely, so
# an exemption written for one rule silently covered all of them. The first real
# one, for the palette's colour channels, took a whole file out of the Task and
# calendar rules as well, and the scanned file count dropping by one was the
# only sign.
# ---------------------------------------------------------------------------
ALLOWED="$WORK/allowed"
mkdir -p "$ALLOWED"
printf 'let progress: Double = 0\n' > "$ALLOWED/Animation.swift"
printf 'struct Money { let cents: Int64 }\n' > "$ALLOWED/Money.swift"
check "an allowlisted file and rule with a written reason is not reported" \
    "$(status_on "$ALLOWED" "Animation.swift : floating point money # a SwiftUI animation fraction, never money")" "0"
check "an allowlist entry with no reason is refused" \
    "$(status_on "$ALLOWED" "Animation.swift : floating point money")" "3"
check "an allowlist entry naming a file that is not there is refused" \
    "$(status_on "$ALLOWED" "Gone.swift : floating point money # a reason for a file that no longer exists")" "3"

# AN ENTRY NAMING NO RULE IS REFUSED, rather than read as covering every rule,
# which is the reading this issue was filed against.
check "an allowlist entry naming a file but no rule is refused" \
    "$(status_on "$ALLOWED" "Animation.swift # a SwiftUI animation fraction, never money")" "3"
check "and the refusal says the entry names no rule" \
    "$(run_on "$ALLOWED" "Animation.swift # a SwiftUI animation fraction, never money" \
        | grep -c "^  the allowlist entry 'Animation.swift' names no rule")" "1"
check "an allowlist entry naming a rule that does not exist is refused" \
    "$(status_on "$ALLOWED" "Animation.swift : floating money # a misspelt rule")" "3"
check "and the refusal lists the rules an entry can name" \
    "$(run_on "$ALLOWED" "Animation.swift : floating money # a misspelt rule" \
        | grep -c '^  the rules are: floating point money, ')" "1"

# THE CLASS, not the instance: an exemption from one rule leaves every other
# rule applying to that file.
MIXED="$WORK/allowed-mixed"
mkdir -p "$MIXED"
printf 'let progress: Double = 0\nlet zone = TimeZone.current\n' > "$MIXED/Animation.swift"
check "an exemption from one rule does not exempt the file from another" \
    "$(status_on "$MIXED" "Animation.swift : floating point money # a SwiftUI animation fraction, never money")" "1"
check "and the rule still applying is the one reported" \
    "$(run_on "$MIXED" "Animation.swift : floating point money # a SwiftUI animation fraction, never money" \
        | grep -c '^  Animation.swift:2: TimeZone.current (ambient calendar)$')" "1"
check "and the exempted rule is not" \
    "$(run_on "$MIXED" "Animation.swift : floating point money # a SwiftUI animation fraction, never money" \
        | grep -c '(floating point money)$')" "0"

# An allowlist that has grown to cover EVERYTHING has scanned nothing, and that
# is the state in which a scanner reports exactly what a clean tree does (L98).
# With exemptions per rule, everything means every rule for every file, so the
# entries are derived from the rules the script declares rather than typed here.
EVERYTHING="$WORK/everything-allowed"
mkdir -p "$EVERYTHING"
printf 'let progress: Double = 0\n' > "$EVERYTHING/Animation.swift"
EVERY_RULE="$([ -x "./$TARGET" ] && "./$TARGET" --list-rules 2>/dev/null \
    | sed 's/^\(.*\)$/Animation.swift : \1 # the only file, and it is exempt from this rule/')"
check "an allowlist covering every rule for every file refuses rather than passing" \
    "$(status_on "$EVERYTHING" "$EVERY_RULE")" "2"

check "a refused allowlist says which entry it refused" \
    "$(OVATION_CONSTRUCT_SCAN_ROOT="$ALLOWED" \
        OVATION_CONSTRUCT_ALLOWLIST="Gone.swift : floating point money # a reason" \
        "./$TARGET" 2>&1 | grep -c "^  the allowlist entry 'Gone.swift' names a file that is not there")" "1"

# ---------------------------------------------------------------------------
# WHAT THE DEFAULT ALLOWLIST ACTUALLY COSTS, measured rather than assumed.
#
# An entry names a file AND A RULE since ovation#210, so the palette's exemption
# from the money rule no longer lets a `Task.detached` or a `Calendar.current`
# through: the cases above prove that for every entry, not only this one.
#
# What this case still holds is the exemption's REASON. The palette is scanned
# with the allowlist EMPTY and the money rule is asserted to be the only one it
# trips, so it fails the day anything else goes in the file, which is when the
# comment claiming it holds nothing but colour stops being true (L129).
# ---------------------------------------------------------------------------
PALETTE="$WORK/palette"
mkdir -p "$PALETTE"
cp "Ovation/Roster/OvationPalette.swift" "$PALETTE/"
check "the exempted palette is genuinely found, so this case measures something" \
    "$(status_on "$PALETTE" "")" "1"
check "and it trips no OTHER rule, which is what its exemption silently covers" \
    "$(OVATION_CONSTRUCT_SCAN_ROOT="$PALETTE" OVATION_CONSTRUCT_ALLOWLIST="" \
        "./$TARGET" 2>&1 | grep -cE 'ambient calendar|cooperative pool')" "0"

# ---------------------------------------------------------------------------
# The real root, once, so the seam is not the only thing ever measured (L246).
# ---------------------------------------------------------------------------
check "Ovation's own sources pass, scanned at the real default root" \
    "$("./$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "0"

harness_end
