/* HOURS DERIVED FROM A START AND AN END TIME. Dan, 2026-09-07: "I'd love to be
   able to do a start and end time and have it calculate the hours", rounding to
   the nearest quarter hour (his choice, put to him with the measurement: 94% of
   his billed lines over 2019 to 2024 already land on a quarter).

   These are the REAL times of the shoot, entered by Dan after it happened. They
   are not Downbeat's booking times, which PRD 5.3a says are a placeholder that
   nothing may ever be priced from. This is what ovation#95 asked for.

   Three rules live here and each is a decision rather than arithmetic.

   THE ONE HOUR MINIMUM (PRD 5.3). Forty minutes bills one hour.

   Whether the minimum is applied before or after the rounding makes NO
   difference, and that is only true because the minimum is itself a whole
   number of quarters. Change it to something that is not, say 1.1 hours, and
   the two orders disagree and one of them starts producing figures that are
   not on a quarter at all. A mutation swapping the order was not caught by any
   case, which is how this coupling was found, so it is asserted below rather
   than left as a comment nothing enforces (L407).

   CROSSING MIDNIGHT. An evening concert can start at 21:00 and end at 00:30,
   and read literally that is a negative duration. An end at or before the start
   is taken as the next day, which is the only reading that is ever true of a
   shoot. It is capped, because 09:00 to 08:00 is far more likely to be a typo
   than a 23 hour shoot.

   THE CAP. Above CAP_HOURS nothing is priced, because a duration that long is
   a mistake rather than a shoot: the longest Dan has ever billed is 6.25 hours
   and the median is 1.625. PRD 5.3b requires such a value to be refused BY NAME
   rather than priced, and naming it is a surface decision that is not made here.
   What is guaranteed here is that it prices nothing. */

var QUARTER = 0.25;
var MINIMUM_HOURS = 1;
var CAP_HOURS = 12;

function parseClock(text) {
  var m = /^([0-9]{1,2}):([0-9]{2})$/.exec(String(text == null ? "" : text).trim());
  if (!m) return null;
  var h = parseInt(m[1], 10), min = parseInt(m[2], 10);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

function roundToQuarter(hours) {
  return Math.round(hours / QUARTER) * QUARTER;
}

/* Returns null where no duration can be read, otherwise the minutes elapsed
   and the hours that will be billed, so a caller can show the person BOTH and
   never make the rounding silent. */
function durationBetween(startText, endText) {
  var start = parseClock(startText), end = parseClock(endText);
  if (start === null || end === null) return null;
  var minutes = end - start;
  if (minutes <= 0) minutes += 24 * 60;
  var raw = minutes / 60;
  if (raw > CAP_HOURS) return null;
  var billed = Math.max(MINIMUM_HOURS, roundToQuarter(raw));
  return { minutes: minutes, rawHours: raw, billedHours: billed,
           roundedUp: billed > raw, atMinimum: billed === MINIMUM_HOURS && roundToQuarter(raw) < MINIMUM_HOURS };
}
