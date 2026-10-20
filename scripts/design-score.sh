#!/bin/bash
# Scores a screen as built against its settled design (ovation#760).
#
#     bash scripts/design-score.sh <screen> [--design <settled file>] [--pr <number>]
#
# The design match score is claude-config's (claude-config#1364): a build is done
# when it matches its settled design at 100% on both halves, every decision's check
# met and every frame's pixels within 8 levels a channel. The design rounds skill
# ("Scoring the build against the settled design") is the full reference. This is
# Ovation's half of it, in order, stopping at the first failure:
#
#   1. the DESIGN side: the shared capture-web.mjs draws each frame of
#      docs/design/<screen>.html (or the file --design names) in the shared
#      Playwright's Chromium, and leaves the capture folder;
#   2. the BUILT side: the hosted suite OvationHostedTests/<Screen>DesignScoreTests
#      draws the real view for each frame from the committed fixture, through
#      run-tests.sh --only, so it takes the sibling locks every other hosted run
#      takes (raw xcodebuild would take neither, see CLAUDE.md). The capture folder,
#      the commit and whether anything is uncommitted reach the test as
#      TEST_RUNNER_DESIGN_SCORE_*, which xcodebuild hands on without the prefix;
#   3. the SCORE: design_score.py score, whose exit is this script's exit. 0 is
#      matched, 1 is not matched yet, 2 is no score.
#
# EVERY STOP BEFORE THE SCORE IS 2, never the failing step's own code. A snapshot
# that failed leaves the previous run's pictures in no folder this run made, but a
# runner that went on would score whatever the step left and report it as this
# run's (L98), and a step's exit of 1 would read as "not matched yet".
#
# --pr posts the score on that pull request (and on its design milestone's Match
# issue, which design_score.py finds), as every pull request in a design milestone
# must. A run with no score posts nothing: an unmeasured run is not a score. A post
# that reached nothing is said and exits 2, because a score nobody can see on the
# pull request is the absence the close gate reads. One that reached the pull
# request but found no Match issue is the score, and says so: on #764, the first
# real post, the runner called exactly that a failure.
#
# THE ADAPTER IS A COPY. vendor/design-score/DesignScoreCapture.swift is
# claude-config's file verbatim, because a test target cannot depend on ~/.claude
# (CI has none). A copy that has fallen behind draws the build side with code the
# score was not written against, so it is compared with the shared one first and a
# difference refuses, naming the cp that refreshes it.
#
# WHAT IT CANNOT DO YET, measured 2026-10-20 rather than assumed: text drawn by
# Chrome and the same text drawn by SwiftUI land in the same box and still differ
# at the glyph edges, 96.9% on one 13pt line while flat colour matched 100% in the
# same run. So a screen with words on it cannot reach 100% under the score's rule
# however exactly it is built; the proof screen is colour only for that reason.
# Recorded on ovation#760 and its pull request.
#
# The score's tools come from DESIGN_SCORE_TOOLS, by default the shared folder
# beside the design rounds skill. With no shared Playwright, capture-web.mjs exits
# 2 naming the one command that installs it.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="${DESIGN_SCORE_TOOLS:-${HOME}/.claude/skills/design-rounds/score}"
ADAPTER="${REPO_ROOT}/vendor/design-score/DesignScoreCapture.swift"
REPO_SLUG="danwright32/ovation"

usage() {
  echo "usage: bash scripts/design-score.sh <screen> [--design <settled file>] [--pr <number>]" >&2
  exit 2
}
no_score() { echo "design-score: $1" >&2; echo "design-score: NO SCORE" >&2; exit 2; }

SCREEN="${1:-}"
[ -n "${SCREEN}" ] && [ "${SCREEN#-}" = "${SCREEN}" ] || usage
shift
DESIGN="docs/design/${SCREEN}.html"
PR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --design) [ -n "${2:-}" ] || usage; DESIGN="$2"; shift 2 ;;
    --pr) [[ "${2:-}" =~ ^[0-9]+$ ]] || usage; PR="$2"; shift 2 ;;
    *) usage ;;
  esac
