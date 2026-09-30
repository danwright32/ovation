#!/usr/bin/env python3
"""Probe 4b: what a single on device read of a PHOTOGRAPHED receipt yields.

ovation#74. A photographed receipt has no text layer, so the two reader
comparison of ovation#73 cannot run on it by construction. This probe measures
what is left instead (PRD 18, 18a, 18d, 5.18a): what Vision reads as the amount,
the date and the vendor, with its own confidence and its alternative readings;
whether the receipt's own arithmetic can be checked (the line items against the
subtotal, and subtotal plus tax against the total) and whether it holds; and
whether a barcode or QR code is present at all, since that is the one check
genuinely independent of the text reader where it exists (L543).

IT IS A PILOT UNTIL THERE ARE 20 RECEIPTS, and it says so in its own output.
Dan decided on 2026-09-29 to run it on the four receipts he had as a first look
that can catch a broken approach early, with the pass or fail verdict against
the agreed marks given only at 20 or more. It never judges correctness either:
whether a reading is RIGHT is decided by Dan, against the receipt in his hand,
from the results page this writes. A confidently wrong fill is the failure the
agreed marks forbid, and only a person holding the receipt can see one.

PRINTS COUNTS ONLY. Never a vendor, an amount, a date or a filename, because
this reads Dan's real receipts and printed output reaches transcripts by a route
no file scanner inspects (docs/PRIVACY-FLOOR.md, L222). Everything a person has
to read by eye goes into the results file, which is written into the custody
folder, readable by Dan alone, and refused a home inside any git repository.

THE READER IS PINNED AND RECORDED. Vision is part of the operating system and
changes under a system update with no code change here, so every run records
the OS version and the request revisions it read with (PRD 18c).

Usage:
    measure-receipt-reads.py [--folder <receipts>] [--results <folder>]
    measure-receipt-reads.py --summarise <results-....json>

Defaults: the receipts in the custody folder's receipt-sample, and results into
the custody folder's receipt-probe.

Exit codes: 0 measured, 1 refused (each refusal says which), 2 CANNOT MEASURE
(not a Mac, or no Swift compiler), 64 a usage error.
"""
import datetime
import hashlib
import html
import json
import math
import os
import platform
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import urllib.parse
from decimal import Decimal

CUSTODY = os.path.expanduser("~/Library/Application Support/Ovation/custody")
DEFAULT_FOLDER = os.path.join(CUSTODY, "receipt-sample")
DEFAULT_RESULTS = os.path.join(CUSTODY, "receipt-probe")
READER_SOURCE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "receipt-reader.swift")

# The size of sample the verdict waits for, from Dan's decision on ovation#74
# (2026-09-29). Below it every run is a pilot.
VERDICT_SAMPLE = 20

# A receipt counts as TURNED when its text runs more than this far from
# upright. Photographs are routinely skewed by a few degrees, which is not what
# this count is for: it asks how often a receipt arrives sideways or upside down.
TURNED_BEYOND_DEGREES = 45

MONEY = re.compile(r"(?<![\d.,])(-)?\$?\s?(\d{1,3}(?:,\d{3})+|\d+)\.(\d{2})(?!\d)")
MONTHS = r"(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?"
DATES = [
    re.compile(r"(?<!\d)\d{4}-\d{1,2}-\d{1,2}(?!\d)"),
    re.compile(r"(?<!\d)\d{1,2}[/.\-]\d{1,2}[/.\-](?:\d{4}|\d{2})(?!\d)"),
    re.compile(r"\b" + MONTHS + r"\s+\d{1,2},?\s+\d{4}\b", re.IGNORECASE),
    re.compile(r"\b\d{1,2}\s+" + MONTHS + r",?\s+\d{4}\b", re.IGNORECASE),
]

