"""How review-send.html's embedded copy of the invoice PDF design is built.

ovation#167. review-send.html carries the whole invoice PDF design as one escaped
string, PDF_PAGE, and hands it to a frame, so its preview runs that design's own
code (PRD 10c). Nothing compared the two, and on 2026-09-14 the copy was an older
page: it still carried the builder that blanks the page on a line with no hours,
fixed in invoice-pdf.html by ovation#170, and a phone number the design had since
dropped. Two copies of one thing with nothing comparing them is L370.

ONE DEFINITION, READ BY THE CHECKER AND BY THE WRITER. Were each to build the page
its own way, the checker would pass pages the writer could not produce and the
writer would write pages the checker refuses (L70).

WHAT THE PAGE IS, IN ORDER:
    the design's head, up to its stylesheet's end, with the preview's own title
    and without any declaration line (a declaration belongs to the file that
    makes it, and carried into the host it reads as the host declaring it)
    one rule so the page sits in the frame with no margin of its own
    the design's script, up to the line where its fixture chooser begins
    the host's OWN invoice, kept from the page already there, because it is what
    the preview draws and it exists nowhere else

EVERY ANCHOR IS FOUND EXACTLY ONCE OR REFUSED. An operation that finds its place
by matching text reports success when it matches nothing, and the next step acts
on a page nobody built (L100).

Sourced by scripts/check-design-embedded-page.sh and
scripts/write-design-embedded-page.sh. Never run on its own. It never prints the
page or any part of it, only file names and what could not be found.
"""
import json
import os

HOST = "review-send.html"
SOURCE = "invoice-pdf.html"
VARIABLE = "var PDF_PAGE = "
TITLE = "<title>The invoice that ships</title>"
CUT = 'var bar = document.getElementById("fixbar");'
TAIL_START = "var CEDAR = {"
FRAME_RULE = "html, body { margin: 0; padding: 0; background: transparent; }"
MARKERS = ("NOT SHELLED:", "NOT RENDERED:")


class Refusal(Exception):
    """An anchor could not be found, so nothing may be built or written."""


def find_literal(host_text):
    """Where the embedded page sits in the host, and the page decoded.

    Returns (None, lines, None) when the host carries no embedded page at all,
    which is nothing to compare rather than a refusal.
    """
    lines = host_text.split("\n")
    found = [i for i, line in enumerate(lines) if line.startswith(VARIABLE)]
    if not found:
        return None, lines, None
    if len(found) > 1:
        raise Refusal("%s carries PDF_PAGE %d times, and only one can be the page"
                      % (HOST, len(found)))
    raw = lines[found[0]][len(VARIABLE):].rstrip()
    if not raw.endswith(";"):
        raise Refusal("the PDF_PAGE line in %s does not end its statement" % HOST)
    try:
        page = json.loads(raw[:-1])
    except ValueError:
        raise Refusal("the PDF_PAGE string in %s cannot be decoded" % HOST)
    return found[0], lines, page


def tail_of(page):
    """The host's own invoice and the call that draws it, from the page there now."""
    start = page.find(TAIL_START)
    end = page.rfind("</script>")
    if start < 0:
        raise Refusal("the embedded page carries no preview invoice (%s), so it cannot be kept"
                      % TAIL_START.rstrip(" {"))
    if end < start:
        raise Refusal("the embedded page's preview invoice is not inside its script")
    return page[start:end].rstrip("\n")


def build(source_text, tail):
    """The embedded page, from the design file and the host's own invoice."""
    lines = source_text.split("\n")

    def exactly_once(exact, what):
        hits = [i for i, line in enumerate(lines) if line.strip() == exact]
        if len(hits) != 1:
            raise Refusal("%s: %s was found %d times, where it must be found once"
                          % (SOURCE, what, len(hits)))
        return hits[0]

    style_end = exactly_once("</style>", "the end of the stylesheet")
    script_start = exactly_once("<script>", "the start of the script")
    cut = exactly_once(CUT, "the line where the fixture chooser begins")
    if not style_end < script_start < cut:
        raise Refusal("%s: the stylesheet, the script and the chooser are not in that order"
                      % SOURCE)
    titles = [i for i, line in enumerate(lines[:style_end]) if line.startswith("<title>")]
    if len(titles) != 1:
        raise Refusal("%s: the head carries %d titles, where it must carry one"
                      % (SOURCE, len(titles)))

    head = [TITLE if line.startswith("<title>") else line
            for line in lines[:style_end]
            if not any(marker in line for marker in MARKERS)]
    script = lines[script_start + 1:cut]
    page = (head
            + [FRAME_RULE, "</style>", "</head>", "<body>", "<script>"]
            + script
            + [tail, "</script>", "</body>", "</html>"])
    return "\n".join(page) + "\n"


def encode(page):
    """The host's line for a page. A closing tag inside the string is escaped, or
    it would end the host's own script where it stands."""
    return VARIABLE + json.dumps(page, ensure_ascii=False).replace("</", "<\\/") + ";"


def judge(root):
    """What the record comes to: a state, a sentence, and the host's new text.

    States: "in step", "drifted", "nothing" (no host, no design or no embedded
    page, so nothing could be compared) and "refused" (an anchor is lost).
    """
    host_path = os.path.join(root, HOST)
    source_path = os.path.join(root, SOURCE)
    if not os.path.isfile(host_path) or not os.path.isfile(source_path):
        return ("nothing", "%s or %s is not in %s, so nothing was compared"
                % (HOST, SOURCE, root), None)
    host_text = open(host_path, encoding="utf-8").read()
    try:
        index, lines, page = find_literal(host_text)
        if index is None:
            return ("nothing", "%s carries no embedded page, so nothing was compared" % HOST,
                    None)
        expected = build(open(source_path, encoding="utf-8").read(), tail_of(page))
    except Refusal as refusal:
        return ("refused", str(refusal), None)
    if page == expected:
        return ("in step", "%s carries %s as it stands" % (HOST, SOURCE), None)
    lines[index] = encode(expected)
    return ("drifted", "%s carries a copy of %s that differs from it" % (HOST, SOURCE),
            "\n".join(lines))
