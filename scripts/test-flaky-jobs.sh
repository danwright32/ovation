#!/bin/bash
# The suite for scripts/check-flaky-jobs.sh.
#
# ovation#493. Nothing recorded that a job went red and then green on a re-run
# of the same commit: ovation#433 and ovation#279 were found by a person being
# there at the time. The check counts them over the last 30 days so a flaky suite
# has a number, and every outcome it can give is produced here (L151).
#
# THE TRACKER IS A STUB. `gh` is replaced by a script answering from fixture
# files, so nothing reaches GitHub and a case names the runs it is about rather
# than depending on what happened to fail this month (L2, L291).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "flaky job count tests" 27

TARGET="scripts/check-flaky-jobs.sh"
require_target "$TARGET"
harness_temp_dir WORK

FIX="$WORK/fixtures"
mkdir -p "$FIX"
# The stub. `run list ... --created DAY` answers runs-DAY.json, or an empty list
# for a day with no fixture; `api .../runs/ID/attempts/N/jobs` answers
# jobs-ID-N.json. FAIL_ON makes any call whose arguments contain it fail, the
# way a gh with no network does.
cat > "$WORK/gh" <<'SH'
#!/bin/bash
all="$*"
if [ -n "${FAIL_ON:-}" ] && [[ "$all" == *"$FAIL_ON"* ]]; then
  echo "HTTP 502: bad gateway" >&2; exit 1
fi
printf '%s\n' "$all" >> "$FIX/calls"
if [ "$1 $2" = "run list" ]; then
  day=""; prev=""
  for a in "$@"; do [ "$prev" = "--created" ] && day="$a"; prev="$a"; done
  if [ -f "$FIX/runs-$day.json" ]; then cat "$FIX/runs-$day.json"; else echo '[]'; fi
  exit 0
fi
if [ "$1" = "api" ]; then
  id="$(sed -E 's|.*/runs/([0-9]+)/attempts/([0-9]+)/jobs.*|\1-\2|' <<< "$2")"
  if [ -f "$FIX/jobs-$id.json" ]; then cat "$FIX/jobs-$id.json"; exit 0; fi
  echo "HTTP 404: Not Found" >&2; exit 1
fi
echo "stub gh: unexpected call: $all" >&2
exit 1
SH
chmod +x "$WORK/gh"

run_it() {
    FIX="$FIX" OVATION_GH="$WORK/gh" OVATION_REPO="owner/repo" \
        OVATION_FLAKY_TODAY="2026-09-29" python3 "$TARGET" "$@" 2>&1
}
failing_on() {
    FIX="$FIX" FAIL_ON="$1" OVATION_GH="$WORK/gh" OVATION_REPO="owner/repo" \
        OVATION_FLAKY_TODAY="2026-09-29" python3 "$TARGET" 2>&1
}

