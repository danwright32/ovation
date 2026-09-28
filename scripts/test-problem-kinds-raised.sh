#!/bin/bash
# The suite for scripts/check-problem-kinds-raised.sh.
#
# ovation#262. Every case runs against a THROWAWAY scan root through the script's
# own seam, and the real sources are scanned once, deliberately, because a seam
# that hides the real path from every test leaves the real path untested (L246).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "problem kinds raised tests" 22

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
check "and it says how many declared kinds it checked, and how many are matched on" \
    "$(run_on "$CLEAN" | grep -c '1 problem kind(s) declared, every one raised somewhere; 1 of them matched on')" "1"

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

# ---------------------------------------------------------------------------
# EVERY DECLARED KIND, NOT ONLY THE MATCHED ONES (ovation#583). Two backup
# retention kinds were declared, named in the rail foot's table, and raised by
# nothing, and nothing compared against them either, so the rule above never
# looked at them. A kind nothing raises is either dead or a failure that passes
# in silence, and neither is visible from the declaration (L90, L29).
# ---------------------------------------------------------------------------
DECLARED="$WORK/declared-only"
declare_kind "$DECLARED"
check_exit "a kind declared and raised nowhere is refused, even when nothing matches on it" \
    1 status_on "$DECLARED"
check "and the refusal names where it is declared" \
    "$(run_on "$DECLARED" | grep -c '^  Problem.swift:2: folderMissing (declared here, raised nowhere)$')" "1"

# The rail foot's table names every kind, and its keys are not raises.
DECLARED_TABLE="$WORK/declared-table"
declare_kind "$DECLARED_TABLE"
cat > "$DECLARED_TABLE/Names.swift" <<'SWIFT'
static let shortNames: [ProblemKind: String] = [
    .folderMissing: "No backup folder",
]
SWIFT
check_exit "a kind declared and named only in the short names table is still refused" \
    1 status_on "$DECLARED_TABLE"

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

# A table keyed by every kind, like the rail foot's short names (ovation#99), is
# not the kind happening. Were it counted, one table naming every kind would
# silence this check for all of them at once.
TABLE="$WORK/table"
declare_kind "$TABLE"
resolve_kind "$TABLE"
cat > "$TABLE/Names.swift" <<'SWIFT'
static let shortNames: [ProblemKind: String] = [
    .folderMissing: "No backup folder",
]
SWIFT
check_exit "a kind named only as a table's key is still refused" 1 status_on "$TABLE"

# But only a table's KEY is discounted. A genuine raise written as the true branch
# of a ternary has a colon after it too, and must still count, or the check
# refuses a kind that is raised.
TERNARY="$WORK/ternary"
declare_kind "$TERNARY"
resolve_kind "$TERNARY"
cat > "$TERNARY/Launch.swift" <<'SWIFT'
problems.raise(kind: missing ? .folderMissing : .other, subject: "b", sentence: "s", now: now)
SWIFT
check_exit "a kind raised as the true branch of a ternary counts as raised" 0 status_on "$TERNARY"

# A switch case label is read as it always was, as a use, whether it stands alone
# or follows another pattern: this check never counted matching in a switch as
# "never raised", and discounting keys must not quietly start to.
CASELABEL="$WORK/case-label"
declare_kind "$CASELABEL"
resolve_kind "$CASELABEL"
cat > "$CASELABEL/Sort.swift" <<'SWIFT'
switch kind {
case .folderMissing: return 1
default: return 0
}
SWIFT
check_exit "a kind in a switch case label is counted as before" 0 status_on "$CASELABEL"
CASELIST="$WORK/case-list"
declare_kind "$CASELIST"
resolve_kind "$CASELIST"
cat > "$CASELIST/Sort.swift" <<'SWIFT'
switch kind {
case .other, .folderMissing: return 1
default: return 0
}
SWIFT
check_exit "a kind second in a case pattern list is counted as before" 0 status_on "$CASELIST"

# ---------------------------------------------------------------------------
# Scope.
# ---------------------------------------------------------------------------
# `kind == .directory` in the backup plan compares a member kind, not a problem
# kind, and must not be read as one.
OTHER="$WORK/other"
declare_kind "$OTHER"
printf 'let folders = members.filter { $0.kind == .directory }\n' > "$OTHER/Plan.swift"
# Raised, so this case stays about the comparison rather than the declaration.
printf 'problems.raise(kind: .folderMissing, subject: "b", sentence: "s", now: now)\n' \
    > "$OTHER/Launch.swift"
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
