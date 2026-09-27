/* THE FOOT OF THE RAIL NAMES EACH OPEN THING (Dan, 2026-09-26, ovation#99 and
   ovation#566, PRD 44f). "So the foot carries no count. Each open item gets its
   own line, its short name with its own Read beside it, newest first, at most two
   lines, then "and N more". Read and unread items look the same (a notice closes
   once read, so what stays is standing problems). Nothing open: the whole foot
   disappears (the zero rule)."

   Each case: the open items, newest first, then the names the foot draws, then
   the line under them (null for none), then why.

   NOT RENDERED: these cases are run by scripts/test-design-rules.sh against
   rules/rail-foot.js, which the three screens carry; unlike the invoice
   screen's rules, no screen runs its own copy of the foot's cases. */
var RAIL_FOOT_CASES = [
  [[], [], null,
   "nothing open: the whole foot disappears, and an empty list is not a foot with nothing in it"],
  [["2026 export written"], ["2026 export written"], null,
   "one open thing is named, with no line under it"],
  [["2026 export written", "Backup 3 days behind"],
   ["2026 export written", "Backup 3 days behind"], null,
   "two open things are both named, newest first, and nothing counts them"],
  [["A", "B", "C"], ["A", "B"], "and 1 more",
   "a third open thing is not named; the foot says how many more there are"],
  [["A", "B", "C", "D", "E"], ["A", "B"], "and 3 more",
   "at most two lines of names, however many are open"]
];

/* What pressing I have read this leaves open. A notice closes once read; a
   standing problem stays until its condition clears, so reading it changes
   nothing on the foot. Each case: the items open, the one read, the names still
   open, why. */
var RAIL_READ_CASES = [
  [[["export", true], ["backup", false]], "export", ["backup"],
   "reading the notice closes it, and the standing problem becomes the first line"],
  [[["export", true], ["backup", false]], "backup", ["export", "backup"],
   "reading a standing problem leaves it open: read and unread look the same"],
  [[["backup", false]], "backup", ["backup"],
   "a standing problem read is still the whole foot until it clears"],
  [[["export", true]], "export", [],
   "the last notice read leaves nothing open, so the foot goes"]
];

function runRailFootTests() {
  var failures = [], ran = 0;
  RAIL_FOOT_CASES.forEach(function (c) {
    ran++;
    var items = c[0].map(function (s) { return { key: s, short: s }; });
    var got = footLines(items);
    var names = got.names.map(function (it) { return it.short; });
    if (JSON.stringify(names) !== JSON.stringify(c[1]))
      failures.push(c[3] + ": named " + JSON.stringify(names) + ", expected " + JSON.stringify(c[1]));
    if (got.more !== c[2])
      failures.push(c[3] + ": the line under was " + JSON.stringify(got.more) + ", expected " + JSON.stringify(c[2]));
    if (got.drawn !== (c[1].length > 0))
      failures.push(c[3] + ": drawn " + got.drawn);
  });

  /* "AND N MORE" OPENS A LIST OF EVERY OPEN ITEM (Dan, 2026-09-26, ovation#566:
     "Opens a list pop-up"), the two named above it included, so every open thing
     can be read from the sidebar. With nothing hidden there is no list. */
  RAIL_FOOT_CASES.forEach(function (c) {
    ran++;
    var items = c[0].map(function (s) { return { key: s, short: s }; });
    var got = footLines(items);
    var listed = got.listed.map(function (it) { return it.short; });
    var want = c[2] ? c[0] : [];
    if (JSON.stringify(listed) !== JSON.stringify(want))
      failures.push(c[3] + ": the list behind the line held " + JSON.stringify(listed)
        + ", expected " + JSON.stringify(want));
  });

  /* THE RETIRED WORDS NEVER COME BACK. "1 more to read" and "1 other problem"
     counted different things, and the decision retires both from the foot. */
  RAIL_FOOT_CASES.forEach(function (c) {
    ran++;
    var items = c[0].map(function (s) { return { key: s, short: s }; });
    var said = String(footLines(items).more);
    if (/to read|other problem/.test(said))
      failures.push(c[3] + ": the foot said " + said + ", which is a retired count");
  });

  RAIL_READ_CASES.forEach(function (c) {
    ran++;
    var items = c[0].map(function (p) { return { key: p[0], short: p[0], closesOnceRead: p[1] }; });
    var left = afterRead(items, c[1]).map(function (it) { return it.key; });
    if (JSON.stringify(left) !== JSON.stringify(c[2]))
      failures.push(c[3] + ": left " + JSON.stringify(left) + ", expected " + JSON.stringify(c[2]));
  });

  /* The list it was given is not changed in place: a caller holding it would
     otherwise see an item vanish that nothing it did removed. */
  ran++;
  var held = [{ key: "export", short: "x", closesOnceRead: true }];
  afterRead(held, "export");
  if (held.length !== 1) failures.push("afterRead changed the list it was given");

  return { ran: ran, failures: failures };
}