# What a labelled line with an amount on it IS, tried in this order, because
# "TOTAL TAX" is a tax line and "SUBTOTAL" contains "total". Anything that
# matches none of these and carries letters is a line item.
KINDS = [
    ("subtotal", re.compile(r"sub\s*-?\s*total")),
    ("tax", re.compile(r"\b(?:tax|vat|gst|hst|pst)\b")),
    ("tip", re.compile(r"\btip\b|\bgratuity\b|\bservice charge\b")),
    ("discount", re.compile(r"\b(?:discount|savings?|coupon|promo)\b")),
    ("total", re.compile(r"\btotal\b|\bamount due\b|\bbalance due\b")),
    # WHOLE WORDS, because an item line is named by whatever the shop sells, and
    # "Postcard", "Author copy", "Prepaid" and "Exchange fee" each CONTAIN a
    # payment word. Matched as substrings they were taken for payment lines and
    # dropped from the line item sum, which then failed for a reason that was
    # the probe's, not the receipt's (review of ovation#636).
    ("payment", re.compile(r"\b(?:cash|change|visa|mastercard|master card|amex|american express|"
                           r"discover|card|debit|credit|tender|paid|payment|balance|"
                           r"auth|authorization|approved|approval)\b")),
]


class Refusal(Exception):
    """A refusal with its exit code and the sentence that names it."""

    def __init__(self, message, code=1):
        super().__init__(message)
        self.code = code


# ---------------------------------------------------------------------------
# Interpretation. Pure, so it runs on any machine; the Vision half only reports
# what it saw.
# ---------------------------------------------------------------------------

def money_in(text):
    """The LAST amount in a piece of text, as a Decimal, or None."""
    matches = list(MONEY.finditer(text or ""))
    if not matches:
        return None
    sign, whole, cents = matches[-1].groups()
    value = Decimal(whole.replace(",", "") + "." + cents)
    return -value if sign else value


def date_in(text):
    for pattern in DATES:
        match = pattern.search(text or "")
        if match:
            return match.group(0)
    return None


def geometry(observations, width, height):
    """Each observation placed in the receipt's own upright frame, and how far
    the receipt was turned.

    Vision reads a sideways or skewed receipt without being told, and reports
    each observation's corners in the image's frame, so the direction the text
    RUNS is what says which way is up. It is measured in pixels, because in
    normalised units a non square image distorts every angle but the axes."""
    angles = []
    for o in observations:
        (x1, y1), (x2, y2) = o["topLeft"], o["topRight"]
        angles.append(math.atan2((y2 - y1) * height, (x2 - x1) * width))
    if not angles:
        return [], 0
    # The median of circular values, taken on unit vectors so that text running
    # at 179 and -179 degrees is read as one direction rather than averaged to 0.
    angle = math.atan2(statistics.median(math.sin(a) for a in angles),
                       statistics.median(math.cos(a) for a in angles))
    cos, sin = math.cos(angle), math.sin(angle)
    placed = []
    for index, o in enumerate(observations):
        corners = [(p[0] * width, p[1] * height)
                   for p in (o["topLeft"], o["topRight"], o["bottomLeft"], o["bottomRight"])]
        # Rotating by minus the text angle makes the text run along +u, with up
        # along +v.
        uv = [(x * cos + y * sin, -x * sin + y * cos) for x, y in corners]
        placed.append({
            "index": index,
            "u": min(p[0] for p in uv),
            "v": sum(p[1] for p in uv) / 4,
            "height": abs(uv[0][1] - uv[2][1]),
            "candidates": o["candidates"],
        })
    turned = round(-math.degrees(angle)) % 360
    return placed, turned


def rows_of(placed):
    """Observations grouped into printed lines, top down, each line left to
    right. A receipt puts a label and its amount in separate observations, so an
    amount has to be joined to its label by position."""
    if not placed:
        return []
    tolerance = 0.5 * statistics.median(p["height"] for p in placed)
    rows = []
    for p in sorted(placed, key=lambda p: -p["v"]):
        if rows and abs(rows[-1]["v"] - p["v"]) < tolerance:
            rows[-1]["members"].append(p)
        else:
            rows.append({"v": p["v"], "members": [p]})
    for row in rows:
        row["members"].sort(key=lambda p: p["u"])
        row["text"] = " ".join(top(p) for p in row["members"])
    return rows


def top(placed):
    return placed["candidates"][0]["text"] if placed["candidates"] else ""


def confidence(placed):
    return placed["candidates"][0]["confidence"] if placed["candidates"] else 0.0


