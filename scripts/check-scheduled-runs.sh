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
# Exit codes: 0 every schedule ran within its period, 1 at least one stopped or is
# disabled, 2 nothing could be judged (no schedules, a cron it cannot read, or gh
# could not answer).
set -uo pipefail

GH="${OVATION_GH:-gh}"
REPO="${OVATION_REPO:-${GITHUB_REPOSITORY:-danwright32/ovation}}"
NOW="${OVATION_NOW:-$(date +%s)}"
WF_DIR="${OVATION_WORKFLOW_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.github/workflows}"
# A day, plus half a day for GitHub's own scheduling delay, which is routinely
# tens of minutes and on a busy day hours.
GRACE_SECONDS=$((12 * 3600))

to_epoch() {
    python3 -c 'import sys,datetime
try:
    print(int(datetime.datetime.strptime(sys.argv[1].strip(), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()))
except Exception:
    print("")' "$1"
}

judged=0
stopped=0
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
    state="$("$GH" api "repos/${REPO}/actions/workflows/${name}" --jq .state 2>/dev/null || true)"
    if [ -n "$state" ] && [ "$state" != "active" ]; then
        echo "  STOPPED         $name: GitHub reports it as $state, so its schedule no longer runs."
        echo "                  Re-enable it: gh workflow enable $name"
        stopped=$((stopped + 1))
        continue
    fi
    last="$("$GH" run list --repo "$REPO" --workflow "$name" --event schedule --limit 1 --json createdAt --jq '.[0].createdAt' 2>/dev/null || true)"
    last_epoch="$(to_epoch "${last:-}")"
    if [ -z "$last_epoch" ]; then
        echo "  STOPPED         $name: no scheduled run of it is on record at all."
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
    echo "CANNOT MEASURE: ${judged} scheduled workflow(s) judged, ${unreadable} schedule(s) unreadable."
    exit 2
fi
echo "OK: all ${judged} scheduled workflow(s) ran within their period."
exit 0
