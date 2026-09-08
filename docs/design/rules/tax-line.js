/* THE TAX LINE, PRD 5.5, 5.5b and 5.5c. Three states, and they are three rather
   than two on purpose.

   NEVER RECORDED. **No tax figure is drawn at all**, and no total either, because
   nobody yet knows whether any tax applies (Dan, 2026-09-07: "let's not show
   sales tax before we know if we need it"). The screen asks instead, and the
   send is refused until it is answered. This is the same treatment the invoice
   already gives an unpriced draft: a figure that cannot be known is not
   invented, it is asked for.

   An earlier version charged the tax, showed the figure, and offered a "Set it"
   control that silently recorded "not exempt". **A missing status is not the
   same as "not exempt"**, which PRD 5.5 states outright, so that version made
   the exact assumption the refusal exists to prevent.

   NOT EXEMPT. Charged, drawn, nothing said.

   EXEMPT. **The line is still DRAWN, reading $0.00, and names the reason**
   (PRD 5.5c, Dan: "I want to show tax = $0 to the receiving party so they know
   I'm not charging tax"). An invoice that simply omits tax leaves an accounts
   department unable to tell a deliberate exemption from an oversight.

   So the two zeroes on this screen are different things and are drawn
   differently: an exempt client's $0.00 is a MEASURED value, and an unanswered
   status has no value at all. */

var TAX_RATE = 0.08875;

function taxLineFor(status, taxable) {
  if (status === "exempt") {
    return { label: "Sales tax, exempt", amount: 0, drawn: true,
             refusesSend: false, saysWhy: false };
  }
  if (status === "not-exempt") {
    var base = Math.round(taxable * 100) / 100;
    return { label: "Sales tax, 8.875%", amount: Math.round(base * TAX_RATE * 100) / 100,
             drawn: true, refusesSend: false, saysWhy: false };
  }
  return { label: null, amount: null, drawn: false, refusesSend: true, saysWhy: true };
}
