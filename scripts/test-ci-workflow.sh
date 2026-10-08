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
harness_begin "ci workflow tests" 50

TARGET="scripts/check-ci-workflow.sh"
require_target "$TARGET"
harness_temp_dir WORK

run_check() { OVATION_WORKFLOW_DIR="$1" "./$TARGET" 2>&1; }
status_of() { run_check "$1"; }

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
on:
  push:
    branches: [main]
  pull_request:
jobs:
  shell-suites:
    runs-on: macos-26
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
      - run: bash scripts/select-xcode.sh
      - run: bash scripts/run-tests.sh
  build-and-test:
    runs-on: macos-26
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
      - run: bash scripts/select-xcode.sh
      - run: bash scripts/build-products.sh && bash scripts/run-tests.sh
  a-linux-job:
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - run: bash scripts/run-tests.sh
YML
}

# 1. THE PASSING CASE HAS TO BE PRODUCED FIRST, or every refusal below is
#    satisfied by a check that refuses everything (L159).
G="$WORK/good"; good_workflow "$G"
check_exit "a workflow carrying all three passes" 0 status_of "$G"

# 2. No workflow directory at all. This is the state ovation#143 was filed about,
#    and it is a refusal rather than a cannot measure: the repository decided to
#    have CI, so its absence is a fault and not an unanswerable question.
check_exit "no workflow directory is refused" 1 status_of "$WORK/nothing"
check "and it says there is no CI rather than naming a file" \
    "$(run_check "$WORK/nothing" | grep -ci 'no workflow')" "1"

# 3. A job with no timeout. The platform default is six hours, and a hung job
#    holds a runner slot for all of it.
B1="$WORK/notimeout"; good_workflow "$B1"
sed_in_place "$B1/ci.yml" '/timeout-minutes: 20/d' 
check_exit "a job with no timeout is refused" 1 status_of "$B1"
check "and it names the job that has none" \
    "$(run_check "$B1" | grep -c 'shell-suites')" "1"

# 4. An action on a moving tag rather than a commit.
B2="$WORK/unpinned"; good_workflow "$B2"
sed_in_place "$B2/ci.yml" 's|actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1|actions/checkout@v4|' 
check_exit "an action pinned to a tag rather than a commit is refused" 1 status_of "$B2"
# BOTH uses, not the first one. A guard that reports the first instance teaches
# whoever fixes it that there was one (L30).
check "and it names every unpinned use, not just the first" \
    "$(run_check "$B2" | grep -c 'actions/checkout@v4')" "2"

# 5. The documented command gone. This is the decision itself going missing, and
#    it is the one failure that leaves a green tick on the board (L400).
B3="$WORK/nobuild"; good_workflow "$B3"
sed_in_place "$B3/ci.yml" 's|bash scripts/build-products.sh && bash scripts/run-tests.sh|bash scripts/run-tests.sh|' 
check_exit "a workflow that never builds both configurations is refused" 1 status_of "$B3"
check "and it quotes the command it expected to find" \
    "$(run_check "$B3" | grep -c 'build-products.sh')" "1"

# 5b. A MAC JOB THAT BUILDS WITH WHATEVER XCODE THE IMAGE SHIPS (ovation#270).
#     Both Mac jobs used the image default and nothing named a version, so an
#     image update could move the compiler with no change here. Each Mac job must
#     select the pinned Xcode; the Linux job in the fixture has none to select and
#     is not asked to, which is what the passing case above already proves.
B4="$WORK/noxcode"; good_workflow "$B4"
# THE FIRST SELECTION ONLY, by awk rather than sed: the sed spelling of "first
# match" is `0,/re/`, which GNU reads and BSD does not, and neither errors on the
# other's form in a way a reader would predict (L434). The deletion is still
# proved rather than assumed, because a fixture that selects in both jobs would
# pass the refusal below for the wrong reason (L159).
awk '!done && /bash scripts\/select-xcode.sh/ { done = 1; next } { print }' "$B4/ci.yml" > "$B4/ci.yml.tmp" \
    && mv "$B4/ci.yml.tmp" "$B4/ci.yml"
check "the fixture really lost one job's selection" \
    "$(grep -c 'select-xcode.sh' "$B4/ci.yml")" "1"
check_exit "a macOS job that does not select the pinned Xcode is refused" 1 status_of "$B4"
check "and it names that job" \
    "$(run_check "$B4" | grep -c 'NO PINNED XCODE: shell-suites')" "1"
