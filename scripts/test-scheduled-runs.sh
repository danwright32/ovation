#!/bin/bash
# Every scheduled workflow is still RUNNING, judged by its newest scheduled run.
#
# ovation#387. A failing scheduled run is loud; a schedule that stopped is silent,
# and GitHub disables every schedule in a repository after 60 days of no activity
# without failing anything. A watcher whose silence also means "all is well"
# cannot be told from one that stopped (L13, L98). Judged on whether it RAN, never
# on whether it passed, or a watchdog could never clear its own correct alarm (L71).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "scheduled run tests" 20

TARGET="scripts/check-scheduled-runs.sh"
require_target "$TARGET"
harness_temp_dir WORK

WF="$WORK/workflows"; mkdir -p "$WF"
daily() { printf 'name: %s\non:\n  schedule:\n    - cron: %s\n' "$1" "'17 13 * * *'" > "$WF/$1.yml"; }
printf 'name: pushed\non:\n  push:\n    branches: [main]\n' > "$WF/pushed.yml"

# A STAND IN FOR gh, answering from files by workflow file name (L2). `last-<f>`
# holds the newest scheduled run's time, `state-<f>` the workflow's state, and
# `created-<f>` when GitHub first saw the workflow, in the shape its API gives it.
cat > "$WORK/gh" <<'SH'
#!/bin/bash
for a in "$@"; do case "$a" in *.yml) f="${a##*/}" ;; esac; done
case "$1" in
  run) cat "$FAKE/last-$f" 2>/dev/null ;;
  api)
    case " $* " in
      *created_at*) cat "$FAKE/created-$f" 2>/dev/null ;;
      *) cat "$FAKE/state-$f" 2>/dev/null || echo active ;;
    esac ;;
