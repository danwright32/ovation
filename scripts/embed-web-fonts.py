#!/usr/bin/env python3
"""Turn a Google Fonts CSS URL into an `@font-face` block with the faces inlined.

ovation#115. Every committed design file embeds its typefaces as base64 so it
needs no network (ovation#114 is the guard that keeps that true). That embedding
had been done by hand twice, once for `invoice-list.html` and once for the
invoice PDF rounds, and is due at least three more times.

IT IS NOT A ONE LINE JOB, which is the whole reason it is a script. Doing it
correctly means taking the LATIN subset rather than a whole family (the
Merriweather variable file is 4.4MB raw against 219KB for the latin subsets of
both brand faces), noticing when a variable font is served as ONE file covering
every weight so it is embedded once with a weight range rather than four times,
and REFUSING rather than emitting a face that could not be verified. A face that
quietly fails to embed falls back to a system font and the page still looks
finished, which is exactly the failure the design record exists to prevent, and
it is invisible on any machine with a network.

FETCHING IS INJECTABLE AND OFFLINE IS ENFORCED, not asked for. With
OVATION_FONT_OFFLINE=1 any URL that is not a local file is REFUSED rather than
fetched, so the suite cannot reach the network by writing the wrong fixture
(L2, L196). A seam a test is merely expected to set is not isolation.

EVERY REFUSAL IS ITS OWN OUTCOME (L11), because they need different work: a
family with no latin subset is the wrong URL, a payload that is not woff2 is a
bad download or a changed service, and one family, weight and style served two
different files is a request that has to be narrowed.

Usage:
    embed-web-fonts.py <google-fonts-css-url-or-local-css-path>

Exit codes:
    0  every face was verified and embedded
    1  a face could not be verified, so nothing was emitted
    2  nothing could be read at all
"""
import base64
import os
import re
import sys
import urllib.request

# Google serves woff2 only to a user agent it believes can take it. Asked as an
# older browser it returns truetype, which is several times the size and would be
# embedded without complaint.
WOFF2_CAPABLE = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                 "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36")

# The subset each block belongs to is in a comment ABOVE it. It is the only place
# the subset is named, so a parser that reads only the blocks cannot tell latin
# from cyrillic and embeds every alphabet in the response.
SUBSET_COMMENT = re.compile(r"/\*\s*([a-z0-9\-\[\]]+)\s*\*/", re.IGNORECASE)
FACE_BLOCK = re.compile(r"@font-face\s*\{(.*?)\}", re.DOTALL)
DECLARATION = re.compile(r"([a-z\-]+)\s*:\s*([^;]+);", re.IGNORECASE)
SRC_URL = re.compile(r"url\(\s*['\"]?([^)'\"]+)['\"]?\s*\)")

# The first four bytes of a woff2 file. Checked rather than trusted, because the
# whole point of this script is refusing a face it could not verify.
WOFF2_MAGIC = b"wOF2"


class Refusal(Exception):
    pass


def is_local(url):
    return not re.match(r"^[a-z][a-z0-9+.\-]*://", url, re.IGNORECASE)


def read(url):
    """Bytes at a URL, or a refusal. Local paths are read from disk."""
    if is_local(url):
        if not os.path.isfile(url):
            raise Refusal(f"nothing to read at {url}")
        with open(url, "rb") as handle:
            return handle.read()
    if os.environ.get("OVATION_FONT_OFFLINE") == "1":
        raise Refusal(
            f"refusing to fetch {url}: OVATION_FONT_OFFLINE is set, and a run that "
            "reaches the network is not the run that was asked for")
    request = urllib.request.Request(url, headers={"User-Agent": WOFF2_CAPABLE})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def faces_in(css, wanted_subset="latin"):
    """Every latin face the stylesheet declares, in the order written.

    The subset comes from the comment above each block, so a response carrying
    cyrillic, greek and latin yields only the latin ones. Without that the
    embedded payload is several alphabets nobody asked for, and the page still
    looks correct.
    """
    found = []
    for block in FACE_BLOCK.finditer(css):
        preceding = css[:block.start()]
        comments = SUBSET_COMMENT.findall(preceding)
        subset = comments[-1].lower() if comments else None
        if subset != wanted_subset:
            continue
        declarations = {name.lower(): value.strip()
                        for name, value in DECLARATION.findall(block.group(1))}
        source = SRC_URL.search(declarations.get("src", ""))
        if not source:
            raise Refusal("a latin @font-face block declares no url to fetch")
        found.append({
            "family": declarations.get("font-family", "").strip("'\" "),
            "style": declarations.get("font-style", "normal"),
            "weight": declarations.get("font-weight", "400"),
            "display": declarations.get("font-display"),
            "unicode_range": declarations.get("unicode-range"),
            "url": source.group(1),
        })
    if not found:
        raise Refusal(
            f"no {wanted_subset} subset in this stylesheet. Either the URL names a "
            "family that has none, or the response was not the CSS that was asked "
            "for. Nothing was emitted rather than embedding another alphabet.")
    return found


