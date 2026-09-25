# Where a run may write a durable record, or that it may write none. ovation#368.
#
# THE RULE: a run whose SUBJECT was injected (a stand in browser, an injected
# test command) writes nothing to a durable record, whoever named one, unless the
# caller declares that the staging IS what it measures. Every other run writes to
# the record it names, or to the default.
#
# WHY ONE RULE, WRITTEN ONCE. Two records carried their own copy of this guard
# and the copies disagreed. scripts/lib/design_render.py refused a staged fault
# only beneath "no record was named", and CI names a record for its whole Linux
# job, so every line of every recent run was a fault this repository's own suites
# staged, and ovation#353 counted seven runs of them as real (ovation#366). It
# was fixed there, and scripts/run-tests.sh went on taking a named lock wait
# record whatever else was true: the same defect, one file over (L2, L93). A
# record a suite can write into is worse than no record, because it reads as
# measurement. scripts/check-durable-records.sh refuses a writer that does not
# ask this, so a third record cannot bring a third version (L27, L613).
#
# WHAT IS STAGED IS THE CALLER'S TO SAY, because only the caller knows what its
# subject is: a browser for the restart record, the test commands for the lock
# wait record. What is done about it is this file's.
#
# THE DECLARATION IS NAMED PER RECORD, never one variable for all of them. A
# declaration is an environment variable, inherited by every process the declarer
# starts (L169, L439), so one shared name set by the suite measuring one record
# would open every other record to whatever that suite runs beneath it.
#
# A CALLER THAT CANNOT SAY is refused, exit 2, rather than answered: a subject
# that is neither real nor staged, a declaration that is not a variable name, or
# no default. Each of those would otherwise fall into "write" or "write nothing"
# by accident, and both read as the rule working.
#
# SOURCED by scripts/run-tests.sh, and EXECUTED by scripts/lib/design_render.py,
# which is Python and asks it as a command, so the two records are judged by one
# body of code rather than a Python copy of it (L370):
#
#   durable_record_path <real|staged> <DECLARATION_VARIABLE> <named path> <default path>
#   bash scripts/lib/durable-record.sh <real|staged> <DECLARATION_VARIABLE> <named> <default>
#
# It PRINTS the path to write to, or nothing when the run writes nothing, and
# exits 0 for both.

durable_record_path() {
  local subject="${1:-}" declared_by="${2:-}" named="${3:-}" default="${4:-}" declared
  case "${subject}" in
    real|staged) ;;
    *)
      echo "REFUSED: durable_record_path was told the subject is '${subject}', and it must be real or staged." >&2
      return 2
      ;;
  esac
  if ! [[ "${declared_by}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "REFUSED: durable_record_path was given '${declared_by}' as the declaration, which is not a variable name." >&2
    return 2
  fi
  if [ -z "${default}" ]; then
    echo "REFUSED: durable_record_path was given no default record." >&2
    return 2
  fi
  if [ "${subject}" = "staged" ]; then
    # Spaces are not a declaration: the renderer always read its declaration
    # stripped, and one rule must answer the way both of its callers did.
    declared="${!declared_by:-}"
    declared="${declared//[[:space:]]/}"
    [ -n "${declared}" ] || return 0
  fi
  if [ -n "${named}" ]; then
    printf '%s\n' "${named}"
  else
    printf '%s\n' "${default}"
  fi
}

# Run as a command rather than sourced: answer once and exit with the answer.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  durable_record_path "$@"
  exit $?
fi
