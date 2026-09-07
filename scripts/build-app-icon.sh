#!/bin/bash
# Derive Ovation's AppIcon asset catalog from the source artwork.
#
# ovation#18. The source art is icon/ovation-app-icon.png, a full bleed 1254px
# square with hard corners and no transparency. macOS does NOT mask an app icon
# for you the way iOS does: whatever is in the catalog is what appears in the
# Dock, so a full bleed square ships as a hard cornered square sitting among
# rounded ones. The masking and the inset below are that translation, and they
# are a SCRIPT rather than a one off export because doing by hand what a tool
# does performs the visible change and silently omits the tool's other writes
# (L379). Run it again whenever the artwork changes.
#
# THE GEOMETRY IS APPLE'S, NOT CHOSEN HERE. macOS Big Sur onwards draws an app
# icon as a rounded square occupying 824 of a 1024 point canvas, centred, corner
# radius 185.4. The corner is a CONTINUOUS curve, not a circular arc, which is
# why this uses a superellipse of exponent 5 rather than a plain rounded
# rectangle: at this ratio (185.4 / 824 = 0.225) the two differ visibly at the
# large sizes, and a circular arc reads as the wrong shape beside every other
# icon in the Dock.
#
# WHAT IS DELIBERATELY NOT DONE HERE. No drop shadow is composited in. Apple's
# own template carries a subtle one, and adding a fabricated one would be
# inventing a design decision inside a build script, where nobody would ever
# find it to argue with. If Ovation's icon should carry a shadow, that belongs
# in the artwork or in a decision recorded in docs/design/README.md.
#
# The catalog it writes is COMMITTED. This script is how it is reproduced, not a
# build step: nothing in the Xcode build runs it, so a machine without Pillow
# can still build the app.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

SOURCE="icon/ovation-app-icon.png"
CATALOG="Ovation/Assets.xcassets"
ICONSET="$CATALOG/AppIcon.appiconset"

if [ ! -f "$SOURCE" ]; then
    echo "REFUSED: the source artwork is not at $SOURCE."
    echo "         Nothing was written. This script cannot invent the icon."
    exit 1
fi

# A missing library is REFUSED with the command that fixes it, rather than
# leaving the reader facing a Python traceback about an import (L148, L406).
if ! python3 -c 'import PIL' 2>/dev/null; then
    echo "REFUSED: this script needs Pillow to mask and resample the artwork."
    echo "         Install it, then run this again:"
    echo "             python3 -m pip install --user Pillow"
    echo "         Nothing was written. The committed catalog at $ICONSET is untouched."
    exit 1
fi

mkdir -p "$ICONSET" || exit 1

python3 - "$SOURCE" "$ICONSET" <<'PY'
import json
import sys

from PIL import Image

source_path, iconset = sys.argv[1], sys.argv[2]

CANVAS = 1024      # Apple's macOS icon canvas
BODY = 824         # the rounded square inside it
EXPONENT = 5       # the superellipse that matches Apple's continuous corner
SUPERSAMPLE = 4    # drawn large and reduced, because the mask is computed per
                   # pixel and a hard threshold at final size gives a jagged edge

def squircle_mask(size, exponent, supersample):
    """A superellipse mask, antialiased by drawing it big and reducing it."""
    big = size * supersample
    mask = Image.new("L", (big, big), 0)
    pixels = mask.load()
    half = big / 2.0
    for y in range(big):
        # Solve |x|^n + |y|^n = 1 for x at this row rather than testing every
        # pixel: it is the same shape and it is linear in the height instead of
        # quadratic, which matters at 4096 across.
        ny = abs((y + 0.5 - half) / half)
        if ny >= 1.0:
            continue
        nx = (1.0 - ny ** exponent) ** (1.0 / exponent)
        span = nx * half
        left = int(round(half - span))
        right = int(round(half + span))
        for x in range(max(0, left), min(big, right)):
            pixels[x, y] = 255
    return mask.resize((size, size), Image.LANCZOS)

art = Image.open(source_path).convert("RGB").resize((BODY, BODY), Image.LANCZOS)
body = Image.new("RGBA", (BODY, BODY))
body.paste(art, (0, 0))
body.putalpha(squircle_mask(BODY, EXPONENT, SUPERSAMPLE))

master = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
inset = (CANVAS - BODY) // 2
master.paste(body, (inset, inset), body)

# Every size macOS actually asks a Mac app for. The 1x and 2x entries that land
# on the same pixel count are still written as separate files, because the
# catalog compiler pairs each entry with its own filename and a shared one makes
# a later size change silently apply to two entries at once.
SIZES = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

images = []
for points, scale in SIZES:
    pixels = points * scale
    name = "icon_%dx%d%s.png" % (points, points, "@2x" if scale == 2 else "")
    master.resize((pixels, pixels), Image.LANCZOS).save("%s/%s" % (iconset, name))
    images.append({
        "size": "%dx%d" % (points, points),
        "idiom": "mac",
        "filename": name,
        "scale": "%dx" % scale,
    })

with open("%s/Contents.json" % iconset, "w") as handle:
    json.dump(
        {"images": images, "info": {"version": 1, "author": "xcode"}},
        handle,
        indent=2,
    )
    handle.write("\n")

print("wrote %d representations plus Contents.json to %s" % (len(images), iconset))
PY
STATUS=$?

if [ "$STATUS" != "0" ]; then
    echo "REFUSED: the icon was not generated. $ICONSET may be half written."
    exit "$STATUS"
fi

# Say what actually landed, rather than exiting 0 in silence: a run that wrote
# nothing and a run that wrote everything must not be the same event (L98).
echo "AppIcon catalog rebuilt from $SOURCE:"
ls -1 "$ICONSET" | sed 's/^/    /'
