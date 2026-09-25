#!/bin/bash
# A page is measured only once its typefaces have loaded (ovation#543).
#
# Main went red twice on 2026-09-25 on the design harness lift suite, the
# second time with the tool's own report printed (ovation#539): the harness drew
# the invoice list one pixel off, in the widths of words, and two pixels off in
# height, and the rerun passed. Every probe ran the moment the parser reached it,
# which is before the page's first layout, and a face declared with @font-face is
# not even REQUESTED until a layout needs it. So whichever page's embedded
# typeface happened to be ready was measured in it, and the other in a fallback.
#
# That race cannot be staged on demand, but its cause can be measured without
# one: at the moment a probe runs, is every face the page declares loaded? This
# asks exactly that, of a real browser, with the typeface the committed invoice
# design file embeds, read from that file rather than copied (L48).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "design render font tests" 8

require_target "scripts/lib/design_render.py"
require_target "docs/design/invoice.html"
harness_temp_dir WORK

# A LIBRARY THAT CANNOT BE LOADED IS NOT A MISSING BROWSER. Both leave nothing
# to print, and reading the empty answer as "no browser" reported a broken
# renderer as an unmeasurable machine while this suite was being written (L215).
REAL_BROWSER="$(python3 -c 'import sys; sys.path.insert(0, "scripts/lib"); import design_render; print(design_render.find_browser() or "")' 2>&1)"
FOUND_STATUS=$?
if [ "$FOUND_STATUS" -ne 0 ]; then
    echo "FAIL: scripts/lib/design_render.py could not be loaded to look for a browser:"
    printf '%s\n' "$REAL_BROWSER" | tail -3 | sed 's/^/    /'
    exit 1
fi
if [ -z "$REAL_BROWSER" ]; then
    harness_cannot_measure \
        "no headless browser, so no page can be rendered and nothing here proves anything" \
        "npx playwright install chromium, or set OVATION_HEADLESS_BROWSER"
fi

# THE COMMITTED TYPEFACE. The first woff2 the invoice design file embeds, and a
# refusal by name if it no longer embeds one, since a page with no typeface to
# wait for would pass every case below without testing anything (L159).
FACE="$(grep -o -m 1 "url(data:font/woff2;base64,[A-Za-z0-9+/=]*)" docs/design/invoice.html | head -1)"
if [ -z "$FACE" ]; then
    harness_cannot_measure \
        "docs/design/invoice.html embeds no woff2 typeface, so there is nothing to wait for" \
        "point this suite at a design file that embeds one"
fi

page() {  # $1 file, $2 the @font-face src
    cat > "$1" <<PAGE
<!doctype html>
<html><head><meta charset="utf-8">
<style>
@font-face { font-family: "Committed Face"; src: $2 format("woff2"); }
p { font-family: "Committed Face", monospace; font-size: 20px; }
</style></head>
<body><p id="words">Amount due 1,234.50</p></body></html>
PAGE
}
page "$WORK/declared.html" "$FACE"
page "$WORK/broken.html" "url(data:font/woff2;base64,bm90IGEgZm9udA==)"
printf '<!doctype html>\n<html><body><p>no typeface declared</p></body></html>\n' > "$WORK/plain.html"

# What the probe sees at the moment it runs: each declared face's status, and
# whether the words are drawn in the declared face at all.
PROBE='<script>
(function () {
  var faces = [];
  document.fonts.forEach(function (f) { faces.push(f.family + ":" + f.status); });
  var p = document.getElementById("words");
  var drawn = p ? document.fonts.check("20px \"Committed Face\"") : null;
  var pre = document.createElement("pre");
  pre.id = "ovation-probe";
  pre.textContent = JSON.stringify({ faces: faces, drawn: drawn });
  document.body.appendChild(pre);
})();
</script>'

cat > "$WORK/render.py" <<'DRIVER'
import json, os, sys
sys.path.insert(0, "scripts/lib")
from design_render import CannotMeasure, open_browser
try:
    with open_browser() as browser:
        print(json.dumps(browser.render(sys.argv[1], os.environ["PROBE"]), sort_keys=True))
except CannotMeasure as refusal:
    print("CANNOT MEASURE: %s" % refusal)
    sys.exit(3)
DRIVER
render() { PROBE="$PROBE" HOME="$WORK/home" OVATION_RENDER_RESTART_LOG="$WORK/restarts.tsv" \
    python3 "$WORK/render.py" "$1" 2>&1; }

OUT="$(render "$WORK/declared.html")"; RC=$?
check "a page declaring the committed typeface renders" "$RC" "0"
check "and when its probe runs, every face the page declares has loaded" \
    "$(python3 -c 'import json,sys; r=json.loads(sys.stdin.read()); print(",".join(r["faces"]))' <<< "$OUT" 2>&1)" \
    'Committed Face:loaded'
check "and the words are measurable in that face, not a fallback" \
    "$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["drawn"])' <<< "$OUT" 2>&1)" "True"

# THE CONTROL: a page with no typeface is not held up waiting for one.
OUT="$(render "$WORK/plain.html")"; RC=$?
check "a page declaring no typeface renders as it always did" \
    "$RC:$(python3 -c 'import json,sys; print(len(json.loads(sys.stdin.read())["faces"]))' <<< "$OUT" 2>&1)" "0:0"

# A PROBE THAT WAITS FOR THE PAGE'S LOAD EVENT still runs. Held back until the
# faces load, a probe arrives after that event has fired, and one that listens
# for it would wait for ever: the token check does exactly this, and it measured
# nothing on every page until this case existed. Each listener is given the
# event it asked for, on the page it would have seen it on.
PROBE_ON_LOAD='<script>
window.addEventListener("load", function (event) {
  document.addEventListener("DOMContentLoaded", function () {}, false);
  var pre = document.createElement("pre");
  pre.id = "ovation-probe";
  pre.textContent = JSON.stringify({ event: event.type, ready: document.readyState });
  document.body.appendChild(pre);
});
</script>'
OUT="$(PROBE="$PROBE_ON_LOAD" HOME="$WORK/home" OVATION_RENDER_RESTART_LOG="$WORK/restarts.tsv" \
    python3 "$WORK/render.py" "$WORK/declared.html" 2>&1)"; RC=$?
check "a probe that waits for the load event still runs, and is handed that event" \
    "$RC:$OUT" '0:{"event": "load", "ready": "complete"}'

# A TYPEFACE THAT CANNOT LOAD is a refusal, by name, rather than a measurement
# of a fallback reported as the design, which is the defect itself (L11).
OUT="$(render "$WORK/broken.html")"; RC=$?
check "a page whose typeface cannot load is not measured" "$RC" "3"
check "and the refusal names the face that did not load" \
    "$(grep -c "^CANNOT MEASURE: .*Committed Face" <<< "$OUT")" "1"
check "and says the measurement would have been of a fallback" \
    "$(grep -c "fallback" <<< "$OUT")" "1"

harness_end
