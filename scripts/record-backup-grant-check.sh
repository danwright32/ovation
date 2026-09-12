#!/bin/bash
# ovation#232. Write down what a relaunch actually showed.
#
# Run by Dan, from the steps in docs/BACKUP-GRANT-CHECK.md, and by nothing
# automatic: the whole point is that a person relaunched a real installed build
# and looked.
#
#   bash scripts/record-backup-grant-check.sh survived
#   bash scripts/record-backup-grant-check.sh lapsed
#
# IT RECORDS NO PATH. Dan's backup folder name is his business and this
# repository is public on purpose, so the record carries a date, a verdict and
# nothing else that could identify where his records are copied to.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECORD="${OVATION_GRANT_RECORD:-${REPO_ROOT}/docs/backup-grant-checks.tsv}"

VERDICT="${1:-}"
case "${VERDICT}" in
    survived|lapsed) ;;
    *)
        echo "Usage: bash scripts/record-backup-grant-check.sh survived|lapsed" >&2
        echo "  survived  a relaunched build still wrote into the chosen folder" >&2
        echo "  lapsed    it could not, so the grant did not survive" >&2
        exit 2
        ;;
esac

if [ ! -f "${RECORD}" ]; then
    {
        echo "# ovation#232. Whether a RELAUNCHED, installed build still writes into"
        echo "# the backup folder Dan chose. Appended to by"
        echo "# scripts/record-backup-grant-check.sh and read by"
        echo "# scripts/check-backup-grant.sh."
        echo "#"
        echo "# A date, a verdict, and nothing else. No path: this repository is"
        echo "# public and where Dan's records are copied to is his business."
        echo "#"
        echo "# date	verdict	note"
    } > "${RECORD}"
fi

printf '%s\t%s\t%s\n' "$(date '+%Y-%m-%d')" "${VERDICT}" "${2:-recorded by hand}" >> "${RECORD}"
echo "Recorded: ${VERDICT}, $(date '+%Y-%m-%d'), in ${RECORD}"