esac
SH
chmod +x "$WORK/gh"
NOW=1790000000   # a fixed instant, so no case depends on the real clock (L130)
iso() { python3 -c 'import sys,datetime; print(datetime.datetime.fromtimestamp(int(sys.argv[1]), datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
run_check() { FAKE="$WORK" OVATION_GH="$WORK/gh" OVATION_NOW="$NOW" OVATION_WORKFLOW_DIR="$WF" \
    OVATION_REPO=danwright32/ovation bash "$TARGET" 2>&1; }
says() { if grep -qF -- "$2" <<< "$1"; then echo yes; else echo no; fi; }

# 1. EVERY DAILY SCHEDULE RAN IN THE LAST DAY: pass, and a push-only workflow is
#    not a schedule and is not asked about.
daily watcher; daily recorder
iso $((NOW - 3600)) > "$WORK/last-watcher.yml"; iso $((NOW - 20 * 3600)) > "$WORK/last-recorder.yml"
OUT="$(run_check)"; ST=$?
check "every daily schedule that ran within its day passes" "$ST" "0"
check "and it names how many schedules it judged" "$(says "$OUT" "2 scheduled workflow(s)")" "yes"

# 2. STOPPED: a daily schedule whose newest run is three days old.
iso $((NOW - 3 * 86400)) > "$WORK/last-recorder.yml"
OUT="$(run_check)"; ST=$?
check "a daily schedule with no run for three days is reported as stopped" "$ST" "1"
check "and it names that workflow" "$(says "$OUT" "recorder.yml")" "yes"

# 3. DISABLED BY GITHUB, said by name, because its remedy is re-enabling it.
iso $((NOW - 3600)) > "$WORK/last-recorder.yml"
echo disabled_inactivity > "$WORK/state-recorder.yml"
OUT="$(run_check)"; ST=$?
check "a schedule GitHub disabled is reported" "$ST" "1"
check "and it says GitHub disabled it" "$(says "$OUT" "disabled_inactivity")" "yes"
rm -f "$WORK/state-recorder.yml"

# THE SHAPE GITHUB'S WORKFLOW API RETURNS, measured 2026-10-08: milliseconds and
# an offset, not the Z form runs carry, so the parse is driven by the real one.
api_time() { python3 -c 'import sys,datetime; print(datetime.datetime.fromtimestamp(int(sys.argv[1]), datetime.timezone(datetime.timedelta(hours=-4))).strftime("%Y-%m-%dT%H:%M:%S.000-04:00"))' "$1"; }

# 4. NEVER RAN AT ALL is stopped too, never "nothing to judge" (L557), once it
#    has been there long enough that it should have run: here, added a month
#    ago, so it is the old schedule that is judged and not an unreadable date
#    (4c covers that path).
rm -f "$WORK/last-recorder.yml"
api_time $((NOW - 30 * 86400)) > "$WORK/created-recorder.yml"
OUT="$(run_check)"; ST=$?
check "a schedule added a month ago with no run on record is reported" "$ST" "1"
check "and it is stopped for having been added long ago, not for an unreadable date" \
    "$(says "$OUT" "could not be read")" "no"

# 4b. A SCHEDULE TOO NEW TO HAVE RUN YET (ovation#661). On 2026-09-29 two new
#     daily workflows each turned CI liveness red for most of a day before their
#     first scheduled run, which is the alarm firing on a normal event. Until the
#     workflow is older than one period plus the grace for GitHub's lateness, no
#     run on record is NOT YET DUE, its own outcome. The window is read from the
#     script rather than written here, so moving the grace moves both sides of
#     these fixtures with it (L401).
GRACE_HOURS="$(sed -nE 's/^GRACE_SECONDS=\$\(\(([0-9]+) \* 3600\)\)$/\1/p' "$TARGET")"
check "the grace this reads from the script is a number of hours" \
    "$(grep -cE '^[0-9]+$' <<< "${GRACE_HOURS:-}")" "1"
WINDOW=$((86400 + ${GRACE_HOURS:-0} * 3600))
api_time $((NOW - WINDOW + 3600)) > "$WORK/created-recorder.yml"
OUT="$(run_check)"; ST=$?
check "a schedule added inside its first window with no run yet does not fail the check" "$ST" "0"
check "and it is reported as not yet due, its own outcome" "$(says "$OUT" "NOT YET DUE")" "yes"
check "and not as stopped" "$(says "$OUT" "STOPPED")" "no"
check "and the summary does not claim every schedule ran" "$(says "$OUT" "not yet due")" "yes"

api_time $((NOW - WINDOW - 3600)) > "$WORK/created-recorder.yml"
OUT="$(run_check)"; ST=$?
check "the same schedule an hour past its first window with still no run is stopped" "$ST" "1"
check "and it says how long ago it was added" "$(says "$OUT" "added")" "yes"

# 4c. WHEN IT WAS ADDED CANNOT BE READ: stopped, as before, and said so, because
#     an unreadable date is no evidence the schedule is new (L42, L11).
echo "not a date" > "$WORK/created-recorder.yml"
OUT="$(run_check)"; ST=$?
check "a schedule with no run whose added date cannot be read is still stopped" "$ST" "1"
check "and it says the date could not be read" "$(says "$OUT" "could not be read")" "yes"
rm -f "$WORK/created-recorder.yml"
iso $((NOW - 3600)) > "$WORK/last-recorder.yml"

# 5. A SCHEDULE THIS CANNOT READ is refused rather than guessed at.
printf 'name: odd\non:\n  schedule:\n    - cron: %s\n' "'0 */6 * * *'" > "$WF/odd.yml"
OUT="$(run_check)"; ST=$?
check "a cron this cannot turn into a period cannot be measured" "$ST" "2"
check "and it names the cron" "$(says "$OUT" "0 */6 * * *")" "yes"
rm -f "$WF/odd.yml"

# 6. NO SCHEDULES AT ALL is CANNOT MEASURE, never a pass over nothing.
rm -f "$WF/watcher.yml" "$WF/recorder.yml"
OUT="$(run_check)"; ST=$?
check "a tree with no scheduled workflow cannot be measured" "$ST" "2"

harness_end