def reading(value, source, alternatives):
    """One field as read: the value, Vision's confidence in the observation it
    came from, every OTHER value Vision's alternative readings of that same
    observation would have given, and whether it would be filled. A field is
    filled only where no alternative disagrees (PRD 18, 18a); no confidence
    threshold is applied, because none has been calibrated on receipts and a
    constant invented here would be the thing this probe exists to measure."""
    if value is None:
        return {"value": None, "confidence": None, "alternatives": [], "wouldFill": False}
    return {
        "value": value,
        "confidence": round(confidence(source), 4) if source else None,
        "alternatives": alternatives,
        "wouldFill": not alternatives,
    }


def only_dropped_characters(shorter, longer):
    """Whether one reading is the other with characters missing. Vision's
    alternatives with correction on are mostly that ("TOTA", "Noteboo"), a
    weaker reading of the same TEXT rather than a competing one. Applied to text
    only: an amount or a date with a character missing that still parses is a
    different amount or date, and PRD 18 leaves such a field empty."""
    letters = iter(longer)
    return len(shorter) < len(longer) and all(c in letters for c in shorter)


def alternatives_of(source, parse, chosen, same=lambda a, b: a == b, text=False):
    found = []
    for candidate in source["candidates"][1:]:
        if text and only_dropped_characters(candidate["text"], top(source)):
            continue
        value = parse(candidate["text"])
        if value is not None and not same(value, chosen) and value not in [a["value"] for a in found]:
            found.append({"value": value, "confidence": round(candidate["confidence"], 4)})
    return found


def label_of(row):
    return MONEY.sub(" ", row["text"]).lower()


def classify(rows):
    """Every line carrying an amount, with its kind and the observation the
    amount was read from."""
    lines = []
    for position, row in enumerate(rows):
        source, value = None, None
        for member in reversed(row["members"]):
            value = money_in(top(member))
            if value is not None:
                source = member
                break
        if source is None:
            continue
        label = label_of(row)
        kind = next((name for name, pattern in KINDS if pattern.search(label)), None)
        if kind is None:
            kind = "item" if len(re.findall(r"[a-z]", label)) >= 2 else "unlabelled"
        lines.append({"position": position, "kind": kind, "value": value, "source": source})
    return lines


def arithmetic(lines):
    def of(kind):
        return [line for line in lines if line["kind"] == kind]

    subtotal = of("subtotal")[0]["value"] if of("subtotal") else None
    totals = of("total")
    first_sum_line = min((l["position"] for l in lines if l["kind"] in ("subtotal", "total")), default=None)
    if subtotal is not None:
        below = [t for t in totals if t["position"] > of("subtotal")[0]["position"]]
        total_line = (below or totals or [None])[0]
    else:
        total_line = totals[0] if totals else None
    total = total_line["value"] if total_line else None
    tax = sum((l["value"] for l in of("tax")), Decimal("0"))
    tip = sum((l["value"] for l in of("tip")), Decimal("0"))
    discount = sum((abs(l["value"]) for l in of("discount")), Decimal("0"))
    items = [l for l in of("item") if first_sum_line is None or l["position"] < first_sum_line]

    line_check = {"computable": False, "held": None, "sum": None, "against": None,
                  "againstLine": None, "lineItems": len(items), "reason": None}
    if not items:
        line_check["reason"] = "no line items"
    elif subtotal is None and total is None:
        line_check["reason"] = "no subtotal or total"
    else:
        added = sum((l["value"] for l in items), Decimal("0"))
        if subtotal is not None:
            against, which = subtotal, "subtotal"
        else:
            against, which = total - tax - tip + discount, "total less tax, tip and discount"
        line_check.update(computable=True, held=added == against, sum=str(added),
                          against=str(against), againstLine=which)

    total_check = {"computable": False, "held": None, "sum": None, "against": None, "reason": None}
    if subtotal is None:
        total_check["reason"] = "no subtotal"
    elif total is None:
        total_check["reason"] = "no total"
    else:
        expected = subtotal + tax + tip - discount
        total_check.update(computable=True, held=expected == total, sum=str(expected), against=str(total))
    return total_line, {"lineItems": line_check, "subtotalPlusTax": total_check}


