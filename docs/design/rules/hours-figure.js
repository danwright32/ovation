/* THE NUMBER A DURATION IS WRITTEN AS, ON THE SCREEN AND ON THE PDF (Dan,
   2026-09-19, ovation#322, PRD 51k; held together by ovation#413).

   ONE DECIMAL UNLESS THE QUARTER HOUR NEEDS TWO, so 1.5 and 1.25 rather than
   1.50 and 1.3. The invoice screen wrote `toFixed(2)` in two places while the
   PDF the client receives wrote its own rule, and Dan reads the screen and then
   the PDF of one invoice one after the other, so one fact in two spellings reads
   as two different numbers, which a unit or a qualifier cannot separate (L118).
   A quarter hour written to one decimal printed 1.3, and the hours times the rate
   stopped adding up to the amount beside them (PRD 50c).

   THE UNIT IS NOT PART OF THE FIGURE. The screen's column is already headed
   Hours, so a unit on every row would be the same fact twice on one surface
   (L605), chosen with all three spellings drawn. The PDF adds its unit in
   `hours` (rules/pdf-text.js), because a client reads one line there without a
   column header above it.

   ONE RULE, TWO SCREENS, so each is held to it on its own rather than the
   better copy answering for both:
   CARRIED BY: invoice.html, invoice-pdf.html */
function hoursFigure(h) {
  var hundredths = Math.round(h * 100);
  return hundredths % 10 === 0 ? h.toFixed(1) : h.toFixed(2);
}