# A COMMENT NAMING THE SELECTOR IS NOT A STEP RUNNING IT: comment lines are
# dropped, the same rule lib/workflow-text.sh applies to a whole file
# (ovation#221, L135).
B5="$WORK/xcodecomment"; good_workflow "$B5"
sed_in_place "$B5/ci.yml" 's|      - run: bash scripts/select-xcode.sh|      # - run: bash scripts/select-xcode.sh|'
check "a selection that is only a comment is refused in every Mac job" \
    "$(run_check "$B5" | grep -c 'NO PINNED XCODE')" "2"

# 6. AND THE REAL WORKFLOW PASSES ITS OWN CHECK. Everything above is a fixture;
#    this is the assertion that goes red the day the real file drifts.
check_exit "this repository's own workflow passes" 0 status_of ".github/workflows"

# 7. It reports what it examined, so a run over an empty directory cannot read
#    like a thorough one (L98).
OUT="$(run_check "$G")"
check "it says how many jobs it examined" "$(printf '%s' "$OUT" | grep -cE '[0-9]+ job')" "1"
check "and how many workflow files" "$(printf '%s' "$OUT" | grep -cE '[0-9]+ workflow file')" "1"

# 8. A workflow directory that exists and holds no workflow is its own refusal,
#    not a pass over zero files.
E="$WORK/empty"; mkdir -p "$E"
check_exit "a workflow directory holding no workflow is refused" 1 status_of "$E"


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
check_exit "a workflow file that does not parse is refused" 1 status_of "$BAD"
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
    runs-on: macos-26
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
      - run: bash scripts/select-xcode.sh
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
status_with_inventory() { run_with_inventory "$1" "$2"; }

WF_NAMES="$WORK/wf-names-a-check"; workflow_naming "$WF_NAMES" "check-design-draws.sh"

# THE PASSING CASE FIRST, or every refusal below is satisfied by a rule that
# refuses everything it is shown (L159).
INV_WORKFLOW="$WORK/inv-workflow.tsv"
inventory_with "$INV_WORKFLOW" "check-design-draws.sh" "workflow"
check_exit "a check a workflow runs, declared as run by a workflow, passes" \
    0 status_with_inventory "$WF_NAMES" "$INV_WORKFLOW"

# The divergence itself: the same workflow, the same check, declared as
# something a PERSON runs when a workflow is running it.
INV_TOOL="$WORK/inv-tool.tsv"
inventory_with "$INV_TOOL" "check-design-draws.sh" "tool"
check_exit "the same check declared as run by a person on demand is refused" \
    1 status_with_inventory "$WF_NAMES" "$INV_TOOL"
check "and the refusal names the script and the role it carries" \
    "$(run_with_inventory "$WF_NAMES" "$INV_TOOL" | grep -c "check-design-draws\.sh.*'tool'")" "1"

# A check a workflow runs that the inventory says nothing at all about. It is a
# different fact from a wrong role and gets its own sentence (L11).
INV_SILENT="$WORK/inv-silent.tsv"
printf '# A fixture inventory that declares something else entirely.\nrun-tests.sh\ttool\tA staged reason.\n' > "$INV_SILENT"
check_exit "a check a workflow runs that no inventory entry declares is refused" \
    1 status_with_inventory "$WF_NAMES" "$INV_SILENT"
check "and it says there is no entry, rather than quoting a role it did not find" \
    "$(run_with_inventory "$WF_NAMES" "$INV_SILENT" | grep -ci 'no inventory entry')" "1"

# ONE SIDE OF A COMPARISON MISSING IS NOT A PASS (L345, L98). An inventory that
# cannot be read leaves the question unanswered, and answering it anyway is a
# tick over a comparison that never happened.
check_exit "an inventory that is not there is refused rather than passed over" \
    1 status_with_inventory "$WF_NAMES" "$WORK/no-such-inventory.tsv"

# A NAME IN A COMMENT IS NOT A CHECK BEING RUN (L135). Both workflow files
# explain themselves at length and name scripts while doing it, so a rule reading
# the whole file would refuse on a sentence about a check rather than on a step
# that runs one.
WF_COMMENT="$WORK/wf-comment"; mkdir -p "$WF_COMMENT"
good_workflow "$WF_COMMENT"
sed_in_place "$WF_COMMENT/ci.yml" \
    's|^name: CI$|# Why check-design-draws.sh is not run here, at length.\nname: CI|'
check_exit "a check named only in a comment is not treated as one a workflow runs" \
    0 status_with_inventory "$WF_COMMENT" "$INV_SILENT"

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