runs() {
    # day, then one JSON object per remaining argument
    local day="$1"; shift
    local IFS=,
    printf '[%s]' "$*" > "$FIX/runs-$day.json"
}
run_row() {
    # id, attempt, workflow id, workflow name, sha
    printf '{"databaseId":%s,"attempt":%s,"workflowDatabaseId":%s,"workflowName":"%s","headSha":"%s"}' \
        "$1" "$2" "$3" "$4" "$5"
}
jobs() {
    # run id, attempt, then name=conclusion pairs
    local id="$1" attempt="$2" first=1 pair; shift 2
    { printf '{"total_count":%d,"jobs":[' "$#"
      for pair in "$@"; do
        [ "$first" = 1 ] || printf ','
        first=0
        printf '{"name":"%s","conclusion":"%s"}' "${pair%%=*}" "${pair#*=}"
      done
      printf ']}'; } > "$FIX/jobs-$id-$attempt.json"
}
reset() { rm -f "$FIX"/*; }

# ---------------------------------------------------------------------------
# Nothing re-run in the window.
# ---------------------------------------------------------------------------
reset
runs 2026-09-20 "$(run_row 1 1 10 CI aaaaaaaa11111111)" "$(run_row 2 1 10 CI bbbbbbbb22222222)"
check_exit "a window where nothing was re-run is clear" 0 run_it
check "and says how many runs it read over how many days" \
    "$(run_it | grep -c 'CLEAR: 2 run(s) over the last 30 days, 0 re-run')" "1"
check "and it asked about every day of the window, today included" \
    "$(grep -c -- '--created' "$FIX/calls")" "$((30 * 2))"
check "and it never asked for the jobs of a run that was not re-run" \
    "$(grep -c 'attempts' "$FIX/calls")" "0"

# ---------------------------------------------------------------------------
# THE CASE THIS EXISTS FOR: a job red on the first attempt and green on the re-run.
# ---------------------------------------------------------------------------
reset
runs 2026-09-20 "$(run_row 7 2 10 CI 94b195b2aaaaaaaa)"
jobs 7 1 "Shell suites on Linux=failure" "Build both configurations=success"
jobs 7 2 "Shell suites on Linux=success" "Build both configurations=success"
check_exit "a job that failed then passed on a re-run of the same run is found" 1 run_it
check "and it is named with its workflow, its count and the commit" \
    "$(run_it | grep -c 'FLAKY  CI: Shell suites on Linux, 1 time(s): run 7 on 94b195b2')" "1"
check "and the job that passed both times is not accused" \
    "$(run_it | grep -c 'Build both configurations')" "0"
check "and the verdict counts it" \
    "$(run_it | grep -c 'FOUND: 1 job(s) went red then green on a re-run of the same commit, 1 time(s) in all')" "1"

# COUNTED PER JOB ACROSS RUNS, keyed on the workflow's id rather than its name,
# and the name shown is the one the newest run carried.
reset
runs 2026-09-20 "$(run_row 7 2 10 CI aaaaaaaa00000001)"
runs 2026-09-25 "$(run_row 8 3 10 'CI renamed' bbbbbbbb00000002)" "$(run_row 9 2 11 Other cccccccc00000003)"
jobs 7 1 "Shell=failure"; jobs 7 2 "Shell=success"
jobs 8 1 "Shell=failure"; jobs 8 2 "Shell=failure"; jobs 8 3 "Shell=success"
jobs 9 1 "Shell=failure"; jobs 9 2 "Shell=success"
check "two flakes of one job in one workflow are one line counting two" \
    "$(run_it | grep -c 'FLAKY  CI renamed: Shell, 2 time(s): run 7 on aaaaaaaa, run 8 on bbbbbbbb')" "1"
check "and a job of the same name in another workflow is its own line" \
    "$(run_it | grep -c 'FLAKY  Other: Shell, 1 time(s)')" "1"

# FAILED THEN PASSED, IN THAT ORDER. Passed then failed is a regression or a
# change in the world, not a flake, and a job that only failed is just red.
reset
runs 2026-09-20 "$(run_row 7 2 10 CI aaaaaaaa11111111)" "$(run_row 8 2 10 CI bbbbbbbb22222222)"
jobs 7 1 "Shell=success"; jobs 7 2 "Shell=failure"
jobs 8 1 "Shell=failure"; jobs 8 2 "Shell=failure"
check_exit "passed then failed, or failed twice, is not a flake" 0 run_it
check "and the re-runs were still counted" \
    "$(run_it | grep -c 'CLEAR: 2 run(s) over the last 30 days, 2 re-run')" "1"

# A CANCELLED OR SKIPPED ATTEMPT IS NOT A FAILURE, and the decision says failure.
reset
runs 2026-09-20 "$(run_row 7 2 10 CI aaaaaaaa11111111)"
jobs 7 1 "Shell=cancelled"; jobs 7 2 "Shell=success"
check_exit "a cancelled attempt followed by a pass is not a flake" 0 run_it

# SEPARATE RUNS ON ONE COMMIT ARE NOT RE-RUNS. A new run exists because a new
# event arrived, a schedule, an edited pull request or a finished workflow, and
# that event is an input besides the commit: a monitor going green when the
# world changed is the monitor working (L144).
reset
runs 2026-09-20 "$(run_row 7 1 10 CI aaaaaaaa11111111)" "$(run_row 8 1 10 CI aaaaaaaa11111111)"
check_exit "two single attempt runs on one commit are not asked about" 0 run_it
check "and no jobs were fetched for them" "$(grep -c 'attempts' "$FIX/calls")" "0"

# ---------------------------------------------------------------------------
# NOTHING MEASURED IS NOT A PASS, and each way of measuring nothing is its own
# sentence (L98, L11).
# ---------------------------------------------------------------------------
reset
runs 2026-09-20 "$(run_row 7 2 10 CI aaaaaaaa11111111)"
jobs 7 1 "Shell=failure"; jobs 7 2 "Shell=success"
check_exit "a day that could not be listed cannot measure" 2 failing_on "--created 2026-09-11"
check "and names the day" \
    "$(failing_on "--created 2026-09-11" | grep -c 'the runs created on 2026-09-11 could not be listed')" "1"
check_exit "an attempt whose jobs could not be read cannot measure" 2 failing_on "attempts/1/jobs"
check "and names the run" \
    "$(failing_on "attempts/1/jobs" | grep -c 'the jobs of run 7 attempt 1 could not be read')" "1"

printf 'HTTP 504\n' > "$FIX/runs-2026-09-21.json"
check_exit "a day listed as something that is not JSON cannot measure" 2 run_it
rm -f "$FIX/runs-2026-09-21.json"

# A DAY AS LONG AS THE LIST'S LIMIT may have been cut short, and the runs past
# it are exactly the ones this cannot see (L211).
limited() {
    FIX="$FIX" OVATION_GH="$WORK/gh" OVATION_REPO="owner/repo" OVATION_FLAKY_TODAY="2026-09-29" \
        OVATION_FLAKY_DAY_LIMIT=1 python3 "$TARGET" 2>&1
}
check_exit "a day as long as its limit cannot measure" 2 limited
check "and says it may have been cut short" \
    "$(limited | grep -c 'may have been cut short')" "1"

# AN ATTEMPT WITH MORE JOBS THAN WERE RETURNED was paged, and a job on the page
# not read could be the flaky one.
jobs 7 1 "Shell=failure"
python3 -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["total_count"]=150; json.dump(d,open(p,"w"))' "$FIX/jobs-7-1.json"
check_exit "an attempt holding more jobs than were returned cannot measure" 2 run_it
check "and says the jobs were not all read" \
    "$(run_it | grep -c 'run 7 attempt 1 holds 150 job(s) and 1 were returned')" "1"

# A WINDOW WITH NO RUNS AT ALL is a lookup that went wrong: this repository runs
# something every day, and an empty month reads exactly like a clean one.
reset
check_exit "a window with no runs at all cannot measure" 2 run_it
check "and says why an empty month is not a pass" \
    "$(run_it | grep -c 'no run at all in the last 30 days')" "1"

check_exit "an argument it does not take is refused as used wrongly" 3 run_it --days 7

harness_end
