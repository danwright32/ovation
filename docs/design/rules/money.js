/* THE DISCOUNT AND THE REFERRAL CREDIT, PRD 5.4a, 5.4b and 5.8.

   They net out to the same tax, which is exactly why they are easy to merge and
   must not be. The difference is WHERE each one acts:

   A REFERRAL CREDIT IS A NEGATIVE LINE, so it is INSIDE the subtotal. It is
   earned against a ledger, one hour per hour of the referred client's first
   booking, and it is spent.

   A DISCOUNT IS NOT A LINE. It sits BELOW the subtotal and is a decision Dan
   makes on the day, answering to nothing.

   So a discount applies to a subtotal that has ALREADY had the credit taken out
   of it. Reverse those and the money is different, and the export needs them
   apart to answer how much was given away in a year. */

function cents(n) { return Math.round(n * 100) / 100; }

function discountAmount(kind, value, subtotal) {
  if (value === null || !isFinite(value) || value <= 0) return 0;
  if (kind === "percent") return cents(subtotal * (value / 100));
  return cents(Math.min(value, subtotal));
}

/* creditHours is what the client has EARNED and not yet spent. A credit may
   never exceed the balance, nor take an invoice below nothing: PRD 5.1b makes a
   zero invoice legitimate, and nothing below it is. */
function invoiceTotals(lineTotal, creditRequested, creditBalance, kind, value, taxRate) {
  var lines = cents(lineTotal);
  var credit = cents(Math.max(0, Math.min(creditRequested || 0, creditBalance || 0, lines)));
  var sub = cents(lines - credit);
  var off = discountAmount(kind, value, sub);
  var taxable = cents(sub - off);
  var tax = cents(taxable * taxRate);
  return { lines: lines, credit: credit, subtotal: sub, discount: off,
           taxable: taxable, tax: tax, total: cents(taxable + tax),
           creditRefused: cents(Math.max(0, (creditRequested || 0) - credit)) };
}
