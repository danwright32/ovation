#!/bin/bash
# The suite for scripts/check-problem-kinds-raised.sh.
#
# ovation#262. Every case runs against a THROWAWAY scan root through the script's
# own seam, and the real sources are scanned once, deliberately, because a seam
# that hides the real path from every test leaves the real path untested (L246).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "problem kinds raised tests" 15

TARGET="scripts/check-problem-kinds-raised.sh"
require_target "$TARGET"
harness_temp_dir WORK

run_on() {
    OVATION_KINDS_SCAN_ROOT="$1" "./$TARGET" 2>&1
}
status_on() {
    OVATION_KINDS_SCAN_ROOT="$1" "./$TARGET" >/dev/null 2>&1
    printf '%s' "$?"
}

# One problem kind, declared the way the app declares them.
declare_kind() {
    mkdir -p "$1"
    cat > "$1/Problem.swift" <<'SWIFT'
extension ProblemKind {
    static let folderMissing = ProblemKind("backup.folder-missing")
}
SWIFT
}

# Something that matches on it, on line 1 so a case can name the line.
resolve_kind() {
    printf 'for p in problems.open where p.kind == .folderMissing { resolve(p) }\n' > "$1/Settings.swift"
}

# ---------------------------------------------------------------------------
# A kind something resolves and something raises.
# ---------------------------------------------------------------------------
CLEAN="$WORK/clean"
declare_kind "$CLEAN"
resolve_kind "$CLEAN"
cat > "$CLEAN/Launch.swift" <<'SWIFT'
problems.raise(kind: .folderMissing, subject: "backups", sentence: "No folder.", now: now)
SWIFT
check "a kind that is resolved and raised passes" "$(status_on "$CLEAN")" "0"
check "and it says how many matched kinds it checked" \
    "$(run_on "$CLEAN" | grep -c '1 problem kind(s) matched on')" "1"

# ---------------------------------------------------------------------------
# THE CASE THE CHECK EXISTS FOR: resolved in the app and raised nowhere.
# ---------------------------------------------------------------------------
UNRAISED="$WORK/unraised"
declare_kind "$UNRAISED"
resolve_kind "$UNRAISED"
check "a kind that is resolved and never raised is refused" "$(status_on "$UNRAISED")" "1"
check "the refusal names the file, the line and the kind" \
    "$(run_on "$UNRAISED" | grep -c 'Settings.swift:1: folderMissing')" "1"
check "the refusal does NOT print the source line" \
    "$(run_on "$UNRAISED" | grep -c 'problems.open')" "0"

# A != comparison is matching on the kind just as much as == is.
NOTEQUAL="$WORK/notequal"
declare_kind "$NOTEQUAL"
printf 'let others = problems.open.filter { $0.kind != .folderMissing }\n' > "$NOTEQUAL/Panel.swift"
check "a kind matched with != and raised nowhere is refused too" "$(status_on "$NOTEQUAL")" "1"

# ---------------------------------------------------------------------------
# What counts as raised.
# ---------------------------------------------------------------------------
# A helper returning the kind in a tuple is how the app raises backup kinds, so
# requiring the literal `kind: .name` would call every one of those unraised.
TUPLE="$WORK/tuple"
declare_kind "$TUPLE"
resolve_kind "$TUPLE"
cat > "$TUPLE/Condition.swift" <<'SWIFT'
func condition() -> (ProblemKind, String) {
    (.folderMissing, "No backup folder has been chosen yet.")
}
SWIFT
check "a kind raised through a returned tuple counts as raised" "$(status_on "$TUPLE")" "0"

# A comment naming the kind is not the kind happening (L245).
COMMENT="$WORK/comment"
declare_kind "$COMMENT"
resolve_kind "$COMMENT"
printf '// A launch with no folder raises .folderMissing, eventually.\n' > "$COMMENT/Notes.swift"
check "a kind mentioned only in a comment is still refused" "$(status_on "$COMMENT")" "1"

# Nor is a sentence that happens to spell it.
STRING="$WORK/string"
declare_kind "$STRING"
resolve_kind "$STRING"
printf 'let hint = "raise .folderMissing when the folder is gone"\n' > "$STRING/Hint.swift"
check "a kind spelled only inside a string is still refused" "$(status_on "$STRING")" "1"

# ---------------------------------------------------------------------------
# Scope.
# ---------------------------------------------------------------------------
# `kind == .directory` in the backup plan compares a member kind, not a problem
# kind, and must not be read as one.
OTHER="$WORK/other"
declare_kind "$OTHER"
printf 'let folders = members.filter { $0.kind == .directory }\n' > "$OTHER/Plan.swift"
check "a comparison on something that is not a problem kind is not a finding" \
    "$(status_on "$OTHER")" "0"

# Kinds are declared in extensions in more than one file, so a declaration away
# from Problem.swift must still be a subject.
ELSEWHERE="$WORK/elsewhere"
mkdir -p "$ELSEWHERE"
cat > "$ELSEWHERE/Roster.swift" <<'SWIFT'
extension ProblemKind {
    static let rosterGone = ProblemKind("roster.gone")
}
SWIFT
printf 'let gone = problems.open.first { $0.kind == .rosterGone }\n' > "$ELSEWHERE/Shell.swift"
check "a kind declared outside Problem.swift is held to the rule too" \
    "$(status_on "$ELSEWHERE")" "1"

# ---------------------------------------------------------------------------
# NOTHING SCANNED IS NOT A PASS (L98).
# ---------------------------------------------------------------------------
EMPTY="$WORK/empty"
mkdir -p "$EMPTY"
check "a root holding no Swift files refuses rather than passing" "$(status_on "$EMPTY")" "2"
check "a root that is not there refuses with the same exit code" \
    "$(status_on "$WORK/not-here")" "2"

NOKINDS="$WORK/no-kinds"
mkdir -p "$NOKINDS"
printf 'struct Money { let cents: Int64 }\n' > "$NOKINDS/Money.swift"
check "a tree declaring no problem kinds refuses, since nothing could be held to the rule" \
    "$(status_on "$NOKINDS")" "2"

# ---------------------------------------------------------------------------
# The real root, once, so the seam is not the only thing ever measured (L246).
# ---------------------------------------------------------------------------
check "Ovation's own sources pass, scanned at the real default root" \
    "$("./$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "0"

harness_end
