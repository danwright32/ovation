#!/bin/bash
# The invoice screen's rules, as executable cases (ovation#111).
#
# These are DESIGN artifacts, not app code. Each rule was settled with Dan in a
# design round and written as a function with its cases so the decision is
# executable rather than only described, and so whoever ports it to Swift has
# something to port AGAINST. They cover:
#
#   duration.js    the shoot's hours from its start and end times: rounding to
#                  the nearest quarter, the one hour minimum, a shoot that ends
#                  after midnight, and a span too long to be a shoot
#   time-field.js  the segmented time control's model and its TYPING, which is a
#                  separate surface: the value model passed every case while the
#                  field could not reach 10, 11 or 12 (L442)
#   tax-line.js    the three states of the tax line, including that a status
#                  never recorded must never behave like "not exempt"
#   money.js       the discount and the referral credit, which net to the same
#                  tax and must never be merged (PRD 5.4b)
#
# JUDGED BY EXIT CODE. And a missing node is a REFUSAL, never a pass: a suite
# that reports success when it found nothing to run is indistinguishable from
# one where everything passed (L98).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES="${REPO_ROOT}/docs/design/rules"

NODE=""
for candidate in node "$HOME"/.local/state/fnm_multishells/*/bin/node /opt/homebrew/bin/node /usr/local/bin/node; do
    if command -v "$candidate" >/dev/null 2>&1; then NODE="$(command -v "$candidate")"; break; fi
    if [ -x "$candidate" ]; then NODE="$candidate"; break; fi
done
if [ -z "$NODE" ]; then
    echo "test-design-rules: CANNOT MEASURE, no node found." >&2
    echo "test-design-rules: the rules were NOT checked. This is a refusal, not a pass." >&2
    exit 1
fi

cat "${RULES}"/duration.js "${RULES}"/time-field.js "${RULES}"/tax-line.js "${RULES}"/money.js \
    "${RULES}"/waiting.js \
    "${RULES}"/duration.cases.js "${RULES}"/time-field.cases.js "${RULES}"/typing.cases.js \
    "${RULES}"/tax-line.cases.js "${RULES}"/money.cases.js "${RULES}"/waiting.cases.js \
    "${RULES}"/suite-isolation.js \
  > "${TMPDIR:-/tmp}/ovation-design-rules.$$.js"

cat >> "${TMPDIR:-/tmp}/ovation-design-rules.$$.js" <<'JS'
var isolation = checkSuitesAreIsolated();
var suites = [
  ["duration", runDurationTests()],
  ["time field", runTimeFieldTests()],
  ["typing", runTypingTests()],
  ["tax line", runTaxTests()],
  ["waiting on", runWaitingTests()],
  ["money", runMoneyTests()]
];
var ran = suites.reduce(function (a, s) { return a + s[1].ran; }, 0);
var bad = isolation.slice();
suites.forEach(function (s) {
  s[1].failures.forEach(function (f) { bad.push(s[0] + ": " + f); });
});
if (bad.length) {
  console.log(bad.length + " of " + ran + " design rule cases FAILED:");
  bad.forEach(function (f) { console.log("  " + f); });
  process.exit(1);
}
/* The count is asserted, not just the absence of failures: a suite that runs
   half of itself and reports no failures reads exactly like a green one (L288,
   and ovation#106 filed for the same shape in the main suite). */
if (ran < 130) {
  console.log("only " + ran + " cases ran, which is fewer than the 130 these files carry.");
  process.exit(1);
}
console.log("design rules: " + ran + " cases pass across " + suites.length + " suites, isolation checked");
JS

"$NODE" "${TMPDIR:-/tmp}/ovation-design-rules.$$.js"
STATUS=$?
rm -f "${TMPDIR:-/tmp}/ovation-design-rules.$$.js"
exit $STATUS
