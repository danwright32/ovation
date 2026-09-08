
/* NO TWO SUITES MAY SHARE A GLOBAL. These files are concatenated into one page,
   so a name declared at the top level of two of them leaves only the last, and
   the other suite then runs against data that is not its own. That happened on
   2026-09-07: three suites each called their table CASES, and the typing suite
   reported five failures about tax values. It went red rather than quietly
   green, which is the safe direction, but the failures said nothing true. */
function checkSuitesAreIsolated() {
  var tables = { DURATION_CASES: DURATION_CASES,
                 TIME_CASES_MINUTES: TIME_CASES_MINUTES, TIME_CASES_BUMP: TIME_CASES_BUMP,
                 TYPING_CASES: TYPING_CASES, TAX_CASES: TAX_CASES,
                 MONEY_CASES: MONEY_CASES };
  var problems = [];
  Object.keys(tables).forEach(function (name) {
    if (!Array.isArray(tables[name]) || !tables[name].length)
      problems.push(name + " is missing or empty, so a suite is running against nothing");
  });
  if (typeof CASES !== "undefined")
    problems.push("a global called CASES still exists, which is the name that collided");
  return problems;
}
