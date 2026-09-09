#!/usr/bin/env python3
"""Refuse a design file carrying CSS for a screen it does not draw.

    check-design-dead-rules.sh [design file ...]

ovation#166 and ovation#148. `docs/design/invoice.html` carried 154 rules that
matched no element, and reading them they were not states the invoice screen can
enter. They were OTHER SCREENS: the Clients rows and panels, the invoice list's
own row treatments, the switcher chrome left behind when the chooser was
stripped out, and Option C of round 1, the invoice as a card coming forward over
the list, which round 1 rejected. Roughly half the stylesheet of the largest
design file described screens it does not draw.

WHY IT IS WORTH A GUARD AND NOT A CLEANUP. These files are what a person opens
to READ the design, so a rule for a screen the file does not draw makes every
reader work out first whether the file even uses it. A dead rule also carries a
docstring, so it reads as a considered choice rather than a leftover (L29,
L346). And it is where the class name collision ovation#120 was filed for came
from: `.nrow` was in the dead set of invoice.html, and it is the class that
reached rows it was never written for.

They arrive by one file being copied from the last one, which is a mechanism
nothing stops, so deleting them once and leaving it there converts the file in
front of whoever did the deleting and leaves the next copy standing (L613).

THE PREDICATE, and why it is this one rather than "matches no element". The
rendered check `check-design-tokens-resolve.sh` reports DRAWN BY NOTHING for any
rule matching no element in a page AT REST, and that is a much larger set: it
includes `:hover`, `:focus-visible`, a menu that is only in the DOM while open,
and every state the switcher can put the screen into. Deleting on that reading
would delete live rules. So this reads the SOURCE instead and asks a narrower
question, one that has no false positives of that kind:

    A rule is DEAD when every class name in its selector appears NOWHERE in the
    file outside its own stylesheets.

A class the page can reach has to be written somewhere the page can reach it:
in the markup, or in the script that builds the markup, including inside a
concatenation like `"invact" + (waiting ? " greyed" : "")`, where both words are
still literal text in the file. A rule whose classes appear only between
`<style>` and `</style>` cannot be reached by anything, in any state, ever.

WHAT IT DELIBERATELY DOES NOT JUDGE. A selector naming no class at all (`body`,
`h1`, `:root`, `@font-face`) is left alone: it matches by element or by
document, so absence from the script says nothing about it. An `@media` or
`@supports` block is descended into rather than treated as one rule.

NOTHING SCANNED IS NOT A PASS (L98). A run that found no design file, or a file
holding no stylesheet, is its own outcome and not health.

IT NAMES THE SELECTOR AND THE FILE, NEVER THE CONTENT of any element, because
this prints to a terminal and element text is where a client name would sit
(docs/PRIVACY-FLOOR.md).

Exit codes, one per outcome (L11):

    0  every rule in every file is reachable
    1  at least one rule is dead
    2  nothing was scanned: no design file, or a file with no stylesheet
    3  used wrongly

Seam: OVATION_DESIGN_ROOT, shared with the other design checks rather than
invented again.
"""
import glob
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_ROOT = os.environ.get("OVATION_DESIGN_ROOT", os.path.join(REPO, "docs/design"))

STYLE_BLOCK = re.compile(r"<style\b[^>]*>(.*?)</style>", re.S | re.I)
SCRIPT_BLOCK = re.compile(r"<script\b[^>]*>.*?</script>", re.S | re.I)
CSS_COMMENT = re.compile(r"/\*.*?\*/", re.S)
CLASS_IN_SELECTOR = re.compile(r"\.(-?[_a-zA-Z][_a-zA-Z0-9-]*)")
# A class name as it can appear anywhere the page can reach it: inside an HTML
# class attribute, inside a string handed to a builder, inside a querySelector.
# Word boundaries on both sides so `.row` is not answered by `rowcount`, and the
# dash is part of a class name so `rs-paper` is one word rather than two.
WORD = r"(?<![-_a-zA-Z0-9]){}(?![-_a-zA-Z0-9])"


def blank(text):
    """Replace a span with the newlines it held.

    EVERY SUBSTITUTION KEEPS THE LINE COUNT, so a line number reported here is
    the line in the file the reader will open. A blanking `sub` that collapsed
    the span would move every rule below it, and a check that names the wrong
    line is read as a broken check rather than as a real finding."""
    return "\n" * text.count("\n")


def top_level_styles(text):
    """(first content line, css) for each stylesheet the PAGE ITSELF carries.

    `review-send.html` embeds a whole second document, its stylesheet included,
    as a JavaScript string, because the preview it shows IS the PDF that ships
    (PRD 10c). That embedded sheet belongs to a different document with its own
    markup in the same string, so judging its rules against THIS page's markup
    would report every one of them dead. Script bodies are blanked before the
    stylesheets are found, and only then."""
    scriptless = SCRIPT_BLOCK.sub(lambda m: blank(m.group(0)), text)
    out = []
    for m in STYLE_BLOCK.finditer(scriptless):
        out.append((scriptless[:m.start(1)].count("\n") + 1, m.group(1)))
    return out


