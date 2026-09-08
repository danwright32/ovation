var TAXRATE = 0.08875;

/* lines, creditAsked, balance, kind, value, expect {credit, subtotal, discount, tax, total}, why */
var MONEY_CASES = [
  [375, 0,   0,   null,      null, {credit:0,   subtotal:375, discount:0,     tax:33.28, total:408.28},
   "neither, which is almost every invoice"],
  [375, 100, 250, null,      null, {credit:100, subtotal:275, discount:0,     tax:24.41, total:299.41},
   "a credit alone, the only shape that has ever appeared in the real data"],
  [375, 0,   0,   "percent", 10,   {credit:0,   subtotal:375, discount:37.50, tax:29.95, total:367.45},
   "a discount alone"],
  [375, 100, 250, "percent", 10,   {credit:100, subtotal:275, discount:27.50, tax:21.97, total:269.47},
   "BOTH: the discount comes off a subtotal the credit has already reduced"],
  [375, 100, 250, "amount",  50,   {credit:100, subtotal:275, discount:50,    tax:19.97, total:244.97},
   "both, with an amount rather than a percentage"],
  [375, 375, 500, null,      null, {credit:375, subtotal:0,   discount:0,     tax:0,     total:0},
   "a credit covering the whole invoice, which is a legitimate zero (PRD 5.1b)"],
  [375, 500, 500, null,      null, {credit:375, subtotal:0,   discount:0,     tax:0,     total:0},
   "a credit larger than the invoice takes it to nothing, never below"],
  [375, 250, 100, null,      null, {credit:100, subtotal:275, discount:0,     tax:24.41, total:299.41},
   "spending credit the client does not have is capped at the balance (PRD 5.8)"],
  [375, 100, 0,   null,      null, {credit:0,   subtotal:375, discount:0,     tax:33.28, total:408.28},
   "no balance at all means no credit, not a negative one"]
];

function runMoneyTests() {
  var failures = [];
  MONEY_CASES.forEach(function (c) {
    var g = invoiceTotals(c[0], c[1], c[2], c[3], c[4], TAXRATE);
    var e = c[5], why = c[6];
    ["credit", "subtotal", "discount", "tax", "total"].forEach(function (k) {
      if (g[k] !== e[k]) failures.push(why + ": " + k + " was " + g[k] + ", expected " + e[k]);
    });
  });

  /* THE INVARIANT THAT KEEPS THE TWO APART, checked on every case rather than
     asserted once: the credit acts INSIDE the subtotal and the discount acts on
     what is left, so swapping them changes the money. */
  MONEY_CASES.forEach(function (c) {
    var g = invoiceTotals(c[0], c[1], c[2], c[3], c[4], TAXRATE);
    if (cents(g.lines - g.credit) !== g.subtotal)
      failures.push(c[6] + ": the credit is not inside the subtotal");
    if (cents(g.subtotal - g.discount) !== g.taxable)
      failures.push(c[6] + ": the discount is not taken off the subtotal");
    if (cents(g.taxable + g.tax) !== g.total)
      failures.push(c[6] + ": the figures down the page do not add up");
    if (g.total < 0 || g.subtotal < 0) failures.push(c[6] + ": a figure went below nothing");
    if (g.credit > c[2]) failures.push(c[6] + ": more credit was spent than was earned");
  });
  return { ran: MONEY_CASES.length, failures: failures };
}
