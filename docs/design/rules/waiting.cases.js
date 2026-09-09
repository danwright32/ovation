/* WHAT THE INVOICE IS WAITING ON, and it must name the thing that is actually
   missing rather than the class of thing.

   Dan, 2026-09-08, describing the workflow the screen has to serve: "I plan to
   create drafts with no end time (although I can put the start time in from the
   creation). When I go to send the invoice I will always know the end time."

   So A DRAFT CARRYING A START TIME AND NO END TIME IS THE ORDINARY STATE OF
   EVERY DRAFT, not an edge case. Measured on the committed screen before this
   rule existed: that state was drawn identically to a draft with nothing in it
   at all, saying "Needs the times" while one of them was plainly on screen, and
   the greyed main action read "Waiting on the shoot's start and end times" while
   waiting on one. The everyday case was being drawn as the empty case, which no
   fixture had ever reached because every fixture had both times or neither
   (L101).

   ONE VOCABULARY, COMPLETE OVER ITS STATES. The reason and the two sentences
   that carry it come from here together, so the screen cannot say one thing
   where the figure is drawn and a different thing under the main action (L113, L611).

   start and end are minutes since midnight or null. status is null,
   "exempt" or "not-exempt". */

var WAITING_CASES = [
  /* start, end, status, expected reason, why */
  [null, null, null, "times",
   "nothing in at all: the only state that may ask for both"],
  [1170, null, null, "end",
   "THE EVERYDAY DRAFT. A start time and no end time asks for the END, by name"],
  [null, 1290, null, "start",
   "and the other way round, which a booking with only a finish would give"],
  [1170, 1290, null, "status",
   "both times in, so the next thing outstanding is the tax status"],
  [1170, 1290, "not-exempt", null,
   "nothing outstanding: the invoice can be sent"],
  [1170, 1290, "exempt", null,
   "an exempt client is answered too, and answered is not the same as untaxed"],
  [540, 480, null, "duration",
   "9:00 AM to 8:00 AM is 23 hours, over the cap, so the TIMES are in and the "
   + "duration is the thing that is wrong: asking for the times again is asking "
   + "for something already given"],
  [1170, 1170, null, "duration",
   "identical times read as a whole day, which is also over the cap"]
];

function runWaitingTests() {
  var failures = [];
  WAITING_CASES.forEach(function (c) {
    var got = waitingOnFor(c[0], c[1], c[2]);
    var reason = got === null ? null : got.reason;
    if (reason !== c[3]) {
      failures.push(c[4] + ": reason " + JSON.stringify(reason)
                    + ", expected " + JSON.stringify(c[3]));
      return;
    }
    if (got === null) return;
    /* A REASON THE SEND CANNOT EXPLAIN IS A DEAD CONTROL. Every reason carries a
       tip, always, because the greyed main action is the one place the person is
       looking when they cannot send (L109, L148). */
    if (!got.tip) {
      failures.push(c[4] + ": reason " + reason + " leaves the main action with nothing to say");
    }
    if (got.tip && got.tip.slice(-1) !== ".") {
      failures.push(c[4] + ": the tip is a sentence and needs its full stop");
    }
    /* `says` is what is drawn BESIDE THE TIMES, and exactly one reason has none:
       once both times are in, that space carries the duration the invoice is
       actually billing, and the tax status is asked in the totals block where
       the figure it changes appears. Asserted as an equivalence rather than
       skipped, so a second reason quietly losing its sentence is caught. */
    if ((got.says === null) !== (reason === "status")) {
      failures.push(c[4] + ": reason " + reason + " has says=" + JSON.stringify(got.says)
                    + ", but only the tax status is answered away from the times");
    }
  });

  /* THE TWO THAT THE WHOLE RULE TURNS ON, asserted directly rather than left to
     the table: a half filled draft must not say what an empty one says. */
  var empty = waitingOnFor(null, null, null);
  var started = waitingOnFor(1170, null, null);
  if (empty.reason === started.reason)
    failures.push("a draft with a start time says the same as one with nothing in it");
  if (empty.says === started.says || empty.tip === started.tip)
    failures.push("the two read identically on screen even though the reasons differ");
  if (started.says.indexOf("end") === -1 || started.tip.indexOf("ended") === -1)
    failures.push("a draft waiting on its end time does not say END anywhere a person reads");

  /* And the times being IN is different again from the times being wrong. */
  var overCap = waitingOnFor(540, 480, null);
  if (overCap.reason === empty.reason)
    failures.push("an implausible duration asks for the times as though none were given");

  /* EVERY REASON THE RULE CAN RETURN IS COVERED ABOVE. A vocabulary whose
     completeness nothing enforces silently grows a member nobody drew (L113). */
  var seen = {};
  WAITING_CASES.forEach(function (c) { if (c[3]) seen[c[3]] = true; });
  ["times", "start", "end", "duration", "status"].forEach(function (r) {
    if (!seen[r]) failures.push("the reason " + r + " has no case");
  });

  return { ran: WAITING_CASES.length + 5, failures: failures };
}
