#!/bin/bash
# Is every scheduled workflow still RUNNING? ovation#387.
#
# A scheduled run that FAILS is loud. A schedule that STOPPED is silent: GitHub
# disables every schedule in a repository that has seen no activity for 60 days,
# and it fails nothing when it does. The runner Xcode watcher, the design record
# check and the CI liveness check exist to speak on the days nobody is looking,
# which are exactly the days a schedule would have been switched off, so each one's
# silence read the same as "nothing to report" (L13, L98).
#
# JUDGED ON WHETHER IT RAN, NEVER ON WHETHER IT PASSED. A watchdog judged on its
# last SUCCESSFUL run can never clear its own correct alarm, and one that derives
# its set from the workflow files includes itself (L71); a failing run is already
# loud on its own, so the question here is only whether runs are still happening.
#
# RUN FROM OUTSIDE GITHUB AS WELL AS INSIDE IT. If GitHub disables schedules for
# inactivity it disables whatever would have run this too, so the post-merge step
# in CLAUDE.md runs it from the session that just merged, which GitHub cannot
# switch off. The CI liveness workflow runs it daily for the case one schedule
# stops on its own.
#
# Only a DAILY schedule (`M H * * *`) is read; anything else is refused by name
# rather than turned into a guessed period (L11).
#
# A SCHEDULE TOO NEW TO HAVE RUN IS NOT YET DUE, NOT STOPPED (ovation#661). On
# 2026-09-29 backstage-release.yml and flaky-jobs.yml were added, and CI liveness
# went red at least 15 times before either had its first scheduled run: "no run
# on record at all" was true and meant nothing yet. An alarm red for a known
# harmless reason is the one ignored on the day a schedule really stops (L36). So
# a workflow with no scheduled run whose file GitHub first saw less than one
# period plus GRACE_SECONDS ago is reported NOT YET DUE, and does not fail.
#
# KEYED ON THE WORKFLOW'S created_at FROM GITHUB'S API, not on the git history.
# Measured 2026-10-08: backstage-release.yml's created_at is 19:44:24 UTC on
# 09-29 and #623 merged at 19:44:22, flaky-jobs.yml's is 22:57:35 and #628 merged
# at 22:57:34, so it is the moment the file reached main, which is when its
# schedule starts. It needs no history in the checkout, so CI's shallow clone and
# the post-merge run from a session both read the same thing.
#
# THE SAME GRACE AS A LATE RUN. GitHub's measured schedule delay was 6h18m and
# 6h35m on those two workflows' first days (crons 06:41 and 08:37, runs at 12:59
# and 15:12 UTC), inside the 12 hours already allowed a schedule that has run
# before, so a new one is given that same allowance rather than a second notion
# of late.
#
# A DATE IT CANNOT READ IS NO EVIDENCE THE SCHEDULE IS NEW, so a workflow with no
# run whose created_at cannot be read is STOPPED as before, and says why (L42).
#
# Exit codes: 0 every schedule ran within its period or is not yet due, 1 at
# least one stopped or is disabled, 2 nothing could be judged (no schedules, a
# cron it cannot read, or gh could not answer).
set -uo pipefail

GH="${OVATION_GH:-gh}"
REPO="${OVATION_REPO:-${GITHUB_REPOSITORY:-danwright32/ovation}}"
NOW="${OVATION_NOW:-$(date +%s)}"
WF_DIR="${OVATION_WORKFLOW_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.github/workflows}"
# A day, plus half a day for GitHub's own scheduling delay, which is routinely
# tens of minutes and on a busy day hours.
GRACE_SECONDS=$((12 * 3600))

# EITHER SHAPE GITHUB USES: a run's createdAt is 2026-09-29T19:44:25Z, and a
# workflow's created_at is 2026-09-29T15:44:24.000-04:00. A time with no zone is
# refused rather than read as local, which would move it by hours.
to_epoch() {
    python3 -c 'import sys,datetime
try:
    t = datetime.datetime.fromisoformat(sys.argv[1].strip().replace("Z", "+00:00"))
    print(int(t.timestamp()) if t.tzinfo is not None else "")
except Exception:
    print("")' "$1"
}