def fields(observations, width, height):
    """Amount, date and vendor as one pass of the reader saw them, with the
    lines and the arithmetic they rest on."""
    placed, turned = geometry(observations, width, height)
    rows = rows_of(placed)
    lines = classify(rows)
    total_line, checks = arithmetic(lines)

    if total_line:
        chosen = total_line["value"]
        amount = reading(str(chosen), total_line["source"],
                         [dict(a, value=str(a["value"])) for a in
                          alternatives_of(total_line["source"], money_in, chosen)])
    else:
        amount = reading(None, None, [])

    date = reading(None, None, [])
    for row in rows:
        member = next((m for m in row["members"] if date_in(top(m))), None)
        if member:
            chosen = date_in(top(member))
            date = reading(chosen, member, alternatives_of(member, date_in, chosen))
            break

    vendor = reading(None, None, [])
    for row in rows:
        text = row["text"]
        if len(re.findall(r"[A-Za-z]", text)) >= 3 and not date_in(text) and money_in(text) is None:
            first = row["members"][0]
            vendor = reading(text, first, alternatives_of(
                first, lambda t: t, top(first), lambda a, b: a.casefold() == b.casefold(), text=True))
            vendor["confidence"] = round(min(confidence(m) for m in row["members"]), 4)
            break

    disagreeing = sum(1 for p in placed if alternatives_of(p, lambda t: t, top(p), text=True))
    return {"turned": turned, "rows": rows, "lines": lines, "checks": checks,
            "amount": amount, "date": date, "vendor": vendor,
            "observations": len(placed), "withDisagreeingAlternative": disagreeing}


FIELDS = ("amount", "date", "vendor")


def interpret(raw, file, digest):
    base = {"index": raw["index"], "file": file, "sha256": digest}
    if not raw.get("readable"):
        return dict(base, readable=False, error=raw.get("error", "unreadable"))
    width, height = raw["pixelWidth"], raw["pixelHeight"]
    first = fields(raw["observations"], width, height)
    second = fields(raw.get("observationsWithCorrection", []), width, height)
    amount, date, vendor = first["amount"], first["date"], first["vendor"]
    rows, lines = first["rows"], first["lines"]
    same_value = {}
    for field in FIELDS:
        a, b = first[field]["value"], second[field]["value"]
        same_value[field] = None if a is None or b is None else a == b

    barcodes = []
    for barcode in raw.get("barcodes", []):
        payload = barcode.get("payload")
        carries = None
        if payload is not None and amount["value"] is not None:
            carries = amount["value"] in payload or amount["value"].replace(".", "") in payload
        barcodes.append({"symbology": barcode["symbology"], "payload": payload,
                         "payloadContainsAmount": carries})

    return dict(
        base, readable=True, turnedDegrees=first["turned"],
        amount=amount, date=date, vendor=vendor,
        arithmetic=first["checks"], barcodes=barcodes,
        # The same reader again with language correction on: corroboration,
        # never an independent check, since both passes share every failure a
        # misread digit comes from (ovation#74, candidate 1).
        withLanguageCorrection={field: second[field] for field in FIELDS},
        passesAgree=same_value,
        alternativesSeen={
            "correctionOff": {"observations": first["observations"],
                              "withDisagreeingAlternative": first["withDisagreeingAlternative"]},
            "correctionOn": {"observations": second["observations"],
                             "withDisagreeingAlternative": second["withDisagreeingAlternative"]},
        },
        lines=[{"text": row["text"],
                "kind": next((l["kind"] for l in lines if l["position"] == position), None),
                "readings": [[c["text"] for c in m["candidates"]] for m in row["members"]]}
               for position, row in enumerate(rows)],
        observations=raw["observations"],
        observationsWithCorrection=raw.get("observationsWithCorrection", []),
    )


# ---------------------------------------------------------------------------
# The summary. Counts only, from the results file alone, so re-printing it
# never needs Vision and says exactly what the file says.
# ---------------------------------------------------------------------------

