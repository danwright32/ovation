#!/bin/bash
# The CI workflow carries decisions, and a workflow file is the kind of thing
# nothing else in a repository ever reads.
#
# ovation#143. scripts/build-products.sh was written for CI, on Dan's decision of
# 2026-09-06 that CI BUILDS BOTH configurations, because skipping the build
# dependent suites there would leave the shipping build's bundle assertions
# running on exactly one machine, and those are the assertions that caught a real
# security defect in ovation#9. Then no CI existed: .github/workflows/ was
# absent, `gh run list` returned nothing, and no workflow had ever run.
#
# THREE THINGS, EACH BECAUSE IT FAILS SILENTLY:
#
#   a timeout on every job   GitHub's default is six hours. A hung job is worse
#                            than a failed one because it cannot be told from a
#                            slow one, and it holds a runner slot for all of it
#                            (L110, L313).
#   every action pinned      `@v4` is a moving tag, which is somebody else's code
#                            running here tomorrow, chosen by them (L25).
#   the documented command   the decision above is a sentence in a header until
#                            something reads it (L407).
#
# It prints paths, job names and counts. There is nothing here to redact.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${OVATION_WORKFLOW_DIR:-$REPO_ROOT/.github/workflows}"
# The command Dan decided on, kept as one string so the message can quote the
# thing it is asking for rather than describing it (L399).
WANTED="bash scripts/build-products.sh && bash scripts/run-tests.sh"

if [ ! -d "$DIR" ]; then
  echo "REFUSED: there is no workflow directory at $DIR."
  echo "    This repository decided to have CI (ovation#143), so its absence is a"
  echo "    fault rather than a question nothing here can answer."
  exit 1
fi

FILES=""
for f in "$DIR"/*.yml "$DIR"/*.yaml; do
  [ -f "$f" ] || continue
  FILES="${FILES}${f}
"
done
FILE_COUNT="$(printf '%s' "$FILES" | grep -c . || true)"

if [ "$FILE_COUNT" -eq 0 ]; then
  echo "REFUSED: $DIR holds no workflow file."
  echo "    A directory that exists and is empty is not CI, and a check that"
  echo "    passed over zero files would be indistinguishable from one that"
  echo "    examined a healthy workflow."
  exit 1
fi

problems=0
job_count=0
saw_wanted_command=0

while IFS= read -r file; do
  [ -n "$file" ] || continue

  # Jobs are the two space keys under `jobs:`. Nothing here parses YAML properly,
  # and it does not need to: the shapes it asks about are line shaped, and a
  # dependency on a YAML parser would be a tool this repository does not have on
  # every machine that has to run this.
  in_jobs=0
  current_job=""
  job_has_timeout=0
  while IFS= read -r line; do
    case "$line" in
      "jobs:"*) in_jobs=1; continue ;;
    esac
    [ "$in_jobs" -eq 1 ] || continue

    # A two space indented key that is not deeper: a job name.
    if printf '%s' "$line" | grep -qE '^  [A-Za-z0-9_-]+:[[:space:]]*$'; then
      if [ -n "$current_job" ] && [ "$job_has_timeout" -eq 0 ]; then
        echo "NO TIMEOUT: $current_job in $(basename "$file")"
        problems=$((problems+1))
      fi
      current_job="$(printf '%s' "$line" | tr -d ' :')"
      job_count=$((job_count+1))
      job_has_timeout=0
      continue
    fi
    case "$line" in
      *timeout-minutes:*) job_has_timeout=1 ;;
    esac
  done < "$file"
  if [ -n "$current_job" ] && [ "$job_has_timeout" -eq 0 ]; then
    echo "NO TIMEOUT: $current_job in $(basename "$file")"
    problems=$((problems+1))
  fi

  # Every `uses:` must name a 40 character commit, not a tag or a branch.
  while IFS= read -r used; do
    [ -n "$used" ] || continue
    case "$used" in
      *@*) ;;
      *) echo "UNPINNED: $used in $(basename "$file") names no version at all"
         problems=$((problems+1)); continue ;;
    esac
    ref="${used##*@}"
    if ! printf '%s' "$ref" | grep -qE '^[0-9a-f]{40}$'; then
      echo "UNPINNED: $used in $(basename "$file")"
      echo "    a tag or branch is somebody else's choice of what runs here"
      echo "    tomorrow. Pin the commit: gh api repos/<owner>/<repo>/git/ref/tags/<tag>"
      problems=$((problems+1))
    fi
  done < <(grep -oE 'uses:[[:space:]]*[^[:space:]]+' "$file" | sed 's/uses:[[:space:]]*//')

  if grep -qF "$WANTED" "$file"; then
    saw_wanted_command=1
  fi
done <<< "$FILES"

if [ "$saw_wanted_command" -eq 0 ]; then
  echo "MISSING THE DOCUMENTED COMMAND: no workflow runs"
  echo "    $WANTED"
  echo "    Dan decided on 2026-09-06 that CI builds BOTH configurations, because"
  echo "    the alternative leaves the shipping build's bundle assertions running"
  echo "    on one machine. A workflow that only runs the suite has quietly taken"
  echo "    the option that decision rejected, and it goes green while doing it."
  problems=$((problems+1))
fi

echo "examined $FILE_COUNT workflow file(s) and $job_count job(s) under $DIR"
[ "$problems" -eq 0 ] || exit 1
exit 0