# ---------------------------------------------------------------------------
# ONE COMMIT, ONE RUN (ovation#304).
#
# ci.yml ran on a push to EVERY branch and on pull_request, and its concurrency
# group was keyed on github.ref, which is the branch for one event and the pull
# request's merge ref for the other. So neither run cancelled the other, and
# every commit on a branch with an open pull request built both configurations
# twice. On 2026-09-14 a pull request's jobs sat queued over 25 minutes behind
# those duplicates, and after ovation#15 each one bills macOS minutes.
#
# Nothing read the branch push runs: no ruleset or branch protection exists, the
# liveness workflow reads runs on main only, and the closing keyword check has
# its own workflow. So the rule is the trigger shape itself, over every workflow
# file, because a second workflow copied from this one would double the same way
# (L30): a workflow that runs on pull requests may run on push to main only.
twice_workflow() {
    # twice_workflow <dir> <the on: block, as lines>
    # Assembled with printf and sed rather than `awk -v`, which BSD awk refuses
    # for a value holding a newline (L434).
    good_workflow "$1"
    { printf 'name: CI\n%s\n' "$2"; sed -n '/^jobs:/,$p' "$1/ci.yml"; } > "$1/ci.yml.tmp" \
        && mv "$1/ci.yml.tmp" "$1/ci.yml"
}

T1="$WORK/twice-every-branch"
twice_workflow "$T1" "on:
  push:
    branches: ['**']
  pull_request:"
check_exit "a workflow on pull requests and on push to every branch is refused" 1 status_of "$T1"
check "and it names the file that runs twice" \
    "$(run_check "$T1" | grep -c 'RUNS TWICE PER PULL REQUEST COMMIT: ci.yml')" "1"

T2="$WORK/twice-unfiltered"
twice_workflow "$T2" "on:
  push:
  pull_request:"
check_exit "a push with no branch filter beside pull requests is refused" 1 status_of "$T2"

T3="$WORK/twice-inline"
twice_workflow "$T3" "on: [push, pull_request]"
check_exit "the one line spelling of the same two triggers is refused" 1 status_of "$T3"

T4="$WORK/once-block-list"
twice_workflow "$T4" "on:
  push:
    branches:
      - main
  pull_request:"
check_exit "push to main written as a block list, beside pull requests, passes" 0 status_of "$T4"

# ---------------------------------------------------------------------------
# A RUNNER LABEL THAT NAMES A VERSION (ovation#663).
#
# `ubuntu-latest` is GitHub's choice of image, and GitHub announced it moves to
# Ubuntu 26 on 2026-10-19. The Linux job runs the shell suites, which test real
# shell behaviour, so a new bash, coreutils, git or flock would turn them red
# overnight with no change here, and the red would read as a regression in
# Ovation. A moving label is the same thing as a moving action tag (L25), so it
# is refused the same way, in every workflow file, for every image.
L1="$WORK/latest-runner"; good_workflow "$L1"
sed_in_place "$L1/ci.yml" 's|runs-on: ubuntu-24.04|runs-on: ubuntu-latest|'
check_exit "a job on a -latest runner label is refused" 1 status_of "$L1"
check "and it names the job and the label it moves with" \
    "$(run_check "$L1" | grep -c 'MOVING RUNNER IMAGE: a-linux-job in ci.yml runs on ubuntu-latest')" "1"
# A COMMENT NAMING THE LABEL IS NOT A JOB RUNNING ON IT (L135): the ci.yml
# comments explain why the label is not used, and must not refuse themselves.
L2="$WORK/latest-in-comment"; good_workflow "$L2"
# By awk, because a newline in a sed replacement is GNU only and BSD writes an n.
awk '$0 == "    runs-on: ubuntu-24.04" { print "    # not ubuntu-latest, which moves on its own" } { print }' \
    "$L2/ci.yml" > "$L2/ci.yml.tmp" && mv "$L2/ci.yml.tmp" "$L2/ci.yml"
check "the fixture really names the label in a comment" "$(grep -c '# not ubuntu-latest' "$L2/ci.yml")" "1"
check_exit "a -latest label named only in a comment passes" 0 status_of "$L2"