done
case "${DESIGN}" in /*) ;; *) DESIGN="${REPO_ROOT}/${DESIGN}" ;; esac
[ -f "${DESIGN}" ] || no_score "there is no settled design at ${DESIGN#"${REPO_ROOT}"/}; make it with the design rounds skill's make-settled.py"

# invoice-list -> InvoiceListDesignScoreTests
SUITE="$(awk -F- '{ for (i = 1; i <= NF; i++) printf "%s%s", toupper(substr($i, 1, 1)), substr($i, 2) }' <<< "${SCREEN}")DesignScoreTests"
grep -rqsE "struct ${SUITE}([^A-Za-z0-9_]|$)" "${REPO_ROOT}/OvationHostedTests" \
  || no_score "no snapshot suite draws ${SCREEN}: add ${SUITE} to OvationHostedTests/DesignScore, drawing each of its frames from the committed fixture"

for tool in capture-web.mjs design_score.py swiftui/DesignScoreTests/DesignScoreCapture.swift; do
  [ -f "${TOOLS}/${tool}" ] || no_score "the design score's tools are not at ${TOOLS} (${tool} is missing); pull the shared config, or name them with DESIGN_SCORE_TOOLS"
done
if ! cmp -s "${TOOLS}/swiftui/DesignScoreTests/DesignScoreCapture.swift" "${ADAPTER}"; then
  no_score "Ovation's copy of the SwiftUI adapter differs from the shared one, so the build side would be drawn by code the score was not written against. Refresh it with:
  cp \"${TOOLS}/swiftui/DesignScoreTests/DesignScoreCapture.swift\" \"${ADAPTER}\""
fi

COMMIT="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null)" || no_score "${REPO_ROOT} is not a git checkout, so the score could not name what it measured"
DIRTY=0
[ -z "$(git -C "${REPO_ROOT}" status --porcelain 2>/dev/null)" ] || DIRTY=1
CAPTURE="$(mktemp -d "${TMPDIR:-/tmp}/ovation-design-score-${SCREEN}.XXXXXX")" || no_score "could not make a capture folder"
echo "design-score: ${SCREEN}, against ${DESIGN#"${REPO_ROOT}"/}, capture in ${CAPTURE}"
[ "${DIRTY}" = 1 ] && echo "design-score: the checkout has uncommitted changes, so this score cannot close a Match issue"

echo "==> the design side"
node "${TOOLS}/capture-web.mjs" --design "${DESIGN}" --out "${CAPTURE}" --design-only \
  || no_score "the design side could not be drawn (above)"

echo "==> the built side: OvationHostedTests/${SUITE}"
TEST_RUNNER_DESIGN_SCORE_CAPTURE="${CAPTURE}" \
TEST_RUNNER_DESIGN_SCORE_COMMIT="${COMMIT}" \
TEST_RUNNER_DESIGN_SCORE_DIRTY="${DIRTY}" \
  bash "${REPO_ROOT}/scripts/run-tests.sh" --only "OvationHostedTests/${SUITE}" \
  || no_score "the snapshot suite failed, so the built side was not drawn (above)"

echo "==> the score"
python3 "${TOOLS}/design_score.py" score "${CAPTURE}"
SCORE=$?
if [ -n "${PR}" ]; then
  if [ "${SCORE}" -eq 2 ]; then
    echo "design-score: nothing was posted on #${PR}, because an unmeasured run is not a score"
  else
    # post's own exits: 0 posted on the pull request and its Match issue, 1 on the
    # pull request only (its milestone holds no Match issue for this design), 2
    # nothing posted. 1 is a score that reached the pull request, not a failure.
    python3 "${TOOLS}/design_score.py" post "${CAPTURE}/score.json" --repo "${REPO_SLUG}" --pr "${PR}"
    case $? in
      0) ;;
      1) echo "design-score: posted on #${PR} only, since its milestone holds no Match issue for this design" ;;
      *) no_score "the score was measured (exit ${SCORE}) but could not be posted on #${PR} (above)" ;;
    esac
  fi
fi
exit "${SCORE}"