def summary(results):
    receipts = results["receipts"]
    n = len(receipts)
    out = []
    if n < VERDICT_SAMPLE:
        out.append(f"PILOT, n={n}, NOT A VERDICT")
        out.append(f"  The verdict against the marks agreed on ovation#74 waits for {VERDICT_SAMPLE} or more receipts.")
    else:
        out.append(f"n={n}, NOT A VERDICT")
        out.append("  Enough receipts for the verdict, which is judged against the marks agreed on ovation#74.")
    out.append("  Whether any reading is RIGHT is judged by Dan against the receipts, not by this probe.")
    reader = results["reader"]
    if reader.get("standIn"):
        # Said before any number, because a stand in's numbers otherwise read
        # exactly like Vision's (L169).
        out.append(f"READER REPLACED: OVATION_RECEIPT_READER={reader['standIn']} stood in for Vision, "
                   "so none of these numbers is a measurement of Vision.")
    out.append(f"Reader: macOS {reader['osVersion']}, text recognition revision "
               f"{reader['textRecognitionRevision']}, barcode revision {reader['barcodeRevision']}")
    out.append(f"Per field, over {n} receipts, language correction off:")
    for field in FIELDS:
        read = sum(1 for r in receipts if r[field]["value"] is not None)
        fill = sum(1 for r in receipts if r[field]["wouldFill"])
        out.append(f"  {field:<8} read {read} of {n}    would fill {fill} of {n}")
    out.append("Second pass, language correction on (the same reader, so corroboration, never independent):")
    for field in FIELDS:
        second = [r["withLanguageCorrection"][field] for r in receipts]
        read = sum(1 for f in second if f["value"] is not None)
        fill = sum(1 for f in second if f["wouldFill"])
        both = [r["passesAgree"][field] for r in receipts if r["passesAgree"][field] is not None]
        out.append(f"  {field:<8} read {read} of {n}    would fill {fill} of {n}    "
                   f"same as the first pass {sum(both)} of {len(both)}")
    out.append("Text observations with a disagreeing alternative, not merely the same text with characters missing (PRD 18a):")
    for key, words in (("correctionOff", "correction off"), ("correctionOn", "correction on")):
        seen = [r["alternativesSeen"][key] for r in receipts]
        out.append(f"  {words:<15} {sum(s['withDisagreeingAlternative'] for s in seen)} of "
                   f"{sum(s['observations'] for s in seen)}")
    out.append(f"Arithmetic self consistency, over {n} receipts:")
    for key, words in (("lineItems", "line items sum to the subtotal:"),
                       ("subtotalPlusTax", "subtotal plus tax equals the total:")):
        computable = [r for r in receipts if r["arithmetic"][key]["computable"]]
        held = sum(1 for r in computable if r["arithmetic"][key]["held"])
        out.append(f"  {words:<37} computable {len(computable)} of {n}, held {held} of {len(computable)}")
    either = sum(1 for r in receipts if any(c["computable"] for c in r["arithmetic"].values()))
    out.append(f"  {'either check computable:':<37} {either} of {n}")
    barcodes = sum(1 for r in receipts if r["barcodes"])
    out.append(f"  {'barcode or QR present:':<37} {barcodes} of {n}")
    turned = sum(1 for r in receipts
                 if min(r["turnedDegrees"], 360 - r["turnedDegrees"]) > TURNED_BEYOND_DEGREES)
    out.append(f"  {'read turned from upright:':<37} {turned} of {n}")
    return out


