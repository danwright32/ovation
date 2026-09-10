#!/usr/bin/env python3
"""Render the committed picture of a design file, and say when it is stale.

    build-design-screenshot.sh [--check]

ovation#178. `docs/design/invoice-list.png` is described in the design README as
a rendering of the design file at 2x, framed to the window. No script produced
it. On 2026-09-09 it silently described a screen FOUR settled rounds out of
date, and it was noticed only because the fixture happened to change;
regenerating it meant an ad hoc headless capture plus a crop with hand typed
pixel offsets, which is the same fragility again.

A derived artifact committed beside its source is a standing claim that it is
current, and nothing enforced that claim (L422). This one is the copy a person
looks at when opening the page is inconvenient, so a stale one misinforms
exactly the reader who did not open the real file.

THE CROP COMES FROM THE PAGE, not from typed offsets. The `.screen` rect is read
out of the rendering itself, so a screen that changes size is framed correctly
without anybody adjusting a number, and a number nobody can re-derive cannot go
wrong quietly.

WHAT `--check` COMPARES, and why it is not the pixels. Two machines do not
produce identical PNGs: font rasterisation, the browser's version and the
platform all move bytes without moving anything a person would call a
difference, so a byte comparison would be red on every machine but the one that
last rendered it (L376). It compares the LAYOUT instead: a hash over every
element inside the screen, its tag, its classes and its box, recorded in a
sidecar beside the PNG. That is exactly the claim the PNG makes, it does not
move when the record's prose around it is edited, and it moves the moment the
screen is drawn differently.

IT ALSO CHECKS THE SIZE, because the sidecar and the PNG are two files and
nothing else would notice one of them being replaced by hand.

Exit codes, one per outcome (L11):

    0  rendered, or --check and the picture is current
    1  --check and the picture is stale
    2  used wrongly, or nothing to render
    3  cannot measure: no headless browser, or no Pillow to crop with

Seams: OVATION_DESIGN_ROOT, OVATION_HEADLESS_BROWSER.
"""
import hashlib
import json
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

from design_render import CannotMeasure, NO_BROWSER, find_browser, render  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.environ.get("OVATION_DESIGN_ROOT") or os.path.join(REPO, "docs", "design")

# THE ONE FILE THAT HAS A PICTURE, named here rather than discovered, because a
# picture is a deliberate thing to commit and a scan over the folder would make
# a new design file silently owe one.
SUBJECT = "invoice-list.html"
PICTURE = "invoice-list.png"
SIDECAR = "invoice-list.png.layout"

# Twice actual size, which is what the README says it is. The window is tall
# enough to hold the record's prose above the screen as well as the screen, and
# the crop takes only the screen.
#
# THE HEIGHT IS HEADROOM, NOT A MEASUREMENT, and it has to be re-checked when the
# screen grows. It was 1600 until ovation#190 put a group of two invoices and a
# band at the top of the list: the committed file still fitted, and the SUITE's
# own case, which makes every row 10px taller to prove a changed screen is caught,
# did not. The tool refused with CANNOT MEASURE, which is the right answer and
# names this constant as the remedy. Anything that adds rows to the list will
# spend this headroom again.
SCALE = 2
WINDOW = (1440, 1900)

PROBE = r"""
<script>
window.addEventListener("load", function () {
  var screen = document.querySelector(".screen");
  var result = { found: !!screen };
  if (screen) {
    var box = screen.getBoundingClientRect();
    result.rect = [box.x, box.y, box.width, box.height];
    var parts = [];
    screen.querySelectorAll("*").forEach(function (e) {
      var r = e.getBoundingClientRect();
      parts.push([e.tagName, e.getAttribute("class") || "",
                  Math.round(r.x - box.x), Math.round(r.y - box.y),
                  Math.round(r.width), Math.round(r.height)]);
    });
    result.layout = parts;
  }
  var pre = document.createElement("pre");
  pre.id = "ovation-probe";
  pre.textContent = JSON.stringify(result);
  document.body.appendChild(pre);
});
</script>
"""


def measure(browser, path):
    """The screen's rect and a hash of everything drawn inside it."""
    report = render(browser, path, PROBE,
                    window="%d,%d" % WINDOW, budget=6000)
    if not report.get("found"):
        raise CannotMeasure("%s draws no `.screen`, so there is nothing to frame"
                            % os.path.basename(path))
    shape = json.dumps(report["layout"], separators=(",", ":"), sort_keys=False)
    return report["rect"], hashlib.sha256(shape.encode("utf-8")).hexdigest(), len(report["layout"])


