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
harness_begin "ci workflow tests" 26

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

# ---------------------------------------------------------------------------
# WHAT A WORKFLOW RUNS, AGAINST WHAT THE INVENTORY SAYS RUNS IT (ovation#214).
#
# scripts/lib/script-roles.tsv declares for every script what watches it, and
# scripts/test-preconditions.sh already asserts ONE direction of that: every
# script declared `workflow` is named by a workflow file. Nothing asserted the
# reverse, and six scripts sat on the wrong side of it for as long as that was
# true. The six rendering checks are run by .github/workflows/ci.yml and were
# declared `tool`, which the inventory defines as "Run by a person on demand",
# each carrying a reason that was true when it was written and had since been
# answered by gate_check's three outcomes (ovation#135). So each entry read as a
# considered decision while describing a state that had changed (L346).
#
# A ONE DIRECTIONAL COMPARISON IS NOT A COMPARISON: it can only find the entries
# somebody remembered to declare, which was never the half that went wrong. Both
# sides have to be enumerated from their own source and held against each other
# (L582, L41).
#
# THIS IS WHERE IT LIVES rather than in a guard of its own, because it is the
# same question this file already exists to ask: a workflow file carries
# decisions nothing else in the repository reads, and a check a workflow runs is
# one of them.

# A workflow that names one check script in a step, and is otherwise everything
# the cases above demand: a timeout, a pinned action, the documented command.
workflow_naming() {
    # workflow_naming <dir> <script name>
    mkdir -p "$1"
    cat > "$1/ci.yml" <<YML
name: CI
jobs:
  shell-suites:
    runs-on: macos-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
      - run: python3 scripts/$2
      - run: bash scripts/build-products.sh && bash scripts/run-tests.sh
YML
}

# A fixture inventory in the real one's three column shape, so a divergence can
# be planted without touching the file the repository actually runs on (L2).
inventory_with() {
    # inventory_with <file> <script name> <role>
    printf '# A fixture inventory.\n%s\t%s\tA staged reason.\n' "$2" "$3" > "$1"
}

run_with_inventory() {
    OVATION_SCRIPT_ROLES_TSV="$2" OVATION_WORKFLOW_DIR="$1" "./$TARGET" 2>&1
}
status_with_inventory() { run_with_inventory "$1" "$2" >/dev/null 2>&1; printf '%s' "$?"; }

WF_NAMES="$WORK/wf-names-a-check"; workflow_naming "$WF_NAMES" "check-design-draws.sh"

# THE PASSING CASE FIRST, or every refusal below is satisfied by a rule that
# refuses everything it is shown (L159).
INV_WORKFLOW="$WORK/inv-workflow.tsv"
inventory_with "$INV_WORKFLOW" "check-design-draws.sh" "workflow"
check "a check a workflow runs, declared as run by a workflow, passes" \
    "$(status_with_inventory "$WF_NAMES" "$INV_WORKFLOW")" "0"

# The divergence itself: the same workflow, the same check, declared as
# something a PERSON runs when a workflow is running it.
INV_TOOL="$WORK/inv-tool.tsv"
inventory_with "$INV_TOOL" "check-design-draws.sh" "tool"
check "the same check declared as run by a person on demand is refused" \
    "$(status_with_inventory "$WF_NAMES" "$INV_TOOL")" "1"
check "and the refusal names the script and the role it carries" \
    "$(run_with_inventory "$WF_NAMES" "$INV_TOOL" | grep -c "check-design-draws\.sh.*'tool'")" "1"

# A check a workflow runs that the inventory says nothing at all about. It is a
# different fact from a wrong role and gets its own sentence (L11).
INV_SILENT="$WORK/inv-silent.tsv"
printf '# A fixture inventory that declares something else entirely.\nrun-tests.sh\ttool\tA staged reason.\n' > "$INV_SILENT"
check "a check a workflow runs that no inventory entry declares is refused" \
    "$(status_with_inventory "$WF_NAMES" "$INV_SILENT")" "1"
check "and it says there is no entry, rather than quoting a role it did not find" \
    "$(run_with_inventory "$WF_NAMES" "$INV_SILENT" | grep -ci 'no inventory entry')" "1"

# ONE SIDE OF A COMPARISON MISSING IS NOT A PASS (L345, L98). An inventory that
# cannot be read leaves the question unanswered, and answering it anyway is a
# tick over a comparison that never happened.
check "an inventory that is not there is refused rather than passed over" \
    "$(status_with_inventory "$WF_NAMES" "$WORK/no-such-inventory.tsv")" "1"

# A NAME IN A COMMENT IS NOT A CHECK BEING RUN (L135). Both workflow files
# explain themselves at length and name scripts while doing it, so a rule reading
# the whole file would refuse on a sentence about a check rather than on a step
# that runs one.
WF_COMMENT="$WORK/wf-comment"; mkdir -p "$WF_COMMENT"
good_workflow "$WF_COMMENT"
sed_in_place "$WF_COMMENT/ci.yml" \
    's|^name: CI$|# Why check-design-draws.sh is not run here, at length.\nname: CI|'
check "a check named only in a comment is not treated as one a workflow runs" \
    "$(status_with_inventory "$WF_COMMENT" "$INV_SILENT")" "0"

# IT SAYS HOW MANY IT COMPARED, because a comparison that found nothing to
# compare passes exactly like one that compared eight and agreed (L100, L98).
check "it says how many check scripts the workflows name" \
    "$(run_with_inventory "$WF_NAMES" "$INV_WORKFLOW" | grep -cE '[0-9]+ check script')" "1"

# AND THE REAL TREE HAS SOMETHING FOR IT TO JUDGE. Asserted as a floor rather
# than a count, because the count is meant to grow and a test pinned to today's
# would fail on the next check a workflow gains (L63).
REAL_NAMED="$(run_check ".github/workflows" | grep -oE '[0-9]+ check script' | grep -oE '^[0-9]+' | head -1)"
check "this repository's own workflows name checks for the rule to judge" \
    "$([ "${REAL_NAMED:-0}" -ge 1 ] && echo named || echo none)" "named"

harness_end