def page(results):
    """The per receipt page Dan checks against the receipts. It carries the
    content, which is why it lives in the custody folder and nowhere else."""
    e = lambda value: html.escape("" if value is None else str(value))
    parts = [
        "<!doctype html><html><head><meta charset='utf-8'>",
        "<meta name='viewport' content='width=device-width, initial-scale=1'>",
        "<title>Receipt probe results</title><style>",
        ":root{color-scheme:light dark;--bg:#fff;--fg:#1d1d1f;--line:#d2d2d7;--muted:#6e6e73}",
        "@media (prefers-color-scheme:dark){:root{--bg:#1d1d1f;--fg:#f5f5f7;--line:#424245;--muted:#a1a1a6}}",
        "body{background:var(--bg);color:var(--fg);font:15px/1.45 -apple-system,sans-serif;margin:24px}",
        "section{display:grid;grid-template-columns:minmax(0,360px) minmax(0,1fr);gap:24px;",
        "border-top:1px solid var(--line);padding:24px 0}",
        "img{max-width:100%;border:1px solid var(--line)}table{border-collapse:collapse;width:100%}",
        "td,th{text-align:left;vertical-align:top;padding:4px 12px 4px 0;border-bottom:1px solid var(--line)}",
        ".muted{color:var(--muted)}pre{white-space:pre-wrap;font-size:13px}",
        "</style></head><body>",
    ]
    parts.append("<h1>Receipt probe results</h1><p>" + "<br>".join(e(l) for l in summary(results)) + "</p>")
    parts.append("<p class='muted'>Check each reading against the receipt beside it. A value that is "
                 "filled and wrong is the failure the agreed marks forbid.</p>")
    for r in results["receipts"]:
        image = "file://" + urllib.parse.quote(os.path.join(results["folder"], r["file"]))
        parts.append(f"<section><div><h2>Receipt {r['index']}</h2><p class='muted'>{e(r['file'])}</p>"
                     f"<img src='{e(image)}' alt='Receipt {r['index']}'></div><div>")
        if not r.get("readable"):
            parts.append(f"<p>Not read: {e(r.get('error'))}</p></div></section>")
            continue
        parts.append("<table><tr><th>Field</th><th>Pass</th><th>Read</th><th>Confidence</th>"
                     "<th>Alternatives that disagree</th><th>Would fill</th></tr>")
        for field in FIELDS:
            for label, f in (("correction off", r[field]), ("correction on", r["withLanguageCorrection"][field])):
                alternatives = ", ".join(f"{a['value']} ({a['confidence']})" for a in f["alternatives"]) or "none"
                parts.append(f"<tr><td>{field}</td><td class='muted'>{label}</td>"
                             f"<td>{e(f['value']) or 'not read'}</td>"
                             f"<td>{e(f['confidence'])}</td><td>{e(alternatives)}</td>"
                             f"<td>{'yes' if f['wouldFill'] else 'no'}</td></tr>")
        parts.append("</table><h3>Arithmetic</h3><table>")
        for key, words in (("lineItems", "Line items against the subtotal"),
                           ("subtotalPlusTax", "Subtotal plus tax against the total")):
            c = r["arithmetic"][key]
            if c["computable"]:
                verdict = f"{'held' if c['held'] else 'DID NOT HOLD'}: {e(c['sum'])} against {e(c['against'])}"
                if c.get("againstLine"):
                    verdict += f" (the {e(c['againstLine'])})"
            else:
                verdict = f"not computable: {e(c['reason'])}"
            parts.append(f"<tr><td>{words}</td><td>{verdict}</td></tr>")
        parts.append("</table><h3>Barcodes</h3>")
        if r["barcodes"]:
            for b in r["barcodes"]:
                parts.append(f"<p>{e(b['symbology'])}: {e(b['payload'])} "
                             f"<span class='muted'>(carries the amount: {e(b['payloadContainsAmount'])})</span></p>")
        else:
            parts.append("<p>none found</p>")
        parts.append(f"<h3>Every line as read</h3><p class='muted'>Turned {r['turnedDegrees']} degrees "
                     "from upright. Each line shows its kind where it carried an amount.</p><pre>")
        for line in r["lines"]:
            parts.append(e(line["text"]) + (f"   [{e(line['kind'])}]" if line["kind"] else ""))
        parts.append("</pre></div></section>")
    parts.append("</body></html>")
    return "\n".join(parts)


# ---------------------------------------------------------------------------
# The run.
# ---------------------------------------------------------------------------

def inside_git_repository(path):
    current = os.path.abspath(path)
    while True:
        if os.path.exists(os.path.join(current, ".git")):
            return True
        parent = os.path.dirname(current)
        if parent == current:
            return False
        current = parent


def receipts_in(folder):
    return sorted(name for name in os.listdir(folder)
                  if not name.startswith(".") and os.path.isfile(os.path.join(folder, name)))


