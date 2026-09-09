/* WHAT THE INVOICE IS WAITING ON, named as the thing that is actually missing.

   Dan, 2026-09-08: "I plan to create drafts with no end time (although I can put
   the start time in from the creation). When I go to send the invoice I will
   always know the end time."

   That makes a start time with no end time THE ORDINARY STATE OF EVERY DRAFT,
   and the screen was drawing it as the empty state: "Needs the times" with one
   of them plainly on screen, and a greyed main action reading "Waiting on the shoot's
   start and end times" while waiting on one of them.

   ONE THING AT A TIME, IN A FIXED ORDER, which is round 4's settled rule and the
   reason this returns a single reason rather than a list. Dan's own argument for
   it: "what happens if I set the tax status before the hours? That line just
   disappears and nothing takes its place." The order here is the times, then the
   duration they produce, then the tax status.

   THE TIMES BEING IN IS NOT THE SAME AS THE TIMES BEING USABLE. Both times can
   be present and still price nothing, because a span over the cap is a typo
   rather than a shoot (see duration.js). Asking for the times again in that
   state asks for something already given, so it has its own reason. PRD 5.3b
   wants such a value refused BY NAME and this is that name.

   THE SENTENCES LIVE HERE, WITH THE REASON. They are drawn in two places, where
   the figure would be and under the greyed main action, and a screen that says one
   thing in one place and something else in the other is two vocabularies for one
   fact (L113, L611).

   start and end are minutes since midnight or null. status is null, "exempt" or
   "not-exempt". Returns null when nothing is outstanding. */

function waitingOnFor(start, end, status) {
  if (start === null && end === null) {
    return { reason: "times",
             says: "Needs the times",
             tip: "Waiting on the shoot's start and end times." };
  }
  if (end === null) {
    return { reason: "end",
             says: "Needs the end time",
             tip: "Waiting on the time the shoot ended." };
  }
  if (start === null) {
    return { reason: "start",
             says: "Needs the start time",
             tip: "Waiting on the time the shoot started." };
  }

  /* Both times are in. Whether they produce a billable duration is the
     duration rule's decision, asked here rather than re-implemented (L370). */
  var pad = function (m) {
    return String(Math.floor(m / 60)).padStart(2, "0") + ":" + String(m % 60).padStart(2, "0");
  };
  if (durationBetween(pad(start), pad(end)) === null) {
    return { reason: "duration",
             says: "Longer than a shoot",
             tip: "That is more than " + CAP_HOURS + " hours, so it prices nothing. Check the times." };
  }

  if (status === null) {
    return { reason: "status",
             says: null,
             tip: "Waiting on this client's tax status." };
  }
  return null;
}
