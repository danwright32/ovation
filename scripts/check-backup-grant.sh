#!/bin/bash
# ovation#232. HAS ANYBODY EVER PROVED THE BACKUP FOLDER GRANT SURVIVES A
# RELAUNCH, and when.
#
# ovation#87 asks for this to be proved by relaunching rather than by reading
# the code (L3). One CORRECTION to how it framed it, measured on 2026-09-11 with
# a standalone program: the issue says the choice is kept "as a security scoped
# bookmark so the grant survives a relaunch", and Ovation is not sandboxed. Such
# a bookmark does still resolve outside the sandbox and
# startAccessingSecurityScopedResource returns true, so the mechanism works. It
# is NOT what grants access. Outside the sandbox the grant is given by the system
# to the CODE IDENTITY, which is why ovation#9 made the signing identity stable,
# and the bookmark's real job is remembering WHERE the folder is when it moves.
#
# So the thing worth proving is not a bookmark round trip. It is that a REAL
# installed build, relaunched, still writes into the folder Dan chose. Only Dan
# can do that: he installs the apps himself (his standing instruction,
# 2026-08-28), and no test here can relaunch a signed build.
#
# WHY A RECORDED ANSWER AT ALL. Without one, "he checked and it survived" and
# "nobody has ever run it" are the same state to every later session, and the
# hand-off rule says to check whether a manual step is already done rather than
# asking him to redo it (L557, CLAUDE.md).
#
# IT REPORTS, IT DOES NOT REFUSE. Exit 2 is CANNOT MEASURE, which the
# preconditions entry point names rather than treats as a pass, so an unanswered
# question is visible on every run without blocking anything. A guard that
# refused until a person did something would be one people learn to skip (L378).
#
#   0  a check is recorded, and it is recent enough to mean something
#   1  a check is recorded and says the grant did NOT survive
#   2  nothing has ever been recorded, or the record cannot be read
#
# The record is docs/backup-grant-checks.tsv, appended to by
# scripts/record-backup-grant-check.sh. It prints dates and verdicts only: there
# is no identity in it, and the folder path is deliberately NOT recorded, since
# Dan's backup folder name is his business and this file is in a PUBLIC repo.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECORD="${OVATION_GRANT_RECORD:-${REPO_ROOT}/docs/backup-grant-checks.tsv}"

if [ ! -f "${RECORD}" ]; then
    echo "CANNOT MEASURE: no backup folder grant check has ever been recorded."
    echo "    Nobody has confirmed that a relaunched build still writes into the"
    echo "    folder Dan chose, and an unanswered question is not a passing one."
    echo "    The steps are in docs/BACKUP-GRANT-CHECK.md, and they end with the"
    echo "    one command that writes the record this reads."
    exit 2
fi

# The newest record wins. Lines are: date<TAB>verdict<TAB>note.
LAST="$(grep -v '^#' "${RECORD}" | grep -v '^[[:space:]]*$' | tail -1)"
if [ -z "${LAST}" ]; then
    echo "CANNOT MEASURE: ${RECORD} exists and holds no record."
    echo "    An empty file is not an answer, and it must not read as one (L98)."
    exit 2
fi

WHEN="$(printf '%s' "${LAST}" | cut -f1)"
VERDICT="$(printf '%s' "${LAST}" | cut -f2)"

case "${VERDICT}" in
    survived)
        echo "OK: the backup folder grant was last confirmed on ${WHEN}."
        echo "    A relaunched build still wrote into the folder Dan chose."
        exit 0
        ;;
    lapsed)
        echo "BLOCKED: the backup folder grant did NOT survive, checked ${WHEN}."
        echo "    A relaunched build could not write into the folder Dan chose, so"
        echo "    backups stop silently until it is chosen again. This is the"
        echo "    failure ovation#9's stable signing identity exists to prevent."
        exit 1
        ;;
    *)
        echo "CANNOT MEASURE: the newest record carries a verdict this does not know:"
        echo "    '${VERDICT}', recorded ${WHEN}."
        echo "    A verdict nothing can read is not a pass (L98)."
        exit 2
        ;;
esac
