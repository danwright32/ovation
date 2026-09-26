var TAXRATE = 0.08875;

/* NOBODY ASKS FOR A CREDIT AMOUNT (Dan, 2026-09-23, ovation#457, PRD 4c). A
   credit spends the smaller of what the client has banked and what the invoice
   is charging, and he chose that over a sheet asking how much to spend, so no
   case carries an asked figure. Until 2026-09-26 three of them did, and they
   described the shape he rejected (ovation#500).

   THE CASES ARE STRICT JSON, one object each, because the app's suite reads this
   same table (OvationTests/DesignMoneyCasesTests.swift) through the app's own
   credit writer and invoice arithmetic, and two implementations each tested by
   cases of their own agree on the day they are written and then drift (L26).
   The balance is in hundredths of an hour at the case's rate, because the
   ledger banks hours, not dollars (PRD 8). */
var MONEY_CASES = [
  {"lines": 375, "rate": 250, "balanceHundredths": 0, "kind": null, "value": null,
   "expect": {"credit": 0, "subtotal": 375, "discount": 0, "tax": 33.28, "total": 408.28},
   "why": "neither, which is almost every invoice"},
  {"lines": 375, "rate": 250, "balanceHundredths": 100, "kind": null, "value": null,
   "expect": {"credit": 250, "subtotal": 125, "discount": 0, "tax": 11.09, "total": 136.09},
   "why": "a credit alone, the only shape that has ever appeared in the real data: a balance smaller than the charges is spent whole"},
  {"lines": 375, "rate": 250, "balanceHundredths": 0, "kind": "percent", "value": 10,
   "expect": {"credit": 0, "subtotal": 375, "discount": 37.50, "tax": 29.95, "total": 367.45},
   "why": "a discount alone"},
  {"lines": 375, "rate": 250, "balanceHundredths": 100, "kind": "percent", "value": 10,
   "expect": {"credit": 250, "subtotal": 125, "discount": 12.50, "tax": 9.98, "total": 122.48},
   "why": "BOTH: the discount comes off a subtotal the credit has already reduced"},
  {"lines": 375, "rate": 250, "balanceHundredths": 100, "kind": "amount", "value": 50,
   "expect": {"credit": 250, "subtotal": 125, "discount": 50, "tax": 6.66, "total": 81.66},
   "why": "both, with an amount rather than a percentage"},
  {"lines": 375, "rate": 250, "balanceHundredths": 150, "kind": null, "value": null,
   "expect": {"credit": 375, "subtotal": 0, "discount": 0, "tax": 0, "total": 0},
   "why": "a balance exactly covering the invoice, which is a legitimate zero (PRD 5.1b)"},
  {"lines": 375, "rate": 250, "balanceHundredths": 200, "kind": null, "value": null,
   "expect": {"credit": 375, "subtotal": 0, "discount": 0, "tax": 0, "total": 0},
   "why": "a balance larger than the invoice takes it to nothing, never below (PRD 4c)"},
  {"lines": 375, "rate": 250, "balanceHundredths": 40, "kind": null, "value": null,
   "expect": {"credit": 100, "subtotal": 275, "discount": 0, "tax": 24.41, "total": 299.41},
   "why": "no more is spent than the client has banked, even a part of an hour (PRD 5.8)"},
  {"lines": 375, "rate": 250, "balanceHundredths": 0, "kind": null, "value": null,
   "expect": {"credit": 0, "subtotal": 375, "discount": 0, "tax": 33.28, "total": 408.28},
   "why": "no balance at all means no credit, not a negative one"}
];

function moneyCaseBalance(c) { return cents(c.balanceHundredths / 100 * c.rate); }

function runMoneyTests() {
  var failures = [];
  MONEY_CASES.forEach(function (c) {
    var g = invoiceTotals(c.lines, moneyCaseBalance(c), c.kind, c.value, TAXRATE);
    ["credit", "subtotal", "discount", "tax", "total"].forEach(function (k) {
      if (g[k] !== c.expect[k]) failures.push(c.why + ": " + k + " was " + g[k] + ", expected " + c.expect[k]);
    });
  });

  /* THE INVARIANT THAT KEEPS THE TWO APART, checked on every case rather than
     asserted once: the credit acts INSIDE the subtotal and the discount acts on
     what is left, so swapping them changes the money. */
  MONEY_CASES.forEach(function (c) {
    var g = invoiceTotals(c.lines, moneyCaseBalance(c), c.kind, c.value, TAXRATE);
    if (cents(g.lines - g.credit) !== g.subtotal)
      failures.push(c.why + ": the credit is not inside the subtotal");
    if (cents(g.subtotal - g.discount) !== g.taxable)
      failures.push(c.why + ": the discount is not taken off the subtotal");
    if (cents(g.taxable + g.tax) !== g.total)
      failures.push(c.why + ": the figures down the page do not add up");
    if (g.total < 0 || g.subtotal < 0) failures.push(c.why + ": a figure went below nothing");
    if (g.credit > moneyCaseBalance(c)) failures.push(c.why + ": more credit was spent than was earned");
  });
  return { ran: MONEY_CASES.length, failures: failures };
}
