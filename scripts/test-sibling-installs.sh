#!/bin/bash
# The sibling install verdict must BLOCK, PASS and REFUSE as three different
# things, and must never print a client, venue or vendor name.
#
# ovation#3, plan 0.2.0 and 0.2. Ovation's whole handoff rests on two facts
# about apps it does not build: the installed Overture must contain the widened
# version gate `bdd85404`, or it refuses a version 3 Downbeat export outright and
# loses its client roster on the first action of the plan; and the installed
# Downbeat must actually be writing a version 3 export, which is the file that
# carries shoot times.
#
# BOTH WERE TRUE WHEN THIS WAS WRITTEN, which is exactly why the guard needs its
# failure cases staged rather than measured. A guard only ever seen to pass has
# not been seen to work (L1), and a check that reads live data and asserts what
# that data currently says is asserting about today rather than about the rule
# (L68).
#
# THE THREE OUTCOMES ARE KEPT APART DELIBERATELY (L11, L98, L260):
#
#   0  PASS           both facts measured and both hold
#   1  BLOCKED        a fact was measured and is wrong
#   2  CANNOT MEASURE the fact could not be read at all
#
# CANNOT MEASURE is not a pass and not a failure. A missing installed-build.json
# says nothing about which build is installed, and reporting that as either
# answer invents a measurement nobody took.
#
# Every case runs against a THROWAWAY record, a THROWAWAY git repository and a
# THROWAWAY export. Nothing here reads or writes Overture's or Downbeat's real
# files, and nothing here runs git in a real sibling checkout (L2).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "sibling install verdict tests" 16

TARGET="scripts/check-sibling-installs.sh"
require_target "$TARGET"
harness_temp_dir WORK

# ONE repository, built once for the whole suite rather than per case. Two empty
# commits is the entire fixture: OLD is an ancestor of NEW, which is the only
# relationship the gate check asks about.
REPO="$WORK/overture"
git init -q "$REPO" 2>/dev/null
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty --no-verify -m first
OLD="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty --no-verify -m second
NEW="$(git -C "$REPO" rev-parse HEAD)"

record() {
    # record <path> <commit-or-omit> <provenance-or-omit>
    local out="$1" commit="$2" prov="$3" body=""
    [ "$commit" = "-" ] || body="\"commit\":\"$commit\""
    if [ "$prov" != "-" ]; then
        [ -n "$body" ] && body="$body,"
        body="$body\"provenance\":\"$prov\""
    fi
    printf '{%s}\n' "$body" > "$out"
}

export_file() {
    # export_file <path> <version> [extra client name]
    printf '{"version":%s,"clients":[{"displayName":"%s"}]}\n' "$2" "${3:-Placeholder Ensemble}" > "$1"
}

GOOD_RECORD="$WORK/good.json"; record "$GOOD_RECORD" "$NEW" main
GOOD_EXPORT="$WORK/good-export.json"; export_file "$GOOD_EXPORT" 3

run_check() {
    # run_check <record> <repo> <export> <gate>
    OVATION_OVERTURE_BUILD_RECORD="$1" \
    OVATION_OVERTURE_REPO="$2" \
    OVATION_DOWNBEAT_EXPORT="$3" \
    OVATION_OVERTURE_GATE_COMMIT="$4" \
        "./$TARGET" 2>&1
}
status_of() { run_check "$@" >/dev/null 2>&1; printf '%s' "$?"; }
says() { if printf '%s' "$1" | grep -qF "$2"; then echo yes; else echo no; fi; }

# ---------------------------------------------------------------------------
# 1. The healthy case, which is what this machine actually looks like today.
# ---------------------------------------------------------------------------
OUT_OK="$(run_check "$GOOD_RECORD" "$REPO" "$GOOD_EXPORT" "$OLD")"
check "everything in order is a pass" \
    "$(status_of "$GOOD_RECORD" "$REPO" "$GOOD_EXPORT" "$OLD")" "0"
check "and it names both facts it measured, not just its verdict" \
    "$(says "$OUT_OK" "version 3")" "yes"

