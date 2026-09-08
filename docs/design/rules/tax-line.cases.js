/* status, taxable, expected amount (null means no figure at all), drawn,
   refusesSend, saysWhy, label, why */
var TAX_CASES = [
  [null,         375, null,  false, true,  true,  null,
   "never recorded: NO TAX FIGURE AT ALL, because we do not yet know whether any applies (Dan, 2026-09-07)"],
  ["not-exempt", 375, 33.28, true,  false, false, "Sales tax, 8.875%",
   "not exempt: charged, drawn, nothing said"],
  ["exempt",     375, 0,     true,  false, false, "Sales tax, exempt",
   "exempt: STILL DRAWN at zero and names the reason (PRD 5.5c), because a measured zero is not an absence"],
  ["exempt",     0,   0,     true,  false, false, "Sales tax, exempt",
   "a comped invoice for an exempt client is all zeroes and still draws the line"],
  [null,         0,   null,  false, true,  true,  null,
   "a comped invoice for an unrecorded client still shows no tax and is still refused"]
];

function runTaxTests() {
  var failures = [];
  TAX_CASES.forEach(function (c) {
    var g = taxLineFor(c[0], c[1]);
    var why = c[7];
    if (g.amount !== c[2]) failures.push(why + ": amount " + g.amount + ", expected " + c[2]);
    if (g.drawn !== c[3]) failures.push(why + ": drawn " + g.drawn + ", expected " + c[3]);
    if (g.refusesSend !== c[4]) failures.push(why + ": refusesSend " + g.refusesSend + ", expected " + c[4]);
    if (g.saysWhy !== c[5]) failures.push(why + ": saysWhy " + g.saysWhy + ", expected " + c[5]);
    if (g.label !== c[6]) failures.push(why + ": label " + JSON.stringify(g.label) + ", expected " + JSON.stringify(c[6]));
  });

  /* AN UNKNOWN IS NOT A ZERO, and neither is a zero an unknown. These two are
     the pair the whole requirement turns on, so they are asserted directly
     rather than left to the table. */
  var unknown = taxLineFor(null, 375), exempt = taxLineFor("exempt", 375);
  if (unknown.drawn) failures.push("an unknown tax is drawn as a figure, which asserts an amount nobody has established");
  if (!exempt.drawn) failures.push("an exempt client's zero is NOT drawn, which loses the difference between a deliberate exemption and an oversight (PRD 5.5c)");
  if (unknown.refusesSend === taxLineFor("not-exempt", 375).refusesSend)
    failures.push("an unrecorded status behaves the same as not exempt, which PRD 5.5 forbids");

  /* And nothing may compute a TOTAL from a tax nobody knows. */
  if (unknown.amount !== null)
    failures.push("an unknown tax carries a number, so a total could be computed from it");
  return { ran: TAX_CASES.length + 4, failures: failures };
}
