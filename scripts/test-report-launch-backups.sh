#!/bin/bash
# How close the real launch backups came to their deadline, read from the record
# each one leaves.
#
# ovation#557. Every launch backup appends a line to launch-backups.jsonl, and
# scripts/report-launch-backups.sh is its reader, where the allowances in
# LaunchBackupOutcome.swift are re-judged from. The lines here are the committed
# sample integration/launch-backups-sample.jsonl, which a Swift test holds to be
# exactly what the record writes, so this suite reads the format the app writes
# rather than one it was written against (L26, L52). Every case names its own
# throwaway record, so nothing here can read Dan's (L2).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "launch backup report tests" 31

TARGET="scripts/report-launch-backups.sh"
SAMPLE="integration/launch-backups-sample.jsonl"
require_target "$TARGET"
require_target "$SAMPLE"
harness_temp_dir WORK
RECORD="$WORK/launch-backups.jsonl"

run_report() { OVATION_LAUNCH_BACKUP_RECORD="$RECORD" bash "$TARGET" 2>&1; }
says() { if grep -qF -- "$2" <<< "$1"; then echo yes; else echo no; fi; }

# 1. THE SAMPLE: two whole copies, a skip, a refusal and a launch that gave up.
cp "$SAMPLE" "$RECORD"
OUT="$(run_report)"; ST=$?
check "a readable record is reported" "$ST" "0"
check "and it counts every line" "$(says "$OUT" ": 5")" "yes"
check "and it names the tightest WHOLE copy, 410 of 5300 ms" \
    "$(says "$OUT" "Tightest whole copy: 7.7% of its deadline (410 ms of 5300 ms), 24 files, 1,200,000 bytes, on 2026-09-22.")" "yes"
check "and it counts the skip apart from the copies" \
    "$(says "$OUT" "1 found that day's backup already taken")" "yes"
check "and the refusal apart from both" "$(says "$OUT" "1 were refused by the backup")" "yes"
check "and it says out loud that a launch gave up" "$(says "$OUT" "GAVE UP: 1 launch(es)")" "yes"

# 2. A SKIP IS NEVER THE TIGHTEST. Made to look tighter than any copy (4999 of
#    5000 ms), it must not move the figure, because it timed no copy (L331).
cp "$SAMPLE" "$RECORD"
printf '%s\n' '{"at":"2026-09-25T09:00:00Z","bytes":1,"deadlineMilliseconds":5000,"elapsedMilliseconds":4999,"files":1,"outcome":"alreadyTakenToday"}' >> "$RECORD"
OUT="$(run_report)"
check "a skip does not stand in for a whole copy" "$(says "$OUT" "Tightest whole copy: 7.7%")" "yes"

# 3. NO WHOLE COPY YET is an answer, and it says so rather than printing a share.
printf '%s\n' '{"at":"2026-09-25T09:00:00Z","bytes":1,"deadlineMilliseconds":5000,"elapsedMilliseconds":3,"files":1,"outcome":"alreadyTakenToday"}' > "$RECORD"
OUT="$(run_report)"; ST=$?
check "a record with no whole copy is still reported" "$ST" "0"
check "and it says there is no headroom to judge" "$(says "$OUT" "no headroom to judge")" "yes"
check "and it claims no share" "$(says "$OUT" "Tightest")" "no"

# 4. A DAMAGED LINE costs that line and is counted (L215).
cp "$SAMPLE" "$RECORD"
printf '%s\n' '{not a line' >> "$RECORD"
OUT="$(run_report)"; ST=$?
check "a record with one damaged line is still reported" "$ST" "0"
check "and the damaged line is counted, not dropped" \
    "$(says "$OUT" "1 line(s) that could not be read")" "yes"

# 4b. A LINE WITH EVERY KEY BUT A WRONG TYPE is refused like a damaged one, by
#     the field that is wrong, rather than passing the check and crashing the
#     report later. Each numeric field is tried, and a boolean is not a number.
for bad in \
    '{"at":"2026-09-25T09:00:00Z","bytes":1,"deadlineMilliseconds":5000,"elapsedMilliseconds":"90","files":1,"outcome":"taken"}|elapsedMilliseconds' \
    '{"at":"2026-09-25T09:00:00Z","bytes":1,"deadlineMilliseconds":5000,"elapsedMilliseconds":true,"files":1,"outcome":"taken"}|elapsedMilliseconds' \
    '{"at":"2026-09-25T09:00:00Z","bytes":1,"deadlineMilliseconds":5000,"elapsedMilliseconds":90,"files":"19","outcome":"taken"}|files' \
    '{"at":"2026-09-25T09:00:00Z","bytes":null,"deadlineMilliseconds":5000,"elapsedMilliseconds":90,"files":1,"outcome":"taken"}|bytes' \
    '{"at":7,"bytes":1,"deadlineMilliseconds":5000,"elapsedMilliseconds":90,"files":1,"outcome":"taken"}|at'; do
  cp "$SAMPLE" "$RECORD"
  printf '%s\n' "${bad%|*}" >> "$RECORD"
  OUT="$(run_report)"; ST=$?
  check "a line whose ${bad#*|} has the wrong type is still reported around" "$ST" "0"
  check "and it is refused by the field that is wrong (${bad#*|})" \
      "$(says "$OUT" "1 line(s) that could not be read, which are not counted (${bad#*|} is not")" "yes"
  check "and it does not move the tightest copy (${bad#*|})" \
      "$(says "$OUT" "Tightest whole copy: 7.7%")" "yes"
done

# 5. NO RECORD cannot be measured, and is not a healthy report.
rm -f "$RECORD"
OUT="$(run_report)"; ST=$?
check "no record at all cannot be measured" "$ST" "2"
check "and it says there is no record" "$(says "$OUT" "there is no launch backup record")" "yes"

# 6. A RECORD IN WHICH NOTHING DECODES cannot be measured either.
printf '%s\n' 'garbage' '{"at":"x"}' > "$RECORD"
OUT="$(run_report)"; ST=$?
check "a record with no readable line cannot be measured" "$ST" "2"
check "and it says none could be read" "$(says "$OUT" "none of them could be read")" "yes"

harness_end
