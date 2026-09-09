#!/bin/bash
# The CI workflow must carry the decisions that made CI exist, and a workflow
# file is exactly the kind of thing nothing else in a repository ever reads.
#
# ovation#143. `scripts/build-products.sh` was written for CI, on Dan's decision
# of 2026-09-06 that CI BUILDS BOTH configurations, and then no CI existed for
# two days: `.github/workflows/` was absent and no workflow had ever run. The
# bundle assertions that decision exists to protect were running on exactly one
# machine, which is the outcome it rejected.
#
# Three things this asserts, each because it fails silently:
#   a timeout on every job    a hung job is worse than a failed one, and the
#                             platform default is six hours (L110, L313)
#   every action pinned       a moving tag is somebody else's code running in
#                             this repository tomorrow (L25)
#   the documented command    the decision above is a sentence in a header until
#                             something reads it (L407)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "ci workflow tests" 17

TARGET="scripts/check-ci-workflow.sh"
require_target "$TARGET"
harness_temp_dir WORK

run_check() { OVATION_WORKFLOW_DIR="$1" "./$TARGET" 2>&1; }
status_of() { run_check "$1" >/dev/null 2>&1; printf '%s' "$?"; }

# EDIT IN PLACE, PORTABLY. `sed -i ''` is the BSD form and GNU sed reads the
# empty string as a FILE to edit, so on Linux it fails with "can't read : No such
# file or directory" while the intended edit never happens. Neither errors on the
# other's form in a way a reader would predict, which is why this is one helper
# rather than a flag choice repeated at each call site (L434, ovation#152).
#
# It writes to a temp file and moves it, which is both dialects' behaviour and
# needs no flag at all.
sed_in_place() {
    # sed_in_place <file> <expression>
    local file="$1" expression="$2" tmp
    tmp="$(mktemp)" || return 1
    sed "$expression" "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$file"
}

good_workflow() {
    mkdir -p "$1"
    cat > "$1/ci.yml" <<'YML'
name: CI
jobs:
  shell-suites:
    runs-on: macos-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
      - run: bash scripts/run-tests.sh
  build-and-test:
    runs-on: macos-latest
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
      - run: bash scripts/build-products.sh && bash scripts/run-tests.sh
YML
}

# 1. THE PASSING CASE HAS TO BE PRODUCED FIRST, or every refusal below is
#    satisfied by a check that refuses everything (L159).
G="$WORK/good"; good_workflow "$G"
check "a workflow carrying all three passes" "$(status_of "$G")" "0"

# 2. No workflow directory at all. This is the state ovation#143 was filed about,
#    and it is a refusal rather than a cannot measure: the repository decided to
#    have CI, so its absence is a fault and not an unanswerable question.
check "no workflow directory is refused" "$(status_of "$WORK/nothing")" "1"
check "and it says there is no CI rather than naming a file" \
    "$(run_check "$WORK/nothing" | grep -ci 'no workflow')" "1"

# 3. A job with no timeout. The platform default is six hours, and a hung job
#    holds a runner slot for all of it.
B1="$WORK/notimeout"; good_workflow "$B1"
sed_in_place "$B1/ci.yml" '/timeout-minutes: 20/d' 
check "a job with no timeout is refused" "$(status_of "$B1")" "1"
check "and it names the job that has none" \
    "$(run_check "$B1" | grep -c 'shell-suites')" "1"

# 4. An action on a moving tag rather than a commit.
B2="$WORK/unpinned"; good_workflow "$B2"
sed_in_place "$B2/ci.yml" 's|actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683|actions/checkout@v4|' 
check "an action pinned to a tag rather than a commit is refused" "$(status_of "$B2")" "1"
# BOTH uses, not the first one. A guard that reports the first instance teaches
# whoever fixes it that there was one (L30).
check "and it names every unpinned use, not just the first" \
    "$(run_check "$B2" | grep -c 'actions/checkout@v4')" "2"

# 5. The documented command gone. This is the decision itself going missing, and
#    it is the one failure that leaves a green tick on the board (L400).
B3="$WORK/nobuild"; good_workflow "$B3"
sed_in_place "$B3/ci.yml" 's|bash scripts/build-products.sh && bash scripts/run-tests.sh|bash scripts/run-tests.sh|' 
check "a workflow that never builds both configurations is refused" "$(status_of "$B3")" "1"
check "and it quotes the command it expected to find" \
    "$(run_check "$B3" | grep -c 'build-products.sh')" "1"

# 6. AND THE REAL WORKFLOW PASSES ITS OWN CHECK. Everything above is a fixture;
#    this is the assertion that goes red the day the real file drifts.
check "this repository's own workflow passes" "$(status_of ".github/workflows")" "0"

# 7. It reports what it examined, so a run over an empty directory cannot read
#    like a thorough one (L98).
OUT="$(run_check "$G")"
check "it says how many jobs it examined" "$(printf '%s' "$OUT" | grep -cE '[0-9]+ job')" "1"
check "and how many workflow files" "$(printf '%s' "$OUT" | grep -cE '[0-9]+ workflow file')" "1"

# 8. A workflow directory that exists and holds no workflow is its own refusal,
#    not a pass over zero files.
E="$WORK/empty"; mkdir -p "$E"
check "a workflow directory holding no workflow is refused" "$(status_of "$E")" "1"


# ---------------------------------------------------------------------------
# DOES IT PARSE (ovation#155). Every check above reads lines, which is blind to
# the one failure that costs most: a file GitHub cannot parse runs NO jobs and
# reports a failure with no log, which from `gh run list` is indistinguishable
# from a job that ran and failed. That is exactly how the liveness workflow first
# shipped: an unindented line inside a `run: |` block ended the block scalar.
BAD="$WORK/badyaml"; good_workflow "$BAD"
cat >> "$BAD/ci.yml" <<'YML'
      - name: A step whose script ends the block early
        run: |
          echo "inside the block"
this line is not indented and is not a key
YML
check "a workflow file that does not parse is refused" "$(status_of "$BAD")" "1"
check "and it says so in those words, rather than as a missing job or timeout" \
    "$(run_check "$BAD" | grep -ci 'does not parse')" "1"
check "and it says what an unparseable workflow actually does" \
    "$(run_check "$BAD" | grep -ci 'runs NO jobs')" "1"

# AND THE PASSING CASE NAMES THE PARSER IT USED, so a run where no parser existed
# cannot read like one that parsed and found nothing wrong (L98).
check "a good workflow says which parser judged it" \
    "$(run_check "$G" | grep -ci 'parsed with:')" "1"

harness_end
