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
    OVATION_KINDS_SCAN_ROOT="$1" "./$TARGET"
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
check_exit "a kind that is resolved and raised passes" 0 status_on "$CLEAN"
check "and it says how many matched kinds it checked" \
    "$(run_on "$CLEAN" | grep -c '1 problem kind(s) matched on')" "1"

# ---------------------------------------------------------------------------
# THE CASE THE CHECK EXISTS FOR: resolved in the app and raised nowhere.
# ---------------------------------------------------------------------------
UNRAISED="$WORK/unraised"
declare_kind "$UNRAISED"
resolve_kind "$UNRAISED"
check_exit "a kind that is resolved and never raised is refused" 1 status_on "$UNRAISED"
check "the refusal names the file, the line and the kind" \
    "$(run_on "$UNRAISED" | grep -c 'Settings.swift:1: folderMissing')" "1"
check "the refusal does NOT print the source line" \
    "$(run_on "$UNRAISED" | grep -c 'problems.open')" "0"

# A != comparison is matching on the kind just as much as == is.
NOTEQUAL="$WORK/notequal"
declare_kind "$NOTEQUAL"
printf 'let others = problems.open.filter { $0.kind != .folderMissing }\n' > "$NOTEQUAL/Panel.swift"
check_exit "a kind matched with != and raised nowhere is refused too" 1 status_on "$NOTEQUAL"

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
check_exit "a kind raised through a returned tuple counts as raised" 0 status_on "$TUPLE"

# A comment naming the kind is not the kind happening (L245).
COMMENT="$WORK/comment"
declare_kind "$COMMENT"
resolve_kind "$COMMENT"
printf '// A launch with no folder raises .folderMissing, eventually.\n' > "$COMMENT/Notes.swift"
check_exit "a kind mentioned only in a comment is still refused" 1 status_on "$COMMENT"

# Nor is a sentence that happens to spell it.
STRING="$WORK/string"
declare_kind "$STRING"
resolve_kind "$STRING"
printf 'let hint = "raise .folderMissing when the folder is gone"\n' > "$STRING/Hint.swift"
check_exit "a kind spelled only inside a string is still refused" 1 status_on "$STRING"

# ---------------------------------------------------------------------------
# Scope.
# ---------------------------------------------------------------------------
# `kind == .directory` in the backup plan compares a member kind, not a problem
# kind, and must not be read as one.
OTHER="$WORK/other"
declare_kind "$OTHER"
printf 'let folders = members.filter { $0.kind == .directory }\n' > "$OTHER/Plan.swift"
check_exit "a comparison on something that is not a problem kind is not a finding" \
    0 status_on "$OTHER"

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
check_exit "a kind declared outside Problem.swift is held to the rule too" \
    1 status_on "$ELSEWHERE"

# ---------------------------------------------------------------------------
# NOTHING SCANNED IS NOT A PASS (L98).
# ---------------------------------------------------------------------------
EMPTY="$WORK/empty"
mkdir -p "$EMPTY"
check_exit "a root holding no Swift files refuses rather than passing" 2 status_on "$EMPTY"
check_exit "a root that is not there refuses with the same exit code" \
    2 status_on "$WORK/not-here"

NOKINDS="$WORK/no-kinds"
mkdir -p "$NOKINDS"
printf 'struct Money { let cents: Int64 }\n' > "$NOKINDS/Money.swift"
check_exit "a tree declaring no problem kinds refuses, since nothing could be held to the rule" \
    2 status_on "$NOKINDS"

# ---------------------------------------------------------------------------
# The real root, once, so the seam is not the only thing ever measured (L246).
# ---------------------------------------------------------------------------
check_exit "Ovation's own sources pass, scanned at the real default root" \
    0 "./$TARGET"

harness_end
