#!/bin/bash
# Say when a pull request conflicts with main, because nothing else will.
#
# ovation#350. GitHub schedules no `pull_request` workflow run for a pull request
# whose merge commit it cannot compute, so a CONFLICTING one shows "no checks
# reported" rather than a conflict. Measured 2026-09-15: two pull requests sat over
# half an hour with no run of any kind while a third opened minutes later ran
# normally, and about forty minutes went into Actions incidents, credentials and
# trigger filters before `mergeable` was read (L476). Every branch that adds a suite
# or a test conflicts on a committed count (ovation#346), so this recurs.
#
# RUN BY .github/workflows/pr-mergeable.yml on `pull_request_target`, which GitHub
# DOES schedule for a conflicting pull request because it runs the base branch's
# workflow, and on every push to main, because main moving is what makes an open
# pull request start to conflict. It never checks out a pull request's code.
#
#     scripts/check-pr-mergeable.sh [--comment] [<number>...]
#
# With no number it asks about every open pull request. With --comment it posts
# ONE comment on a conflicting pull request, found again by a marker rather than
# by its wording, so a rerun never piles up copies (L393).
#
# UNKNOWN IS NOT MERGEABLE. GitHub answers UNKNOWN while it computes the merge, so
# the answer is asked again a few times, through an injectable sleep (L524); one
# that never settles is "could not tell", never a pass (L98).
#
# Exit codes: 0 none conflicts, 1 at least one conflicts, 2 at least one could not
# be read or never settled (and none conflicts).
set -uo pipefail

GH="${OVATION_GH:-gh}"
SLEEP="${OVATION_SLEEP:-sleep}"
REPO="${OVATION_REPO:-${GITHUB_REPOSITORY:-danwright32/ovation}}"
TRIES="${OVATION_MERGEABLE_TRIES:-6}"
MARKER="<!-- ovation-pr-mergeable -->"

COMMENT=""
if [ "${1:-}" = "--comment" ]; then COMMENT=1; shift; fi

NUMBERS="$*"
if [ -z "${NUMBERS}" ]; then
    if ! NUMBERS="$("${GH}" pr list --repo "${REPO}" --state open --json number --jq '.[].number' 2>&1)"; then
        echo "CANNOT MEASURE: the open pull requests could not be listed: ${NUMBERS}"
        exit 2
    fi
    if [ -z "${NUMBERS}" ]; then
        echo "OK: there are no open pull requests, so none can conflict."
        exit 0
    fi
fi

conflicts=0
unmeasured=0
for n in ${NUMBERS}; do
    state=""
    try=1
    while [ "${try}" -le "${TRIES}" ]; do
        if ! state="$("${GH}" pr view "${n}" --repo "${REPO}" --json mergeable --jq .mergeable 2>&1)"; then
            echo "  CANNOT MEASURE  #${n}: ${state}"
            state="unreadable"
            break
        fi
        [ "${state}" = "UNKNOWN" ] || break
        [ "${try}" -lt "${TRIES}" ] && "${SLEEP}" 10
        try=$((try + 1))
    done
    case "${state}" in
        MERGEABLE)
            echo "  OK              #${n} merges cleanly with main"
            ;;
        CONFLICTING)
            echo "  CONFLICTING     #${n}: GitHub runs no checks on it until main is merged in, so"
            echo "                  \"no checks reported\" here means a conflict, not CI failing to start."
            echo "                  Remedy: merge main into the branch, resolve, and push."
            conflicts=$((conflicts + 1))
            if [ -n "${COMMENT}" ]; then
                already="$("${GH}" api "repos/${REPO}/issues/${n}/comments" --jq '.[].body' 2>/dev/null || true)"
                if grep -qF -- "${MARKER}" <<< "${already}"; then
                    echo "                  (already said on the pull request, so not said again)"
                else
                    body="$(mktemp)"
                    {
                        echo "${MARKER}"
                        echo "This pull request **conflicts with main**, so GitHub will not run any checks on it, and \"no checks reported\" means that rather than CI failing to start (ovation#350)."
                        echo ""
                        echo "Remedy: merge main into the branch, resolve the conflict, and push. The checks start on that push."
                    } > "${body}"
                    "${GH}" pr comment "${n}" --repo "${REPO}" --body-file "${body}" >/dev/null \
                        || echo "                  (the comment could not be posted)"
                    rm -f "${body}"
                fi
            fi
            ;;
        unreadable)
            unmeasured=$((unmeasured + 1))
            ;;
        *)
            echo "  CANNOT MEASURE  #${n}: GitHub still answered '${state}' after ${TRIES} asks, so whether it conflicts could not tell."
            unmeasured=$((unmeasured + 1))
            ;;
    esac
done

if [ "${conflicts}" -gt 0 ]; then
    echo "REFUSED: ${conflicts} pull request(s) conflict with main."
    exit 1
fi
if [ "${unmeasured}" -gt 0 ]; then
    echo "CANNOT MEASURE: ${unmeasured} pull request(s) could not tell, which is not the same as merging cleanly."
    exit 2
fi
echo "OK: every pull request asked about merges cleanly with main."
exit 0
