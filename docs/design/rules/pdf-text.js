/* HOW MONEY AND HOURS ARE WRITTEN ON THE INVOICE PDF (ovation#167, PRD 50c).
   The page a client receives writes a dollar sign and a comma between thousands.
   The invoice screen writes its figures without either, on purpose, with a
   formatter of its own, so this rule belongs to the PDF alone.
   ONE SET OF CASES FOR BOTH IMPLEMENTATIONS. pdf-text.cases.json is read by
   scripts/test-design-rules.sh against this rule and by
   OvationTests/PDFTextTests.swift against the app, because two implementations
   each tested by cases of their own agree on the day they are written and then
   drift, and the page the client receives is where it would show (L26).
   HOURS KEEP ONE DECIMAL UNLESS THE VALUE NEEDS TWO. "1.0 hr" and "1.5 hrs" are
   the settled spelling. A quarter hour written to one decimal printed 1.3, so
   the hours times the rate stopped adding up to the amount beside them, and
   PRD 50c exists so a client can reconstruct every figure. */
function money(n) {
  var s = Math.abs(n).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return (n < 0 ? "-$" : "$") + s;
}

function hours(h) {
  var hundredths = Math.round(h * 100);
  var written = hundredths % 10 === 0 ? h.toFixed(1) : h.toFixed(2);
  return written + (hundredths === 100 ? " hr" : " hrs");
}
