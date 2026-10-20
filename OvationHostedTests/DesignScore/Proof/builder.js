// The proof screen's builder (ovation#760): each band the fixture names, top to
// bottom, at its own height and colour. Colour only, because text drawn by Chrome
// and by SwiftUI differs at the glyph edges however exactly it is built.
function buildScreen(variant) {
  var root = document.createElement("div");
  window.DESIGN_FIXTURE.bands.forEach(function (band) {
    var row = document.createElement("div");
    row.dataset.band = band.name;
    row.style.height = band.height + "px";
    row.style.background = "rgb(" + band.red + ", " + band.green + ", " + band.blue + ")";
    root.appendChild(row);
  });
  return root;
}