def collapse(faces):
    """One entry per FILE, not per declared weight.

    A variable font is served as ONE file covering a weight range, declared once
    by Google but easy to request four times. Embedding it per weight would carry
    the same bytes four times over. Faces sharing a url are therefore folded into
    one, and the resulting weight is the range they span.

    The other direction is a REFUSAL: one family, weight and style pointing at two
    DIFFERENT files means the request asked for something this cannot express, and
    guessing which file wins is how a page ends up in a face nobody chose.
    """
    by_url = {}
    order = []
    for face in faces:
        key = (face["family"], face["style"], face["url"])
        if key not in by_url:
            by_url[key] = dict(face)
            by_url[key]["weights"] = []
            order.append(key)
        by_url[key]["weights"].append(face["weight"])

    seen = {}
    for key in order:
        face = by_url[key]
        for weight in face["weights"]:
            identity = (face["family"], face["style"], weight)
            if identity in seen and seen[identity] != face["url"]:
                raise Refusal(
                    f"{face['family']} {face['style']} {weight} is served by two "
                    "different files. Narrow the request rather than choosing one, "
                    "because a page drawn in the file that happened to win is a page "
                    "in a face nobody chose.")
            seen[identity] = face["url"]
    return [by_url[key] for key in order]


def payload(face):
    """The verified bytes of one face, base64 encoded."""
    data = read(face["url"])
    if data[:4] != WOFF2_MAGIC:
        raise Refusal(
            f"{face['family']} {face['weight']} is not woff2: it begins "
            f"{data[:4]!r} rather than {WOFF2_MAGIC!r}. A face that quietly fails to "
            "embed falls back to a system font and the page still looks finished, "
            "so it is refused rather than emitted.")
    return base64.b64encode(data).decode("ascii"), len(data)


def render(face, encoded):
    weights = face["weights"]
    weight = weights[0] if len(set(weights)) == 1 else f"{weights[0]} {weights[-1]}"
    lines = ["@font-face {",
             f"  font-family: '{face['family']}';",
             f"  font-style: {face['style']};",
             f"  font-weight: {weight};"]
    if face.get("display"):
        lines.append(f"  font-display: {face['display']};")
    lines.append(f"  src: url(data:font/woff2;base64,{encoded}) format('woff2');")
    if face.get("unicode_range"):
        lines.append(f"  unicode-range: {face['unicode_range']};")
    lines.append("}")
    return "\n".join(lines)


def main(argv):
    if len(argv) != 1:
        print(__doc__.strip().splitlines()[-4].strip())
        return 2

    try:
        css = read(argv[0]).decode("utf-8", errors="replace")
    except Refusal as refusal:
        print(f"CANNOT READ: {refusal}")
        return 2

    try:
        faces = collapse(faces_in(css))
        rendered = []
        total = 0
        for face in faces:
            encoded, size = payload(face)
            rendered.append(render(face, encoded))
            total += size
    except Refusal as refusal:
        print(f"REFUSED: {refusal}")
        return 1

    print("\n".join(rendered))
    # The report goes to stderr so the block on stdout can be pasted or piped
    # without it. Sizes are named because the reason to take a subset is a size
    # and a number nobody sees is a decision nobody can check.
    print(f"{len(faces)} face(s) embedded, {total} raw byte(s), "
          f"{int(total * 4 / 3)} encoded.", file=sys.stderr)
    for face in faces:
        print(f"  {face['family']} {face['style']} "
              f"{'/'.join(sorted(set(face['weights'])))}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