judged=0
stopped=0
not_yet_due=0
unreadable=0
for f in "$WF_DIR"/*.yml; do
    [ -f "$f" ] || continue
    cron="$(grep -E "^[[:space:]]*-[[:space:]]*cron:" "$f" | head -1 | sed -E "s/.*cron:[[:space:]]*['\"]?([^'\"]*)['\"]?.*/\1/")"
    [ -n "$cron" ] || continue
    name="$(basename "$f")"
    if ! grep -qE '^[0-9]{1,2} [0-9]{1,2} \* \* \*$' <<< "$cron"; then
        echo "  CANNOT MEASURE  $name: its schedule '$cron' is not a daily one this reads, so no period was guessed."
        unreadable=$((unreadable + 1))
        continue
    fi
    judged=$((judged + 1))
    period=86400
    # A FAILED READ OF ITS STATE IS NOT "active" either, or a schedule GitHub
    # disabled passes during an outage or with an expired token (L215).
    if ! state="$("$GH" api "repos/${REPO}/actions/workflows/${name}" --jq .state 2>/dev/null)"; then
        echo "  CANNOT MEASURE  $name: gh could not answer for its state, so whether GitHub disabled it is unknown."
        unreadable=$((unreadable + 1))
        continue
    fi
    if [ -n "$state" ] && [ "$state" != "active" ]; then
        echo "  STOPPED         $name: GitHub reports it as $state, so its schedule no longer runs."
        echo "                  Re-enable it: gh workflow enable $name"
        stopped=$((stopped + 1))
        continue
    fi
    # GH COULD NOT ANSWER IS NOT AN EMPTY ANSWER (L215). Read as empty, a failed
    # run list made a schedule added in the last day and a half NOT YET DUE, so
    # an outage or an expired token passed as healthy; it is CANNOT MEASURE.
    if ! last="$("$GH" run list --repo "$REPO" --workflow "$name" --event schedule --limit 1 --json createdAt --jq '.[0].createdAt' 2>/dev/null)"; then
        echo "  CANNOT MEASURE  $name: gh could not answer for its scheduled runs, so nothing was judged."
        unreadable=$((unreadable + 1))
        continue
    fi
    last_epoch="$(to_epoch "${last:-}")"
    if [ -z "$last_epoch" ]; then
        if ! created="$("$GH" api "repos/${REPO}/actions/workflows/${name}" --jq .created_at 2>/dev/null)"; then
            echo "  CANNOT MEASURE  $name: no scheduled run is on record, and gh could not answer for"
            echo "                  when it was added, so it was not judged new or stopped."
            unreadable=$((unreadable + 1))
            continue
        fi
        created_epoch="$(to_epoch "${created:-}")"
        if [ -z "$created_epoch" ]; then
            echo "  STOPPED         $name: no scheduled run of it is on record at all, and when it was"
            echo "                  added could not be read, so it is not assumed to be new."
            stopped=$((stopped + 1))
            continue
        fi
        added_age=$((NOW - created_epoch))
        if [ "$added_age" -le $((period + GRACE_SECONDS)) ]; then
            echo "  NOT YET DUE     $name: added $((added_age / 3600)) hours ago and has not had its first"
            echo "                  scheduled run yet; it is due within $(((period + GRACE_SECONDS) / 3600)) hours of being added."
            not_yet_due=$((not_yet_due + 1))
            continue
        fi
        echo "  STOPPED         $name: no scheduled run of it is on record at all, and it was added"
        echo "                  $((added_age / 3600)) hours ago, on a daily schedule."
        stopped=$((stopped + 1))
        continue
    fi
    age=$((NOW - last_epoch))
    if [ "$age" -gt $((period + GRACE_SECONDS)) ]; then
        echo "  STOPPED         $name: its newest scheduled run was $((age / 3600)) hours ago, on a daily schedule."
        stopped=$((stopped + 1))
    else
        echo "  OK              $name: ran $((age / 3600)) hours ago."
    fi
done

if [ "$stopped" -gt 0 ]; then
    echo "REFUSED: ${stopped} of ${judged} scheduled workflow(s) have stopped running."
    exit 1
fi
if [ "$unreadable" -gt 0 ] || [ "$judged" -eq 0 ]; then
    echo "CANNOT MEASURE: ${judged} scheduled workflow(s) judged, ${unreadable} could not be read or answered for."
    exit 2
fi
if [ "$not_yet_due" -gt 0 ]; then
    echo "OK: $((judged - not_yet_due)) of ${judged} scheduled workflow(s) ran within their period, and ${not_yet_due} not yet due for a first run."
    exit 0
fi
echo "OK: all ${judged} scheduled workflow(s) ran within their period."
exit 0
