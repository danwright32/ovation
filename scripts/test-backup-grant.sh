#!/bin/bash
# ovation#232. The recorded answer to a question only a person can ask.
#
# EVERY OUTCOME IS DRIVEN, not merely the one this machine happens to be in
# (L151). Nothing here touches the real record: the path is injected, so a test
# can never write into docs/backup-grant-checks.tsv (L2, L201).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "backup grant record tests" 18

CHECK="scripts/check-backup-grant.sh"
RECORDER="scripts/record-backup-grant-check.sh"
require_target "$CHECK"
require_target "$RECORDER"
harness_temp_dir WORK

check_with() { OVATION_GRANT_RECORD="$1" bash "$CHECK" 2>&1; }
status_with() { OVATION_GRANT_RECORD="$1" bash "$CHECK" >/dev/null 2>&1; printf '%s' "$?"; }
record_with() { OVATION_GRANT_RECORD="$1" bash "$RECORDER" "${@:2}" 2>&1; }
record_status() { OVATION_GRANT_RECORD="$1" bash "$RECORDER" "${@:2}" >/dev/null 2>&1; printf '%s' "$?"; }

# 1. NOTHING RECORDED IS NOT A PASS. This is the state the repository is in
#    today, and it must stay visible until somebody answers it (L98).
MISSING="$WORK/no-such-record.tsv"
check "an unanswered question is CANNOT MEASURE, never a pass" \
    "$(status_with "$MISSING")" "2"
check "and it says nobody has confirmed it" \
    "$(check_with "$MISSING" | grep -ci 'has ever been recorded')" "1"
check "and it names where the steps are" \
    "$(check_with "$MISSING" | grep -c 'BACKUP-GRANT-CHECK.md')" "1"

# 2. AN EMPTY FILE IS NOT AN ANSWER EITHER. A file that exists and holds nothing
#    reads exactly like one holding a pass, unless something says otherwise.
EMPTY="$WORK/empty.tsv"
printf '# a header and no records\n' > "$EMPTY"
check "a record file holding nothing is CANNOT MEASURE" "$(status_with "$EMPTY")" "2"
check "and it says the file is there and empty" \
    "$(check_with "$EMPTY" | grep -ci 'holds no record')" "1"

# 3. THE ANSWER THAT MATTERS.
SURVIVED="$WORK/survived.tsv"
check "recording a survived check succeeds" "$(record_status "$SURVIVED" survived)" "0"
check "and the check then passes" "$(status_with "$SURVIVED")" "0"
check "and it says WHEN, because a stored verification that carries no date is one nobody can age" \
    "$(check_with "$SURVIVED" | grep -c "$(date '+%Y-%m-%d')")" "1"

# 4. AND THE ONE THAT IS A FINDING.
LAPSED="$WORK/lapsed.tsv"
check "recording a lapsed check succeeds too" "$(record_status "$LAPSED" lapsed)" "0"
check "and the check then REFUSES, because backups would stop silently" \
    "$(status_with "$LAPSED")" "1"
check "and it says what it means rather than only what happened" \
    "$(check_with "$LAPSED" | grep -ci 'stop silently')" "1"

# 5. THE NEWEST RECORD WINS, so a grant that lapsed and was fixed reads as fixed.
BOTH="$WORK/both.tsv"
record_with "$BOTH" lapsed >/dev/null 2>&1
record_with "$BOTH" survived >/dev/null 2>&1
check "the newest record is the one that counts" "$(status_with "$BOTH")" "0"

# 6. A VERDICT NOTHING CAN READ IS NOT A PASS (L98, L257). A file edited by hand,
#    or written by a later version, must not fall through to the good answer.
STRANGE="$WORK/strange.tsv"
printf '# header\n2026-09-12\tprobably-fine\tby hand\n' > "$STRANGE"
check "a verdict this does not know is CANNOT MEASURE" "$(status_with "$STRANGE")" "2"
check "and it quotes the verdict it could not read" \
    "$(check_with "$STRANGE" | grep -c 'probably-fine')" "1"

# 7. THE RECORDER REFUSES ANYTHING ELSE, rather than writing a verdict the reader
#    will not understand.
check "the recorder refuses a verdict it does not offer" \
    "$(record_status "$WORK/refused.tsv" maybe)" "2"
check "and refuses no verdict at all" "$(record_status "$WORK/refused.tsv")" "2"
check "and wrote nothing when it refused" \
    "$([ -f "$WORK/refused.tsv" ] && echo wrote || echo nothing)" "nothing"

# 8. IT RECORDS NO PATH. This repository is public on purpose, and where Dan's
#    records are copied to is his business (the standing output privacy rule).
PRIVACY="$WORK/privacy.tsv"
record_with "$PRIVACY" survived >/dev/null 2>&1
check "the record carries a date and a verdict and no folder" \
    "$(grep -v '^#' "$PRIVACY" | grep -c '/')" "0"

harness_end
