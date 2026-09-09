#!/usr/bin/env python3
"""Write each shell part into every design file that carries it.

    write-design-shell.sh [--check] [design file ...]

ovation#177. `scripts/check-design-shell-inline.sh` refuses a drifted copy and
ends with "Paste the part back into the file, or say in the file why it carries
none." Nothing pasted. Keeping five design files in step with `docs/design/shell/`
was manual copying, and on 2026-09-09 that meant writing a throwaway script to
put one changed rule into four files by hand.

A guard that detects drift while leaving the remedy to careful copying makes the
next drift a matter of whoever is tired, and the remedy is run precisely when
somebody is mid change and wants to move on. A remedy nothing executes is also
never tested, so nobody finds out it was wrong until the moment it is needed
(L406). This is that remedy, and its suite runs it.

WHAT IT DOES NOT DO, and this is the part worth understanding. It does not
replace the file's copy with the part's text, because the copies are not plain
copies: `invoice-list.html` interleaves its own decision records among the
shell's rules, and four of the five files carry at least one part that way. A
wholesale replacement would delete the rounds' own reasoning, which is the most
expensive thing in these files.

SO IT PATCHES THE CODE LINES AND LEAVES EVERYTHING ELSE STANDING. The file's copy
is located exactly as the checker locates it, as a contiguous run of SIGNIFICANT
lines, and the part's significant lines are applied to that run as a diff:
changed lines are rewritten in place keeping the file's own indentation, new ones
are inserted beside their neighbours, removed ones go. Comments and blank lines
inside the span are never touched.

IT REFUSES WHERE IT CANNOT FIND THE COPY. A file that declares NOT SHELLED is
left alone, and a file whose copy shares no line at all with the part is a
refusal rather than an insertion at a guessed place: an operation that finds its
target by matching text reports success when it matches nothing, and the next
step then acts on a state nobody created (L100).

Exit codes, one per outcome (L11):

    0  every declared copy is in step, whether or not anything was written
    1  at least one file's copy could not be located, so nothing was written for it
    2  used wrongly, or there is nothing to write
    3  --check only: a copy has drifted and would be rewritten

Seam: OVATION_DESIGN_ROOT.
"""
import difflib
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

from design_inline import html_files, significant_lines  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.environ.get("OVATION_DESIGN_ROOT") or os.path.join(REPO, "docs", "design")
DECLARES_UNSHELLED = "NOT SHELLED:"


def declared_unshelled(text):
    """The parts a file says, in its own words, that it does not carry."""
    found = set()
    for raw in text.splitlines():
        if DECLARES_UNSHELLED not in raw:
            continue
        said = raw.split(DECLARES_UNSHELLED, 1)[1].replace("*/", " ").strip()
        match = re.match(r"([A-Za-z0-9_.\-]+)[,:\s]+(.*)", said)
        if match and match.group(2).strip():
            found.add(match.group(1))
    return found


def stripped_keeping_line_numbers(text):
    """The text with comments blanked, ONE LINE FOR ONE LINE.

    `design_inline.strip_comments` collapses a block comment to a single
    newline, which is right for comparing a shape and wrong for editing a file:
    every line after the first comment then has the wrong number, and a writer
    built on it puts the corrected rule into a different part of the file. That
    happened on the first run of this script, which repaired `.item.on` by
    writing it over a line of the palette (L237: addressing something by its
    position measures whatever currently occupies that position).
    """
    out = []
    in_block = False
    for raw in text.split("\n"):
        line, rest = "", raw
        while rest:
            if in_block:
                end = rest.find("*/")
                if end < 0:
                    rest = ""
                else:
                    rest = rest[end + 2:]
                    in_block = False
                continue
            start = rest.find("/*")
            # A LINE COMMENT ONLY WHERE ONE CAN BEGIN, which is at the start of
            # the line or after whitespace. `design_inline.strip_comments` makes
            # the same distinction and for the same reason: these files carry
            # embedded fonts as base64, where `//` occurs by the thousand inside
            # a single token, and a stripper that cut on any `//` truncated the
            # whole payload and then could not find the part at all.
            line_comment = -1
            for where in range(len(rest) - 1):
                if rest[where:where + 2] != "//":
                    continue
                before = (line + rest[:where])
                if not before or before[-1].isspace():
                    line_comment = where
                    break
            if line_comment >= 0 and (start < 0 or line_comment < start):
                line += rest[:line_comment]
                rest = ""
                continue
            if start < 0:
                line += rest
                rest = ""
                continue
            line += rest[:start]
            rest = rest[start + 2:]
            in_block = True
        out.append(line)
    return out


def significant_index(lines):
    """(line number, collapsed text) for every code line, in file order.

    The same normalisation the checker compares by, so the writer and the guard
    cannot disagree about what a copy IS (L70).
    """
    out = []
    for number, raw in enumerate(stripped_keeping_line_numbers(text_of(lines))):
        collapsed = " ".join(raw.split())
        if collapsed:
            out.append((number, collapsed))
    return out


def text_of(lines):
    return "\n".join(lines)


