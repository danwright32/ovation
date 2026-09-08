/* A FIRST CLASS TIME CONTROL. Dan, 2026-09-07, on the native one: "this needs to
   be first class, not this ugly picker."

   The rendering had used an HTML time input, which in Chrome opens a large blue
   list belonging to no design. Calling that "a web idiom to translate" was not
   good enough: an ugly control in a rendering is judged as the design.

   SEGMENTED, the way the macOS control actually is: hour, minute, meridiem,
   each adjusted on its own. That is not decoration. A single typed field has to
   resolve "7:30", which is ambiguous, and either guesses or refuses; segments
   cannot be ambiguous, so the question never arises.

   EACH SEGMENT WRAPS WITHOUT CARRYING. Stepping the minutes past 59 returns to
   00 and leaves the hour alone, which is what every stepper on the platform
   does: the person is setting a field, not counting time. */

function clampSeg(v, lo, hi) {
  var span = hi - lo + 1;
  return ((v - lo) % span + span) % span + lo;
}

/* h12 is 1 to 12, min is 0 to 59, pm is a boolean. */
function bumpTime(t, segment, delta) {
  var next = { h12: t.h12, min: t.min, pm: t.pm };
  if (segment === "hour") next.h12 = clampSeg(t.h12 + delta, 1, 12);
  else if (segment === "min") next.min = clampSeg(t.min + delta, 0, 59);
  else next.pm = !t.pm;
  return next;
}

/* Minutes since midnight. The two cases every 12 hour clock gets wrong are noon
   and midnight, because 12 is the hour that does NOT follow the rule. */
function timeToMinutes(t) {
  if (!t) return null;
  var h = t.h12 % 12;              /* 12 becomes 0 */
  if (t.pm) h += 12;               /* so 12 PM is 12, and 12 AM is 0 */
  return h * 60 + t.min;
}

function minutesToTime(m) {
  if (m === null || m === undefined) return null;
  var h24 = Math.floor(m / 60) % 24, min = m % 60;
  return { h12: (h24 % 12) === 0 ? 12 : h24 % 12, min: min, pm: h24 >= 12 };
}

function formatTime(t) {
  if (!t) return null;
  return t.h12 + ":" + (t.min < 10 ? "0" : "") + t.min + " " + (t.pm ? "PM" : "AM");
}

/* TYPING A SEGMENT, which ACCUMULATES rather than replaces.

   Dan, 2026-09-07: "I can't type 12 in this or 11. Looks to be single digit
   only for hours?" He was right: the first version wrote each digit over the
   last, so 10, 11 and 12 could not be reached at all.

   The buffer holds what has been typed into this segment so far. A digit
   EXTENDS it where the result is still a legal value, and otherwise starts
   again from that digit, which is what every segmented time field does: after
   9 the only sensible reading of a 5 is five o'clock, not ninety five.

   There is deliberately NO TIMER. A buffer that expires after a pause would
   need a clock injected to be testable at all, and it would make the same
   keystrokes mean different things depending on how fast they were pressed.
   The buffer clears when the segment fills, and when focus leaves. */
function typeDigit(buffer, digit, max, isHour) {
  var candidate = (buffer || "") + String(digit);
  if (candidate.length > 2 || parseInt(candidate, 10) > max) candidate = String(digit);
  var n = parseInt(candidate, 10);
  var value = (isHour && n === 0) ? 12 : n;
  return { value: value, buffer: candidate.length >= 2 ? "" : candidate };
}