CLASS_ATTR = re.compile(r"""class\s*=\s*("([^"]*)"|'([^']*)')""", re.I)
# Every string literal a script can hold: the three quotings, with escapes
# consumed so a quote inside a string does not end it early.
STRING_LITERAL = re.compile(
    r'"((?:[^"\\\n]|\\.)*)"'
    r"|'((?:[^'\\\n]|\\.)*)'"
    r"|`((?:[^`\\]|\\.)*)`", re.S)


def reachable_text(text):
    """Everything a class name can be reached FROM, and nothing else.

    TWO PLACES ONLY, and being strict here is the whole of the predicate. A
    class reaches an element either through a `class` attribute in the markup or
    through a STRING LITERAL in the script that builds the markup, whether that
    is `el("div", "acts")`, `classList.add("on")`, a selector handed to
    `querySelector`, or a concatenation like `"invact" + (waiting ? " greyed" :
    "")`, where both words are still literal text.

    STRING LITERALS, NOT THE WHOLE SCRIPT, and this is the part that decides
    whether the check is worth anything. Read whole, a script rescues every
    short class name that happens to spell a variable: a first run of this left
    `.cdisc .n` and `.strip .act` standing because `n` and `act` are ordinary
    identifiers, so half a deleted screen's stylesheet survived and read worse
    than the whole of it had. A class name only ever reaches an element as text,
    so text is the only place worth looking.

    THE RECORD'S PROSE IS NOT ONE OF THEM. These files are a page of writing
    wrapped around a rendering, and class names here are ordinary English:
    `.sheet` was rescued from a first run by the word "sheet" in a comment
    explaining that the review sheet is a different screen, which is the dead
    rule's own docstring answering for it. So the prose, the headings and the
    comments are excluded, and only the two places a class can actually be
    applied are read.

    WHAT IT CONSERVATIVELY KEEPS. `review-send.html` carries the whole document
    it previews as one enormous string literal (PRD 10c), so every class name in
    that document counts as reachable from this page too. That is a false
    negative in the safe direction, and this check's mistakes must never delete
    a live rule.
    """
    parts = [m.group(2) if m.group(2) is not None else m.group(3)
             for m in CLASS_ATTR.finditer(text)]
    for script in SCRIPT_BLOCK.finditer(text):
        body = CSS_COMMENT.sub(" ", script.group(0))
        for lit in STRING_LITERAL.finditer(body):
            parts.append(lit.group(1) or lit.group(2) or lit.group(3) or "")
    return "\n".join(parts)


def rules_of(css):
    """(line within this stylesheet, selector) for every top level rule.

    At-rules that CONTAIN rules are descended into; at-rules whose body is
    declarations (`@font-face`, `@import`, `@charset`, `@keyframes` frames) are
    skipped, because they name no class."""
    out = []
    depth = 0
    buf = []
    line = 1
    start_line = None
    nesting_at = ("@media", "@supports", "@container", "@layer", "@scope")
    for ch in css:
        if ch == "{":
            selector = "".join(buf).strip()
            buf = []
            if selector.startswith("@"):
                keyword = selector.split(None, 1)[0].lower()
                if keyword in nesting_at:
                    start_line = None
                    continue
                depth += 1
            else:
                if depth == 0 and selector:
                    out.append((start_line or line, selector))
                depth += 1
            start_line = None
            continue
        if ch == "}":
            if depth > 0:
                depth -= 1
            buf = []
            start_line = None
            if ch == "\n":
                line += 1
            continue
        if depth == 0:
            if not ch.isspace() and start_line is None:
                start_line = line
            buf.append(ch)
        if ch == "\n":
            line += 1
    return out


def rules_in(text):
    """(file line, selector) for every rule in every stylesheet the page owns."""
    out = []
    for first_line, css in top_level_styles(text):
        stripped = CSS_COMMENT.sub(lambda m: blank(m.group(0)), css)
        for line, selector in rules_of(stripped):
            out.append((first_line + line - 1, " ".join(selector.split())))
    return out