def capture(browser, path, rect, into):
    """The framed picture, at SCALE, cropped to the rect the page reported."""
    try:
        from PIL import Image
    except ImportError:
        raise CannotMeasure(
            "Pillow is not installed, so the rendering cannot be cropped to the "
            "screen. Install it with: python3 -m pip install Pillow")
    holder = tempfile.mkdtemp(prefix="ovation-shot-")
    whole = os.path.join(holder, "whole.png")
    done = subprocess.run(
        [browser, "--headless", "--disable-gpu", "--hide-scrollbars",
         "--virtual-time-budget=6000",
         "--force-device-scale-factor=%d" % SCALE,
         "--window-size=%d,%d" % WINDOW,
         "--screenshot=" + whole, "file://" + os.path.abspath(path)]
        + (["--no-sandbox", "--disable-dev-shm-usage"]
           if sys.platform.startswith("linux") else []),
        capture_output=True, text=True, timeout=120)
    if not os.path.isfile(whole):
        said = " ".join((done.stderr or "").split())[:300] or "and said nothing"
        raise CannotMeasure("the browser wrote no screenshot (exit %d). It said: %s"
                            % (done.returncode, said))
    x, y, w, h = rect
    with Image.open(whole) as image:
        box = (round(x * SCALE), round(y * SCALE),
               round((x + w) * SCALE), round((y + h) * SCALE))
        if box[2] > image.width or box[3] > image.height:
            raise CannotMeasure(
                "the screen runs past the window that was rendered: it needs "
                "%dx%d and the picture is %dx%d. Widen WINDOW rather than "
                "cropping to something smaller than the screen."
                % (box[2], box[3], image.width, image.height))
        image.crop(box).save(into)
    return box[2] - box[0], box[3] - box[1]


def main(argv):
    checking = "--check" in argv[1:]
    if [a for a in argv[1:] if a != "--check"]:
        print(__doc__.strip().splitlines()[2].strip())
        return 2

    path = os.path.join(ROOT, SUBJECT)
    picture = os.path.join(ROOT, PICTURE)
    sidecar = os.path.join(ROOT, SIDECAR)
    if not os.path.isfile(path):
        print("CANNOT MEASURE: no %s, so there is nothing to render." % path)
        return 2

    try:
        browser = find_browser()
    except CannotMeasure as err:
        print("CANNOT MEASURE: %s" % err)
        return 3
    if not browser:
        print(NO_BROWSER)
        return 3

    try:
        rect, layout, elements = measure(browser, path)
    except CannotMeasure as err:
        print("CANNOT MEASURE: %s" % err)
        return 3

    if checking:
        if not os.path.isfile(picture):
            print("STALE: %s is not there at all, though the record says it is."
                  % PICTURE)
            return 1
        if not os.path.isfile(sidecar):
            print("STALE: %s has no %s beside it, so nothing records which "
                  "layout it was rendered from and its currency cannot be "
                  "judged either way." % (PICTURE, SIDECAR))
            return 1
        recorded = json.loads(open(sidecar, encoding="utf-8").read())
        if recorded.get("layout") != layout:
            print("STALE: %s was rendered from a different layout than %s draws "
                  "now.\n  recorded  %s\n  drawn     %s\n  %d element(s) inside "
                  "the screen. Re-render with: scripts/build-design-screenshot.sh"
                  % (PICTURE, SUBJECT, recorded.get("layout"), layout, elements))
            return 1
        try:
            from PIL import Image
            with Image.open(picture) as image:
                size = list(image.size)
        except ImportError:
            print("CANNOT MEASURE: Pillow is not installed, so the picture's own "
                  "size could not be read.")
            return 3
        if size != recorded.get("size"):
            print("STALE: %s is %dx%d and the sidecar records %s, so one of the "
                  "two was replaced without the other." % (PICTURE, size[0], size[1],
                                                           recorded.get("size")))
            return 1
        print("OK: %s is the layout %s draws, %d element(s) inside the screen, "
              "at %dx%d." % (PICTURE, SUBJECT, elements, size[0], size[1]))
        return 0

    try:
        width, height = capture(browser, path, rect, picture)
    except CannotMeasure as err:
        print("CANNOT MEASURE: %s" % err)
        return 3
    with open(sidecar, "w", encoding="utf-8") as handle:
        json.dump({"layout": layout, "size": [width, height], "scale": SCALE},
                  handle, indent=1)
        handle.write("\n")
    print("Rendered %s at %dx%d, framed to the screen %s draws, %d element(s) "
          "inside it." % (PICTURE, width, height, SUBJECT, elements))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