def locate(file_lines, part_lines):
    """(first, last) line numbers of the file's copy of the part, or None.

    THE ANCHOR IS THE PART'S FIRST LINE, and the span runs to the last of its
    lines that still matches in order. A copy that has drifted in the middle
    still anchors, which is the whole point: that is the copy this exists to
    repair.
    """
    index = significant_index(file_lines)
    if not index or not part_lines:
        return None
    best = None
    for start in range(len(index)):
        if index[start][1] != part_lines[0]:
            continue
        matcher = difflib.SequenceMatcher(
            a=[text for _, text in index[start:start + len(part_lines) * 3]],
            b=part_lines, autojunk=False)
        matched = sum(block.size for block in matcher.get_matching_blocks())
        if best is None or matched > best[0]:
            last_in_file = start
            for block in matcher.get_matching_blocks():
                if block.size:
                    last_in_file = start + block.a + block.size - 1
            best = (matched, index[start][0], index[last_in_file][0])
    if best is None:
        return None
    return best[1], best[2]


def indentation(line):
    return line[:len(line) - len(line.lstrip())]


def rewrite(file_lines, span, part_lines):
    """The file's lines with its copy of the part brought back into step."""
    first, last = span
    stripped = stripped_keeping_line_numbers(text_of(file_lines))
    # The code lines inside the span, with where each one is.
    inside = [(n, " ".join(stripped[n].split()))
              for n in range(first, last + 1)
              if n < len(stripped) and stripped[n].split()]

    pad = indentation(file_lines[first]) if file_lines[first].strip() else ""
    matcher = difflib.SequenceMatcher(a=[text for _, text in inside],
                                      b=part_lines, autojunk=False)
    replacements = {}          # file line number -> new text
    insertions = {}            # file line number -> lines to put BEFORE it
    removals = set()
    for tag, a1, a2, b1, b2 in matcher.get_opcodes():
        if tag == "equal":
            continue
        if tag == "replace":
            for offset in range(max(a2 - a1, b2 - b1)):
                where = a1 + offset
                if offset < b2 - b1 and where < a2:
                    replacements[inside[where][0]] = pad + part_lines[b1 + offset]
                elif where < a2:
                    removals.add(inside[where][0])
                else:
                    at = inside[a2 - 1][0] if a2 > a1 else inside[min(a1, len(inside) - 1)][0]
                    insertions.setdefault(at + 1, []).append(pad + part_lines[b1 + offset])
        elif tag == "delete":
            for where in range(a1, a2):
                removals.add(inside[where][0])
        elif tag == "insert":
            at = inside[a1][0] if a1 < len(inside) else last + 1
            insertions.setdefault(at, []).extend(pad + line for line in part_lines[b1:b2])

    out = []
    for number, line in enumerate(file_lines):
        for added in insertions.get(number, []):
            out.append(added)
        if number in removals:
            continue
        out.append(replacements.get(number, line))
    for number in sorted(n for n in insertions if n >= len(file_lines)):
        out.extend(insertions[number])
    return out


def main(argv):
    args = [a for a in argv[1:] if a != "--check"]
    checking = "--check" in argv[1:]

    shell_dir = os.path.join(ROOT, "shell")
    if not os.path.isdir(shell_dir):
        print("CANNOT WRITE: no %s, so there is no shell to write." % shell_dir)
        return 2
    parts = {}
    for name in sorted(os.listdir(shell_dir)):
        if name.endswith((".css", ".js")):
            with open(os.path.join(shell_dir, name), encoding="utf-8") as handle:
                parts[name] = significant_lines(handle.read())
    if not parts:
        print("CANNOT WRITE: %s holds no part, so nothing was written and "
              "nothing was compared." % shell_dir)
        return 2

    files = args or [os.path.join(ROOT, n) for n in html_files(os.listdir(ROOT))]
    if not files:
        print("CANNOT WRITE: no design file under %s." % ROOT)
        return 2

    written = unchanged = 0
    drifted = []
    lost = []
    for path in files:
        if not os.path.isfile(path):
            print("CANNOT WRITE: no such design file: %s" % path)
            return 2
        with open(path, encoding="utf-8") as handle:
            original = handle.read().split("\n")
        unshelled = declared_unshelled("\n".join(original))
        lines = original
        name = os.path.basename(path)
        for part, part_lines in parts.items():
            if part in unshelled:
                continue
            span = locate(lines, part_lines)
            if span is None:
                lost.append((name, part))
                continue
            after = rewrite(lines, span, part_lines)
            if after != lines:
                drifted.append((name, part))
                lines = after
            else:
                unchanged += 1
        if lines != original:
            written += 1
            if not checking:
                with open(path, "w", encoding="utf-8") as handle:
                    handle.write("\n".join(lines))

    for name, part in drifted:
        print("  %s: %s %s" % (name, part, "WOULD BE REWRITTEN" if checking else "REWRITTEN"))
    for name, part in lost:
        print("  %s: %s NOT FOUND, and nothing was written for it. The file "
              "carries no line of that part and does not declare NOT SHELLED, "
              "so where it belongs is a decision rather than a guess."
              % (name, part))

    if lost:
        print("REFUSED: %d copy(s) could not be located, so this wrote nothing "
              "for them." % len(lost))
        return 1
    if checking and drifted:
        print("DRIFTED: %d copy(s) would be rewritten across %d file(s)."
              % (len(drifted), written))
        return 3
    print("OK: %d copy(s) already in step, %d %s, across %d design file(s)."
          % (unchanged, len(drifted),
             "would be rewritten" if checking else "rewritten", len(files)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