def shell_selectors(root):
    """Every selector the shared shell defines.

    A DESIGN FILE DOES NOT OWN THESE. It cannot load `shell/`, so it carries a
    verbatim copy of each part it declares, and `check-design-shell-inline.sh`
    refuses a copy that has drifted. A part is one unit: a file carries it whole
    or declares it carries none, so a rule inside a part that this particular
    screen does not draw is a question about how the SHELL is cut (ovation#179),
    not about this file having leftovers. Judging it here would tell every file
    to delete a line the other check requires it to keep, which is two guards
    ordering opposite work.

    The exemption is by SELECTOR, so a file redefining a shell class under its
    own rule is exempted too. That is deliberate rather than overlooked: a
    screen redefining a shell class is ovation#132's subject and has its own
    tool, and the count below says how many rules were passed over this way so
    the exemption cannot grow quietly (L96)."""
    out = set()
    for path in sorted(glob.glob(os.path.join(root, "shell", "*.css"))):
        css = CSS_COMMENT.sub(lambda m: blank(m.group(0)), open(path, encoding="utf-8").read())
        for _, selector in rules_of(css):
            out.add(" ".join(selector.split()))
    return out


def selector_parts(selector):
    """A selector list split into the selectors it actually holds.

    `\u002ea, .b` is TWO selectors and a rule carrying it is only dead when
    BOTH are, so a comma is never treated as part of one selector."""
    return [p.strip() for p in selector.split(",") if p.strip()]


def dead_rules(text, shell=frozenset()):
    """(line, selector, [unreachable class names]) for every rule the FILE OWNS
    that nothing can reach, the number judged, and the number left to the shell.
    `None` when the page carries no stylesheet of its own.

    EVERY CLASS IN ONE SELECTOR HAS TO BE REACHABLE, not merely one of them.
    `.crow.sel` needs both words on one element and `.disc .n` needs both in one
    tree, so a rule for a deleted screen goes on standing whenever any word in
    it is also used by a screen that survived: a first run of this left
    `.crow.sel`, `.filterbar .act` and `.cdisc .n` behind, which is half a
    stylesheet for a screen the file does not draw and reads worse than the
    whole of it did.
    """
    styles = top_level_styles(text)
    if not any(css.strip() for _, css in styles):
        return None, 0, 0
    reachable = reachable_text(text)
    seen = {}

    def can_reach(name):
        if name not in seen:
            seen[name] = re.search(WORD.format(re.escape(name)), reachable) is not None
        return seen[name]

    dead = []
    counted = 0
    inherited = 0
    for line, selector in rules_in(text):
        if not CLASS_IN_SELECTOR.search(selector):
            continue
        if selector in shell:
            inherited += 1
            continue
        counted += 1
        missing = set()
        alive = False
        for part in selector_parts(selector):
            names = sorted(set(CLASS_IN_SELECTOR.findall(part)))
            absent = [n for n in names if not can_reach(n)]
            if not absent:
                alive = True
                break
            missing.update(absent)
        if not alive:
            dead.append((line, selector, sorted(missing)))
    return dead, counted, inherited


def main(argv):
    files = argv[1:]
    if not files:
        files = sorted(glob.glob(os.path.join(DEFAULT_ROOT, "*.html")))
        if not files:
            print("CANNOT MEASURE: no design file under %s, so nothing was "
                  "compared and a pass here would be a green tick over an unrun "
                  "check." % DEFAULT_ROOT)
            return 2
    for f in files:
        if not os.path.isfile(f):
            print("CANNOT MEASURE: no such design file: %s" % f)
            return 2

    shell = shell_selectors(DEFAULT_ROOT)
    total_rules = 0
    total_dead = 0
    total_inherited = 0
    no_style = []
    for path in files:
        text = open(path, encoding="utf-8").read()
        found, counted, inherited = dead_rules(text, shell)
        total_inherited += inherited
        name = os.path.basename(path)
        if found is None:
            no_style.append(name)
            continue
        total_rules += counted
        for line, selector, names in found:
            total_dead += 1
            print("  %s:%d: DEAD, `%s` cannot match: %s never named outside "
                  "the stylesheet"
                  % (name, line, selector,
                     ", ".join("." + n for n in names)))
        if not found:
            print("  %s: %d rule(s) of its own naming a class, every one "
                  "reachable, %d left to the shell"
                  % (name, counted, inherited))

    if no_style:
        print("CANNOT MEASURE: %s carries no stylesheet of its own, so nothing "
              "in it was compared, and a file with no rules must not report the "
              "same thing as a file whose rules were all read."
              % ", ".join(no_style))
        return 2
    if not total_rules:
        print("CANNOT MEASURE: %d design file(s) read and not one rule names a "
              "class, so this compared nothing." % len(files))
        return 2
    if total_dead:
        print("REFUSED: %d of %d rule(s) across %d design file(s) are reachable "
              "by nothing on the page that carries them. Delete them, or give "
              "the file an element that uses them."
              % (total_dead, total_rules, len(files)))
        return 1
    print("OK: %d rule(s) owned by %d design file(s), every one reachable. "
          "%d further rule(s) come verbatim from shell/ and are that part's "
          "business rather than any one file's."
          % (total_rules, len(files), total_inherited))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