# ---------------------------------------------------------------------------
# 2. BLOCKED: a measured fact is wrong.
# ---------------------------------------------------------------------------
# The installed build predates the gate fix. This is the ordering hazard the
# whole of plan 0.2.0 exists to prevent, so it must never read as a pass.
#
# The record holds the OLD commit and the gate is the NEW one. Written the other
# way round first, with the same commit on both sides, and it passed: a commit is
# its own ancestor, so that fixture asserted nothing at all (L159).
OLD_RECORD="$WORK/old.json"; record "$OLD_RECORD" "$OLD" main
check "an installed build that predates the gate fix is BLOCKED" \
    "$(status_of "$OLD_RECORD" "$REPO" "$GOOD_EXPORT" "$NEW")" "1"
OUT_OLD="$(run_check "$OLD_RECORD" "$REPO" "$GOOD_EXPORT" "$NEW")"
check "and it names the gate commit it wanted" \
    "$(says "$OUT_OLD" "${NEW:0:8}")" "yes"

BRANCH_RECORD="$WORK/branch.json"; record "$BRANCH_RECORD" "$NEW" a-feature-branch
check "an install from a branch other than main is BLOCKED" \
    "$(status_of "$BRANCH_RECORD" "$REPO" "$GOOD_EXPORT" "$OLD")" "1"
OUT_BRANCH="$(run_check "$BRANCH_RECORD" "$REPO" "$GOOD_EXPORT" "$OLD")"
check "and it names the provenance it actually found" \
    "$(says "$OUT_BRANCH" "a-feature-branch")" "yes"

V2_EXPORT="$WORK/v2.json"; export_file "$V2_EXPORT" 2
check "an export that is still version 2 is BLOCKED" \
    "$(status_of "$GOOD_RECORD" "$REPO" "$V2_EXPORT" "$OLD")" "1"

# ---------------------------------------------------------------------------
# 3. CANNOT MEASURE: the fact could not be read at all.
#
# Each of these is a DIFFERENT cause, and each says so, because a message may
# claim only what its check actually measured (L11). Sharing one message would
# let the missing field answer for the missing file.
# ---------------------------------------------------------------------------
check "a missing installed-build.json cannot be measured, and is not a pass" \
    "$(status_of "$WORK/nothing-here.json" "$REPO" "$GOOD_EXPORT" "$OLD")" "2"

NO_COMMIT="$WORK/no-commit.json"; record "$NO_COMMIT" - main
check "a record with no commit field cannot be measured" \
    "$(status_of "$NO_COMMIT" "$REPO" "$GOOD_EXPORT" "$OLD")" "2"
OUT_NC="$(run_check "$NO_COMMIT" "$REPO" "$GOOD_EXPORT" "$OLD")"
check "and it names the field that was missing" "$(says "$OUT_NC" "commit")" "yes"

NO_PROV="$WORK/no-prov.json"; record "$NO_PROV" "$NEW" -
check "a record with no provenance field cannot be measured" \
    "$(status_of "$NO_PROV" "$REPO" "$GOOD_EXPORT" "$OLD")" "2"

MALFORMED="$WORK/malformed.json"; printf 'this is not json\n' > "$MALFORMED"
check "a record that is not JSON at all cannot be measured" \
    "$(status_of "$MALFORMED" "$REPO" "$GOOD_EXPORT" "$OLD")" "2"

check "an unreachable Overture checkout cannot be measured" \
    "$(status_of "$GOOD_RECORD" "$WORK/no-such-repo" "$GOOD_EXPORT" "$OLD")" "2"

UNKNOWN="$WORK/unknown.json"; record "$UNKNOWN" 0000000000000000000000000000000000000000 main
check "a commit the checkout has never heard of cannot be measured" \
    "$(status_of "$UNKNOWN" "$REPO" "$GOOD_EXPORT" "$OLD")" "2"

check "a missing export cannot be measured" \
    "$(status_of "$GOOD_RECORD" "$REPO" "$WORK/no-export.json" "$OLD")" "2"

# ---------------------------------------------------------------------------
# 4. THE PRIVACY FLOOR. The export carries real client and venue names, and this
#    script's output goes into terminal scrollback, transcripts and anything
#    somebody pastes. A repository privacy guard cannot see what a tool PRINTS,
#    so the tool is what has to be checked (L222). Counts, versions and field
#    names only.
# ---------------------------------------------------------------------------
NAMED="$WORK/named.json"; export_file "$NAMED" 3 "Zzyzx Fictional Ensemble"
OUT_NAMED="$(run_check "$GOOD_RECORD" "$REPO" "$NAMED" "$OLD")"
check "a name inside the export never reaches the output" \
    "$(says "$OUT_NAMED" "Zzyzx")" "no"

harness_end
