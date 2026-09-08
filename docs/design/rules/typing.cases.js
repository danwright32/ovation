/* TYPING INTO A SEGMENT. Dan, 2026-09-07: "I can't type 12 in this or 11. Looks
   to be single digit only for hours?"

   He was right. The first version replaced the segment with each digit, so the
   two digit hours were unreachable. These cases are about ACCUMULATION, which
   the time model's own cases never touched: they tested the arithmetic and the
   wrapping, and typing is the part a person actually uses.

   Each case is: what is already buffered, the digit pressed, the maximum for
   that segment, then the value it should show and the buffer left behind. An
   empty buffer left behind means the segment is full and the next digit starts
   again. */

var TYPING_CASES = [
  /* buffer, digit, max, isHour, expected value, expected buffer, why */
  ["",   1, 12, true,  1,  "1",  "the first digit stands alone"],
  ["1",  2, 12, true,  12, "",   "and the second joins it, which is what was broken"],
  ["1",  1, 12, true,  11, "",   "eleven, likewise"],
  ["1",  0, 12, true,  10, "",   "ten"],
  ["1",  3, 12, true,  3,  "3",  "thirteen is not an hour, so the digit starts again"],
  ["9",  5, 12, true,  5,  "5",  "and ninety five certainly is not"],
  ["",   0, 12, true,  12, "0",  "hour zero is shown as 12, and the buffer still remembers the 0"],
  ["0",  9, 12, true,  9,  "",   "so 0 then 9 is nine o'clock"],
  ["",   3, 59, false, 3,  "3",  "minutes, first digit"],
  ["3",  0, 59, false, 30, "",   "half past"],
  ["5",  9, 59, false, 59, "",   "the last minute of the hour"],
  ["7",  5, 59, false, 5,  "5",  "seventy five is not a minute, so it starts again"],
  ["",   0, 59, false, 0,  "0",  "minute zero"],
  ["0",  5, 59, false, 5,  "",   "and five past"],
  ["12", 3, 12, true,  3,  "3",  "a full buffer starts again rather than growing to three digits"],
  ["a",  5, 12, true,  5,  "5",  "a buffer that is not digits cannot survive into the value (L50): parseInt gives NaN, and NaN > max is FALSE, so the guard that should reset it never fires and the segment reads NaN"],
  ["",   5, 12, true,  5,  "5",  "the ordinary path is unchanged by that guard"]
];

function runTypingTests() {
  var failures = [];
  TYPING_CASES.forEach(function (c) {
    var got = typeDigit(c[0], c[1], c[2], c[3]);
    if (got.value !== c[4] || got.buffer !== c[5]) {
      failures.push("typing " + c[1] + " after " + JSON.stringify(c[0]) + ": got value "
                    + got.value + " buffer " + JSON.stringify(got.buffer)
                    + ", expected " + c[4] + " and " + JSON.stringify(c[5]) + " (" + c[6] + ")");
    }
  });

  /* Every hour from 1 to 12 must be TYPEABLE, which is the thing Dan could not
     do. Driven through the same function a keystroke goes through, rather than
     asserted about the model. */
  for (var h = 1; h <= 12; h++) {
    var digits = String(h).split("");
    var buf = "", val = null;
    digits.forEach(function (d) {
      var r = typeDigit(buf, parseInt(d, 10), 12, true);
      buf = r.buffer; val = r.value;
    });
    if (val !== h) failures.push("hour " + h + " cannot be typed: ended at " + val);
  }
  for (var m = 0; m <= 59; m++) {
    var ds = (m < 10 ? "0" + m : String(m)).split("");
    var b = "", v = null;
    ds.forEach(function (d) {
      var r = typeDigit(b, parseInt(d, 10), 59, false);
      b = r.buffer; v = r.value;
    });
    if (v !== m) failures.push("minute " + m + " cannot be typed: ended at " + v);
  }
  return { ran: TYPING_CASES.length + 12 + 60, failures: failures };
}