def what_the_reader_said(ran, written):
    """The reader's exit status, its stderr, its stdout, and what is wrong with
    the file it wrote.

    "Not its JSON" alone named no cause, and on CI it was the only words there
    were (L11). Stdout and stderr carry framework messages and positions, never
    receipt content, because the reader writes its readings only to its file, so
    both are quoted. The file is described by its size and the parser's own
    complaint, a position and a kind of fault, and never quoted, because JSON cut
    short still holds a receipt's text (docs/PRIVACY-FLOOR.md)."""
    lines = [f"  exit status {ran.returncode}"]
    for name, stream in (("stderr", ran.stderr), ("stdout", ran.stdout)):
        text = stream.decode("utf-8", "replace").strip()
        lines.append(f"  {name}: " + (text.splitlines()[0][:300] if text else "(nothing)"))
    if written is None:
        lines.append("  its file: not written")
    else:
        lines.append(f"  its file: {len(written)} bytes of JSON that do not parse (not quoted, it can hold receipt text)")
        try:
            json.loads(written)
        except ValueError as error:
            lines.append(f"  the parser said: {getattr(error, 'msg', 'not JSON')} at character {getattr(error, 'pos', '?')}")
    return "\n".join(lines)


def read_with_vision(paths):
    # A STAND IN READER, for the suite alone, so it can drive the refusals below
    # on purpose, the UNMEASURED one included (L411). Empty is the real reader.
    # A run that uses one says so in its summary and its results, and may not
    # write into the custody folder (see measure()).
    stand_in = os.environ.get("OVATION_RECEIPT_READER", "")
    if stand_in:
        return run_reader(stand_in, paths)
    if platform.system() != "Darwin" or shutil.which("swiftc") is None:
        raise Refusal("CANNOT MEASURE: the probe reads receipts with Apple's Vision framework, which needs "
                      "a Mac with the Swift compiler (swiftc). Nothing was read.", 2)
    with tempfile.TemporaryDirectory() as work:
        reader = os.path.join(work, "receipt-reader")
        built = subprocess.run(["swiftc", "-O", "-o", reader, READER_SOURCE],
                               capture_output=True, text=True)
        if built.returncode != 0:
            raise Refusal("REFUSED: the Vision reader did not compile, so nothing was read.\n"
                          + "\n".join(built.stderr.splitlines()[:10]))
        return run_reader(reader, paths)


def run_reader(reader, paths):
    """Runs a reader and returns its readings, from the FILE it was told to
    write rather than its stdout.

    Measured on the macOS CI runner, 2026-09-30: in a virtual machine Apple's own
    model runtime prints its exceptions to stdout ("E5RT encountered an STL
    exception ... On-device compilation within a VM only supports CPU
    currently") after the reader's JSON, while the recognition itself worked on
    the CPU. A reading carried on stdout is at the mercy of every framework in
    the process, so it is carried in a file the reader alone writes."""
    with tempfile.TemporaryDirectory() as work:
        out = os.path.join(work, "readings.json")
        ran = subprocess.run([reader, "--out", out] + paths, capture_output=True)
        written = None
        if os.path.exists(out):
            with open(out, "rb") as handle:
                written = handle.read()
        if ran.returncode != 0:
            raise Refusal("REFUSED: the Vision reader failed, so nothing was measured.\n"
                          + what_the_reader_said(ran, written))
        try:
            raw = json.loads(written) if written is not None else None
        except ValueError:
            raw = None
        if not isinstance(raw, dict):
            raise Refusal("REFUSED: the Vision reader wrote something that is not its JSON, so nothing was measured.\n"
                          + what_the_reader_said(ran, written))
    # VISION REFUSING TO RUN is a fact about this machine, not about a receipt,
    # so it is CANNOT MEASURE by name rather than "could not be read as an
    # image", which would send somebody to look at a file that is fine (L11).
    refused = [r for r in raw.get("receipts", []) if r.get("visionRefused")]
    if refused:
        raise Refusal("CANNOT MEASURE: Vision text recognition refused on this machine: "
                      + refused[0].get("error", "no reason given") + ". Nothing was measured.", 2)
    return raw


def write_private(folder, stem, suffix, text):
    """Written readable by Dan alone, and never over an earlier run's file."""
    attempt = 0
    while True:
        name = f"{stem}{'' if attempt == 0 else '-' + str(attempt)}{suffix}"
        path = os.path.join(folder, name)
        try:
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            attempt += 1
            continue
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.chmod(path, 0o600)
        return path


