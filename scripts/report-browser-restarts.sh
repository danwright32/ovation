#!/bin/bash
# Put a browser restart CI recorded onto the tracker, where it cannot expire.
#
# ovation#332 made a browser that stops answering restart once and write a line
# saying so, because a fault that heals silently cannot be counted, and CI keeps
# that line as an artifact because a CI log expires (scanning every unsuccessful
# run on 2026-09-15 found ONE occurrence and 32 runs whose logs could no longer
# be read at all). This reads the artifact of the run that just finished and adds
# one comment per occurrence to the issue that carries the count.
#
# ovation#352 MOVED THIS OUT OF THE WORKFLOW. It lived in a step of
# .github/workflows/browser-restarts.yml, which is a `workflow_run` workflow and
# therefore only ever runs from the default branch: it could not run on the pull
# request that added it, and its first real execution would have been on main,
# months later, after a browser had actually stopped answering. That is the half
# that decides whether a finding is seen, and every way it breaks loses the
# report quietly, so it belongs where a suite can drive it (L3, and ovation#339
# for report-finding.sh, which is the same move).
#
# FOUR OUTCOMES, KEPT APART (L11, L98):
#
#   nothing to count   no run was named, or the run kept no record. Exit 0, said.
#   reported           the record held lines and every one reached the issue.
#                      Exit 0, said, and it says how many.
#   could not measure  the lookup, the download or the record itself could not be
#                      read. Exit 1, naming which. Never reported as a run that
#                      recorded nothing: that would be a quiet all clear about a
#                      run nobody read.
#   reached nobody     the occurrence was measured and no open issue carries the
#                      title, so nobody was told. The reporter's own code is
#                      carried out rather than flattened (L184).
#
# IT NEVER OPENS AN ISSUE. Dan decided on 2026-09-15 that an automated write must
# not open an issue on this public tracker by itself, so the issue carrying the
# count is opened by hand and this only ever comments, through report-finding.sh.
#
# SEAMS, so the suite drives every path without a runner and without the tracker
# (L2, L291):
#
#   OVATION_GH                  what talks to GitHub, default `gh`.
#   OVATION_REPORT_FINDING      what reports, default scripts/report-finding.sh.
#   OVATION_RESTART_RECORD_DIR  where the artifact is unpacked, default `record`.
#   OVATION_RESTART_RUN_ID      the run to read, and OVATION_RESTART_RUN_URL the
#                               page a person opens. The workflow passes both from
#                               the event that triggered it.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GH="${OVATION_GH:-gh}"
REPORTER="${OVATION_REPORT_FINDING:-${REPO_ROOT}/scripts/report-finding.sh}"
RECORD_DIR="${OVATION_RESTART_RECORD_DIR:-record}"
RUN_ID="${OVATION_RESTART_RUN_ID:-}"
RUN_URL="${OVATION_RESTART_RUN_URL:-}"
REPOSITORY="${GITHUB_REPOSITORY:-}"

# The name CI keeps the record under, and the file inside it. Written once here;
# scripts/test-design-render.sh holds the workflow's upload step to the same name,
# because nothing in YAML can derive one from the other (L41, L58).
ARTIFACT="browser-restarts"
RECORD_FILE="browser-restarts.tsv"

# The issue that carries the count. Opened by hand, matched exactly by the
# reporter, and named here rather than in the workflow so the suite asserts the
# title that will actually be used.
TITLE="A headless browser stopped answering during CI and was restarted"

if [ -z "${RUN_ID}" ]; then
    echo "No run was named, so there is nothing to count. This is what a run"
    echo "started by hand does: the trigger carries the run to read."
    exit 0
fi

if ! names="$("${GH}" api "repos/${REPOSITORY}/actions/runs/${RUN_ID}/artifacts" \
                --jq '[.artifacts[].name] | join(" ")')"; then
    echo "The artifacts of run ${RUN_ID} could not be read, so whether it recorded" >&2
    echo "a browser restart is unknown. Nothing is reported from a lookup that" >&2
    echo "failed: an all clear here would be about a run nobody read." >&2
    exit 1
fi

case " ${names} " in
    *" ${ARTIFACT} "*) ;;
    *)
        echo "Run ${RUN_ID} kept no ${ARTIFACT} record, so no browser stopped answering"
        echo "in it. That is the ordinary state of almost every run."
        exit 0
        ;;
esac

if ! "${GH}" run download "${RUN_ID}" --repo "${REPOSITORY}" \
       --name "${ARTIFACT}" --dir "${RECORD_DIR}"; then
    echo "Run ${RUN_ID} lists a ${ARTIFACT} record that could not be downloaded, so" >&2
    echo "what it held is unknown. That is a different thing from the run keeping" >&2
    echo "none, and it is not reported as one." >&2
    exit 1
fi

if [ ! -f "${RECORD_DIR}/${RECORD_FILE}" ]; then
    echo "The ${ARTIFACT} artifact of run ${RUN_ID} holds no ${RECORD_FILE}, so" >&2
    echo "something other than the renderer wrote it." >&2
    exit 1
fi

# COUNTED FROM THE RECORD, never assumed to be one: a run can restart more than
# one browser, and a count that cannot say two is not a count (L467).
lines="$(grep -c . "${RECORD_DIR}/${RECORD_FILE}")" || lines=0
if [ "${lines}" -eq 0 ]; then
    echo "The ${ARTIFACT} record of run ${RUN_ID} is empty, and the renderer only" >&2
    echo "creates it by writing a line to it, so an empty one means something else" >&2
    echo "made the file." >&2
    exit 1
fi

BODY="$(mktemp)"
trap 'rm -f "${BODY}"' EXIT
{
    echo "${lines} restart(s) on $(date -u +%Y-%m-%d), in ${RUN_URL:-a run with no URL recorded}:"
    echo
    sed 's/^/    /' "${RECORD_DIR}/${RECORD_FILE}"
    echo
    echo "Each line is one restart. Its columns are when it happened, the request"
    echo "that went unanswered, the page, why the browser went, and the process"
    echo "that recorded it (ovation#366: several lines carrying one process number"
    echo "are one browser failing repeatedly, not several browsers failing once)."
} > "${BODY}"

"${REPORTER}" recurred --title "${TITLE}" --comment-file "${BODY}"
reported=$?

# 1 IS THE ONLY SUCCESS, and that is the reporter's own contract: it exits 1 when
# it added the comment to the issue that carries the count. 8 means nothing open
# carries the title, which fails on purpose: the restart was measured and nobody
# was told. Every other code is carried out rather than flattened onto one, so a
# reader can tell a refusal from a broken reporter (L184, L11).
case "${reported}" in
    1)
        echo "${lines} restart(s) from run ${RUN_ID} reported on the issue that counts them."
        exit 0
        ;;
    8)
        echo "No open issue carries \"${TITLE}\", so this occurrence reached nobody." >&2
        echo "Open that issue, then run this again: a restart measured and reported" >&2
        echo "to nobody is the loss the whole record exists to prevent." >&2
        exit 8
        ;;
    0)
        echo "The reporter exited 0, which is not one of its outcomes, so whether the" >&2
        echo "occurrence was added to the issue is unknown. It is not counted as one." >&2
        exit 1
        ;;
    *)
        echo "The reporter refused with ${reported} (its own message is above), so this" >&2
        echo "occurrence was not added to the issue." >&2
        exit "${reported}"
        ;;
esac
