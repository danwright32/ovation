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
    "${RULES}"/waiting.js "${RULES}"/pdf-text.js \
    "${RULES}"/duration.cases.js "${RULES}"/time-field.cases.js "${RULES}"/typing.cases.js \
    "${RULES}"/tax-line.cases.js "${RULES}"/money.cases.js "${RULES}"/waiting.cases.js \
    "${RULES}"/suite-isolation.js \
  > "${TMPDIR:-/tmp}/ovation-design-rules.$$.js"

# THE PDF'S TEXT RULES ARE JUDGED BY CASES THE APP READS TOO (ovation#167). They
# live in JSON rather than in a cases.js file, because OvationTests/PDFTextTests.swift
# reads the same file against the app's own formatter, and two implementations of
# one rule each tested by cases of their own agree on the day they are written and
# then drift (L26). The table's isolation check is made here rather than in
# suite-isolation.js, because that file is inlined into the invoice screen's
# design, which has no PDF text table to find.
{ printf 'var PDF_TEXT_CASES = '; cat "${RULES}"/pdf-text.cases.json; printf ';\n'; } \
  >> "${TMPDIR:-/tmp}/ovation-design-rules.$$.js"

cat >> "${TMPDIR:-/tmp}/ovation-design-rules.$$.js" <<'JS'
function runPdfTextTests() {
  var failures = [], ran = 0;
  PDF_TEXT_CASES.money.forEach(function (c) {
    ran++;
    var got = money(c.cents / 100);
    if (got !== c.text) failures.push(c.cents + " cents wrote " + got + ", expected " + c.text + " (" + c.why + ")");
  });
  PDF_TEXT_CASES.hours.forEach(function (c) {
    ran++;
    var got = hours(c.hundredths / 100);
    if (got !== c.text) failures.push(c.hundredths + " hundredths wrote " + got + ", expected " + c.text + " (" + c.why + ")");
  });
  /* PRD 50c: the hours AS PRINTED, read back by digits alone, times the rate
     must be the amount, which is what a one decimal quarter hour broke. */
  PDF_TEXT_CASES.hourly.forEach(function (c) {
    ran++;
    var printed = hours(c.hundredths / 100).split(" ")[0].split(".");
    var readBack = parseInt(printed[0], 10) * 100 + parseInt((printed[1] + "00").slice(0, 2), 10);
    var amount = Math.round(readBack * c.rateCents / 100);
    if (amount !== c.amountCents) failures.push("printed " + hours(c.hundredths / 100) + " at " + c.rateCents + " cents is " + amount + ", expected " + c.amountCents + " (" + c.why + ")");
  });
  return { ran: ran, failures: failures };
}
var isolation = checkSuitesAreIsolated();
["money", "hours", "hourly"].forEach(function (k) {
  if (!Array.isArray(PDF_TEXT_CASES[k]) || !PDF_TEXT_CASES[k].length)
    isolation.push("PDF_TEXT_CASES." + k + " is missing or empty, so a suite is running against nothing");
});
var suites = [
  ["duration", runDurationTests()],
  ["time field", runTimeFieldTests()],
  ["typing", runTypingTests()],
  ["tax line", runTaxTests()],
  ["waiting on", runWaitingTests()],
  ["money", runMoneyTests()],
  ["pdf text", runPdfTextTests()]
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
if (ran < 151) {
  console.log("only " + ran + " cases ran, which is fewer than the 151 these files carry.");
  process.exit(1);
}
console.log("design rules: " + ran + " cases pass across " + suites.length + " suites, isolation checked");
JS

"$NODE" "${TMPDIR:-/tmp}/ovation-design-rules.$$.js"
STATUS=$?
rm -f "${TMPDIR:-/tmp}/ovation-design-rules.$$.js"
exit $STATUS