def measure(folder, results_folder):
    if not os.path.isdir(folder):
        raise Refusal(f"REFUSED: the receipt folder does not exist: {folder}")
    names = receipts_in(folder)
    if not names:
        raise Refusal(f"REFUSED: the receipt folder holds no receipts, so there is nothing to measure: {folder}")
    stand_in = os.environ.get("OVATION_RECEIPT_READER", "")
    if stand_in and os.path.realpath(results_folder).startswith(os.path.realpath(CUSTODY) + os.sep):
        # A value left exported by a test must never put a stand in's results
        # where Dan keeps the real ones (L169).
        raise Refusal("REFUSED: OVATION_RECEIPT_READER is set, so a stand in would replace Vision, and its "
                      f"results may not be written into the custody folder. Unset it to measure: {results_folder}")
    if inside_git_repository(results_folder):
        raise Refusal("REFUSED: the results folder is inside a git repository, where the receipts' content "
                      f"could be committed. Give it a folder outside any repository: {results_folder}")

    paths = [os.path.join(folder, name) for name in names]
    raw = read_with_vision(paths)
    unreadable = [r["index"] for r in raw["receipts"] if not r.get("readable")]
    if unreadable:
        # Refused rather than measured over fewer, because a pilot claiming n
        # receipts while reading fewer describes a sample that does not exist.
        # Named by POSITION, since a filename can carry a vendor.
        raise Refusal("\n".join(f"REFUSED: receipt {i} of {len(names)} could not be read as an image, "
                                "so nothing was measured." for i in unreadable)
                      + f"\n  Receipts are counted in filename order within {folder}.")

    receipts = []
    for entry in raw["receipts"]:
        path = paths[entry["index"] - 1]
        with open(path, "rb") as handle:
            digest = hashlib.sha256(handle.read()).hexdigest()
        receipts.append(interpret(entry, os.path.basename(path), digest))
    results = {
        "probe": "ovation#74, photographed receipts",
        "measuredAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "folder": os.path.abspath(folder),
        "reader": {"osVersion": raw["osVersion"],
                   "textRecognitionRevision": raw["textRecognitionRevision"],
                   "barcodeRevision": raw["barcodeRevision"],
                   "standIn": os.environ.get("OVATION_RECEIPT_READER") or None},
        "receipts": receipts,
    }
    os.makedirs(results_folder, mode=0o700, exist_ok=True)
    os.chmod(results_folder, 0o700)
    stem = "results-" + datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    json_path = write_private(results_folder, stem, ".json", json.dumps(results, indent=2, sort_keys=True))
    html_path = write_private(results_folder, os.path.basename(json_path)[:-5], ".html", page(results))
    return results, html_path


def main(argv):
    options = {"--folder": DEFAULT_FOLDER, "--results": DEFAULT_RESULTS, "--summarise": None}
    args = list(argv)
    while args:
        flag = args.pop(0)
        if flag not in options or not args:
            print(__doc__.split("Usage:")[1].split("Defaults:")[0].rstrip(), file=sys.stderr)
            return 64
        options[flag] = args.pop(0)
    try:
        if options["--summarise"]:
            stem, extension = os.path.splitext(options["--summarise"])
            if extension.lower() != ".json":
                raise Refusal("REFUSED: --summarise takes a results .json file, the one a run wrote beside its page.")
            with open(options["--summarise"], encoding="utf-8") as handle:
                results = json.load(handle)
            html_path = stem + ".html"
            html_path = html_path if os.path.exists(html_path) else None
        else:
            results, html_path = measure(options["--folder"], options["--results"])
    except Refusal as refusal:
        print(str(refusal))
        return refusal.code
    except (OSError, ValueError, KeyError) as error:
        # Named by its type and never its text, which could quote a receipt.
        print(f"REFUSED: the results could not be read or written ({type(error).__name__}).")
        return 1
    for line in summary(results):
        print(line)
    if html_path:
        print("Per receipt results, to check against the receipts themselves:")
        print(f"  open -a \"Google Chrome\" \"{html_path}\"")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
