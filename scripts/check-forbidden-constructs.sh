#!/usr/bin/env python3
"""Refuse a construct Ovation has ruled out, anywhere in its app sources.

ovation#53 (plan 1.4) and ovation#54 (plan 1.5). ONE scanner, several rules.
The rules share the walk, the comment stripping, the word boundary matching, the
allowlist and every refusal; only the tokens and the sentence differ. A second
script for the second rule would have shared the DATA while copying the LOGIC,
which is not consolidation (L370).

RULE ONE, FLOATING POINT MONEY (plan 1.4). `Money` carries no floating point
constructor at all, so the mistake cannot be written INSIDE the money type. That
says nothing about a `Double` declared anywhere else, and a rule stated only in a
header is enforced by nothing while reading as binding (L27, L407).

RULE TWO, THE AMBIENT CALENDAR (plan 1.5). Every business date goes through
`BusinessCalendar`, pinned to America/New_York. The second calendar does not
arrive as a decision; it arrives inside a convenience somebody adds later (L39).

WHAT IT NEVER PRINTS: the source line. It reports the file, the line number and
the type name only. Printing the line would put whatever that line says into
transcripts and terminal scrollback, and a comment on a money line is exactly
where a client name would sit (L222).

COMMENTS ARE NOT CODE, and they are stripped from INSIDE each line rather than
the line being judged by how it starts, because one line routinely carries code
and then a comment about it (L361). This scanner has to NAME the types it
forbids in order to forbid them, and so does every file explaining the rule, so
without that the rule's own documentation would be its first violation (L245).

The known gap, stated rather than discovered: `//` inside a string literal
truncates that line early, so a forbidden construct written AFTER such a string
on the same line is missed. That is a false negative in a shape no declaration
takes, and the alternative is a Swift parser.

NOTHING SCANNED IS NOT A PASS (L98). A scanner that walks an empty or absent
root exits 0 and reads as coverage, and Ovation's own tree was five files old
when this was written.

Seams: OVATION_CONSTRUCT_SCAN_ROOT and OVATION_CONSTRUCT_ALLOWLIST.

Exit codes, one per outcome (L11):
    0  scanned, and clean
    1  a forbidden construct is present
    2  nothing was scanned: no root, or no Swift files under it
    3  the allowlist itself is bad
"""
import os
import re
import sys

# One rule per thing Ovation has ruled out. The suite derives its per token cases
# from this, rather than restating the tokens, so adding one here extends the
# coverage on its own and cannot leave a construct forbidden by a check nothing
# exercises (L41, L217).
RULES = (
    {
        "name": "floating point money",
        "tokens": ("Double", "Float", "Float32", "Float64", "Decimal", "NSDecimalNumber"),
        "because": (
            "Money is Int64 minor units and hours are tenths (plan 1.4). A single "
            "conversion through a floating point type is a rounding error small "
            "enough to survive review and large enough to matter across a tax year."
        ),
    },
    {
        "name": "ambient calendar",
        "tokens": ("Calendar.current", "NSCalendar.current", "TimeZone.current", "Locale.current"),
        "because": (
            "Every business date goes through BusinessCalendar, pinned to "
            "America/New_York (plan 1.5). The host's zone is a setting, and a tax "
            "year boundary decided by it moves when Dan travels."
        ),
    },
)

# CGFloat IS DELIBERATELY NOT IN THE FIRST RULE. It is a layout quantity, SwiftUI
# is full of it, and forbidding it would fire on every view Ovation ever writes
# while saying nothing about money.
#
# `Date()` IS DELIBERATELY NOT IN THE SECOND ONE, yet. Reading the clock at the
# point of use is its own defect (L74), but Ovation has no injected clock to
# offer instead, so the rule would be a refusal with no remedy. It becomes worth
# adding the day something owns "now", which is the export run record's staleness
# report (ovation#64).

# EMPTY ON PURPOSE, and it stays that way until something earns a place.
# Each entry is "<path relative to the scan root> # <the reason>", and an entry
# with no reason is refused rather than honoured: an exemption carrying no
# written reason, sitting beside neighbours that have one, is evidence nobody
# reasoned about it (L233).
DEFAULT_ALLOWLIST = ()

