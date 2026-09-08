var DURATION_CASES = [
  ["19:30", "21:00",  90,  1.5,   false, "an ordinary evening, already tidy"],
  ["19:32", "21:04",  92,  1.5,   false, "1h32m rounds down to the quarter"],
  ["19:32", "21:10",  98,  1.75,  true,  "1h38m rounds up to the quarter"],
  ["19:00", "19:40",  40,  1,     true,  "40 minutes bills the one hour minimum (PRD 5.3)"],
  ["19:00", "20:00",  60,  1,     false, "an exact hour is not touched by the minimum"],
  ["19:00", "19:08",   8,  1,     true,  "eight minutes still bills the minimum, never 0.25"],
  ["21:00", "00:30", 210,  3.5,   false, "a concert that ends after midnight is not a negative shoot"],
  ["22:15", "01:00", 165,  2.75,  false, "and again across midnight, landing on a quarter"],
  ["19:00", "19:00", 1440, null,  false, "identical times read as a whole day, which is over the cap"],
  ["19:00", "01:30", 390,  6.5,   false, "a long evening, just under the longest ever billed plus room"],
  ["09:00", "08:00", 1380, null,  false, "a 23 hour span is a typo, not a shoot, and prices nothing"],
  ["7:30",  "9:00",   90,  1.5,   false, "a single digit hour parses"],
  ["19:67", "21:00", null, null,  false, "minutes past 59 are not a time"],
  ["25:00", "26:00", null, null,  false, "hours past 23 are not a time"],
  ["1930",  "21:00", null, null,  false, "a time needs its colon"],
  ["",      "21:00", null, null,  false, "no start means no duration, which is not the same as a bad one"]
];

function runDurationTests() {
  var failures = [];

  /* The invariant the cases cannot see, because it is about the CONSTANTS
     rather than about any input: the minimum must be a whole number of
     quarters, or the order of rounding and flooring starts to matter and the
     billed figure can land off a quarter. */
  var steps = MINIMUM_HOURS / QUARTER;
  if (Math.abs(steps - Math.round(steps)) > 1e-9) {
    failures.push("the one hour minimum (" + MINIMUM_HOURS + ") is not a whole number of "
                  + QUARTER + " hour steps, so rounding and the minimum no longer commute");
  }

  DURATION_CASES.forEach(function (c) {
    var got = durationBetween(c[0], c[1]);
    var where = c[0] + " to " + c[1] + " (" + c[5] + ")";
    if (c[3] === null) {
      if (got !== null) failures.push(where + ": expected nothing priced, got " + JSON.stringify(got));
      return;
    }
    if (got === null) { failures.push(where + ": expected " + c[3] + " hours, got nothing"); return; }
    if (got.minutes !== c[2]) failures.push(where + ": elapsed " + got.minutes + "m, expected " + c[2] + "m");
    if (got.billedHours !== c[3]) failures.push(where + ": billed " + got.billedHours + ", expected " + c[3]);
    if (got.roundedUp !== c[4]) failures.push(where + ": roundedUp " + got.roundedUp + ", expected " + c[4]);
  });
  return { ran: DURATION_CASES.length, failures: failures };
}
