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
harness_begin "scheduled run tests" 10

TARGET="scripts/check-scheduled-runs.sh"
require_target "$TARGET"
harness_temp_dir WORK

WF="$WORK/workflows"; mkdir -p "$WF"
daily() { printf 'name: %s\non:\n  schedule:\n    - cron: %s\n' "$1" "'17 13 * * *'" > "$WF/$1.yml"; }
printf 'name: pushed\non:\n  push:\n    branches: [main]\n' > "$WF/pushed.yml"

# A STAND IN FOR gh, answering from files by workflow file name (L2). `last-<f>`
# holds the newest scheduled run's time, `state-<f>` the workflow's state.
cat > "$WORK/gh" <<'SH'
#!/bin/bash
for a in "$@"; do case "$a" in *.yml) f="${a##*/}" ;; esac; done
case "$1" in
  run) cat "$FAKE/last-$f" 2>/dev/null ;;
  api) cat "$FAKE/state-$f" 2>/dev/null || echo active ;;
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

# 4. NEVER RAN AT ALL is stopped too, never "nothing to judge" (L557).
rm -f "$WORK/last-recorder.yml"
OUT="$(run_check)"; ST=$?
check "a schedule with no run on record is reported" "$ST" "1"
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