for _rule in RULES:
    _rule["pattern"] = re.compile(
        r"\b(" + "|".join(re.escape(t) for t in _rule["tokens"]) + r")\b"
    )


def strip_comments(lines):
    """Yield (line number, code only text) with comments removed."""
    in_block = False
    for number, raw in enumerate(lines, start=1):
        text = ""
        index = 0
        while index < len(raw):
            if in_block:
                end = raw.find("*/", index)
                if end == -1:
                    index = len(raw)
                else:
                    in_block = False
                    index = end + 2
                continue
            block = raw.find("/*", index)
            line_comment = raw.find("//", index)
            if line_comment != -1 and (block == -1 or line_comment < block):
                text += raw[index:line_comment]
                break
            if block != -1:
                text += raw[index:block]
                in_block = True
                index = block + 2
                continue
            text += raw[index:]
            break
        yield number, text


def parse_allowlist(entries, root, problems):
    allowed = set()
    for entry in entries:
        entry = entry.strip()
        if not entry:
            continue
        path, separator, reason = entry.partition("#")
        path = path.strip()
        if not separator or not reason.strip():
            problems.append(f"the allowlist entry '{path or entry}' carries no reason")
            continue
        if not os.path.isfile(os.path.join(root, path)):
            problems.append(
                f"the allowlist entry '{path}' names a file that is not there, "
                "so its reason has outlived it"
            )
            continue
        allowed.add(path)
    return allowed


def main(argv):
    if "--list" in argv:
        for rule in RULES:
            for token in rule["tokens"]:
                print(token)
        return 0

    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    root = os.environ.get("OVATION_CONSTRUCT_SCAN_ROOT") or os.path.join(repo_root, "Ovation")

    if not os.path.isdir(root):
        print(f"CANNOT SCAN: {root} is not a directory, so nothing was checked.")
        print("             That is not a pass. Point OVATION_CONSTRUCT_SCAN_ROOT at the sources.")
        return 2

    raw_allowlist = os.environ.get("OVATION_CONSTRUCT_ALLOWLIST")
    entries = raw_allowlist.splitlines() if raw_allowlist is not None else list(DEFAULT_ALLOWLIST)
    problems = []
    allowed = parse_allowlist(entries, root, problems)
    if problems:
        print("BAD ALLOWLIST: an exemption cannot be honoured.")
        for problem in problems:
            print(f"  {problem}")
        return 3

    scanned = 0
    findings = []
    for directory, _, filenames in os.walk(root):
        for filename in sorted(filenames):
            if not filename.endswith(".swift"):
                continue
            path = os.path.join(directory, filename)
            relative = os.path.relpath(path, root)
            if relative in allowed:
                continue
            scanned += 1
            with open(path, "r", encoding="utf-8", errors="replace") as handle:
                lines = handle.read().splitlines()
            for number, code in strip_comments(lines):
                for rule in RULES:
                    for match in rule["pattern"].finditer(code):
                        findings.append((relative, number, match.group(1), rule["name"]))

    if scanned == 0:
        print(f"CANNOT SCAN: no Swift files under {root}.")
        print("             That is not a pass: a scanner with nothing to read reports")
        print("             exactly what a clean tree does.")
        return 2

    if findings:
        print(f"FOUND: forbidden constructs in {scanned} scanned file(s).")
        for relative, number, token, rule_name in findings:
            print(f"  {relative}:{number}: {token} ({rule_name})")
        # A sentence per rule that actually fired, because two rules forbidding
        # different things for different reasons are two findings, not one
        # (L11). A rule nobody tripped says nothing.
        fired = [rule for rule in RULES if any(f[3] == rule["name"] for f in findings)]
        for rule in fired:
            print(f"{rule['name']}: {rule['because']}")
        print(f"{len(findings)} occurrence(s). If one of these is genuinely outside the")
        print("rule, add it to DEFAULT_ALLOWLIST in this script WITH ITS REASON.")
        return 1

    print(f"OK: scanned {scanned} Swift file(s) under {root}, no forbidden constructs.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