# ---------------------------------------------------------------------------
# A PIN SAYS WHICH RELEASE IT IS (ovation#663).
#
# The checkout pin was a bare commit for its whole life, so nothing on the line
# said it was v4.2.2, and that release targets Node 20, which GitHub deprecated.
# The first anyone knew was a warning in a run log. A pin is reviewed by reading
# it, and a commit hash cannot be read, so every pin carries the release it is.
V1="$WORK/pin-no-release"; good_workflow "$V1"
sed_in_place "$V1/ci.yml" 's|  # v7.0.1$||'
check_exit "a commit pin with no release beside it is refused" 1 status_of "$V1"
check "and it names every such pin, not just the first" \
    "$(run_check "$V1" | grep -c 'PIN NAMES NO RELEASE: actions/checkout@3d3c42e5')" "2"

# ---------------------------------------------------------------------------
# EVERY COMMIT MERGED TO MAIN GETS ITS OWN VERDICT (ovation#662).
#
# ci.yml ran in one concurrency group per ref with cancel-in-progress true, which
# on main cancelled the run of a merge whenever the next merge landed: 42 main
# runs in September 2026. Running on main after a squash merge exists to catch
# two pull requests that were green alone and break together, and the cancelled
# run is exactly the evidence needed to say which merge broke it.
#
# TURNING CANCELLATION OFF IS NOT ENOUGH. A group holds one running and ONE
# pending run, and a newly queued run cancels the pending one whatever
# cancel-in-progress says, so three merges in quick succession still lose the
# middle verdict. On main the group has to be one per commit.
#
# THE RULE IS WRITTEN AS THE REASON (L362): a workflow that runs on pull requests
# and again on push to main is a check whose main run is the verdict on the
# merge. A writer that runs on main alone is not asked, because a superseded
# write is redone by the next one. A check whose main run a newer one makes
# redundant says so, with the reason, on a marker line.
with_concurrency() {
    # with_concurrency <dir> <lines placed before jobs:, as one string>
    good_workflow "$1"
    { sed '/^jobs:/,$d' "$1/ci.yml"; printf '%s\n' "$2"; sed -n '/^jobs:/,$p' "$1/ci.yml"; } \
        > "$1/ci.yml.tmp" && mv "$1/ci.yml.tmp" "$1/ci.yml"
}

C1="$WORK/cancels-main"
with_concurrency "$C1" "concurrency:
  group: ci-\${{ github.ref }}
  cancel-in-progress: true"
check_exit "a pull request check that cancels its runs on main is refused" 1 status_of "$C1"
check "and it says the merge loses its verdict, naming the file" \
    "$(run_check "$C1" | grep -c 'MAIN RUNS CAN BE CANCELLED: ci.yml')" "1"

C2="$WORK/one-group-on-main"
with_concurrency "$C2" "concurrency:
  group: ci-\${{ github.ref }}
  cancel-in-progress: \${{ github.ref != 'refs/heads/main' }}"
check_exit "cancellation off on main, but one group for all of main, is refused" 1 status_of "$C2"
check "and it names the shared group as what still drops a pending run" \
    "$(run_check "$C2" | grep -c 'ONE CONCURRENCY GROUP FOR ALL OF MAIN: ci.yml')" "1"

C3="$WORK/per-commit-on-main"
with_concurrency "$C3" "concurrency:
  group: ci-\${{ github.ref == 'refs/heads/main' && github.sha || github.ref }}
  cancel-in-progress: \${{ github.ref != 'refs/heads/main' }}"
check_exit "a group per commit on main, cancelling only elsewhere, passes" 0 status_of "$C3"

C4="$WORK/superseded-with-reason"
with_concurrency "$C4" "# ovation-main-runs-superseded: a newer run asks the same question of the newer main
concurrency:
  group: ci-\${{ github.ref }}
  cancel-in-progress: true"
check_exit "a check that declares, with a reason, why a newer main run supersedes passes" \
    0 status_of "$C4"

# AN ESCAPE HATCH WITH NO REASON IS NOT A DECISION (L675).
C5="$WORK/superseded-no-reason"
with_concurrency "$C5" "# ovation-main-runs-superseded:
concurrency:
  group: ci-\${{ github.ref }}
  cancel-in-progress: true"
check_exit "the same marker carrying no reason is refused" 1 status_of "$C5"

# A WRITER ON MAIN ALONE IS NOT A PULL REQUEST CHECK, and the next run redoes
# whatever a dropped one would have written, so it is not asked.
C6="$WORK/writer-on-main"
with_concurrency "$C6" "concurrency:
  group: a-writer
  cancel-in-progress: false"
sed_in_place "$C6/ci.yml" '/^  pull_request:$/d'
check "the writer fixture really runs on main only" "$(grep -c 'pull_request' "$C6/ci.yml")" "0"
check_exit "a workflow on push to main only, in one group, passes" 0 status_of "$C6"

harness_end
