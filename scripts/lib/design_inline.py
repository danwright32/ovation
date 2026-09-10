"""How a design file's inlined COPY of something is compared with its source.

ovation#111 established the shape and ovation#120 gave it a second subject, so
this is the one implementation both read rather than two that drift apart.

A design file must be one self contained document that reaches outside itself
never (ovation#114), so it cannot load `rules/*.js` or `shell/*.css` at render
time: it carries its own copy of each. Two copies of one thing with nothing
comparing them is L370, and it had already gone wrong before either guard
existed. Sharing the DATA while copying the code that applies it is not
consolidation, which is why this file exists rather than a second `longest_run`
beside the second checker.

HOW A COPY IS COMPARED. The source is normalized to its code lines, comments
removed and whitespace collapsed, and that sequence must appear inside the design
file as a CONTIGUOUS RUN. Not as lines that all occur somewhere: a check written
as several conditions over one body of text is satisfied by several unrelated
places in it (L178), and a source whose lines are present but interleaved with
others is a source the design file does not actually run. Comments are stripped
because the design file rewraps them when the text is pasted into its own script
or stylesheet, and a comparison that broke on that could only ever match by luck.

Sourced by scripts/check-design-rules-inline.sh and
scripts/check-design-shell-inline.sh. Never run on its own.
"""
import re


def strip_comments(text):
    """Block and line comments out, so rewrapping prose cannot fail a match.

    String literals are left alone rather than parsed: the sources are code we
    wrote, and the alternative is a JavaScript and CSS tokenizer whose own bugs
    would be reported as design drift.
    """
    text = re.sub(r"/\*.*?\*/", "\n", text, flags=re.S)
    return re.sub(r"(^|\s)//[^\n]*", r"\1", text)


def significant_lines(text):
    """The comparable shape of a file: its code lines, whitespace collapsed."""
    lines = []
    for raw in strip_comments(text).splitlines():
        collapsed = " ".join(raw.split())
        if collapsed:
            lines.append(collapsed)
    return lines


COMMENT = re.compile(r"/\*.*?\*/|(?:^|\s)//[^\n]*", re.S | re.M)


def comparable_tokens(text):
    """The comparable shape of a file INCLUDING what it says about itself.

    ovation#144. `significant_lines` strips comments, deliberately: a design file
    rewraps a rule's prose when the rule is pasted into its script, so a
    comparison that broke on rewrapping could only ever match by luck. The
    consequence was that the guard enforced the CODE being identical and let the
    REASONING diverge, and these comments are not decoration: a rule file's
    comment is where the decision, its measurement and the person who made it are
    recorded. `rules/duration.js` carries who chose the 12 hour cap and what it
    was chosen against; `rules/waiting.js` carries the workflow in Dan's own
    words. So the two copies could give different reasons for the same rule and
    the guard reported OK, and on 2026-09-08 the cap's provenance was added to
    one copy by hand with the guard green before and after.

    A COMMENT BECOMES ONE TOKEN, whitespace collapsed across its line breaks, so
    rewrapping the same sentence is tolerated and a CHANGED sentence is not. Code
    lines are collapsed exactly as `significant_lines` collapses them, so the two
    readings cannot disagree about what a line is.
    """
    tokens = []
    at = 0
    for found in COMMENT.finditer(text):
        tokens.extend(_code_tokens(text[at:found.start()]))
        said = " ".join(found.group(0).split())
        if said:
            tokens.append("said: " + said)
        at = found.end()
    tokens.extend(_code_tokens(text[at:]))
    return tokens


def _code_tokens(text):
    return [" ".join(raw.split()) for raw in text.splitlines() if raw.split()]


def longest_run(source_lines, file_lines):
    """How many of the source's lines appear contiguously, at best, in the file.

    Returns the length of the longest prefix of `source_lines` that occurs as a
    contiguous run anywhere in `file_lines`. len(source_lines) means the whole
    thing is carried verbatim; zero means none of it is there at all.
    """
    if not source_lines:
        return 0
    best = 0
    for start in range(len(file_lines)):
        if file_lines[start] != source_lines[0]:
            continue
        run = 0
        while (run < len(source_lines)
               and start + run < len(file_lines)
               and file_lines[start + run] == source_lines[run]):
            run += 1
        if run > best:
            best = run
        if best == len(source_lines):
            break
    return best


def html_files(names):
    """The design files in a directory listing, in a stable order."""
    return sorted(n for n in names if n.lower().endswith((".html", ".htm")))


DECLARES_UNSHELLED = "NOT SHELLED:"


def declared_parts(text):
    """Which shell parts a design file says it does not carry, and why.

    The part is named first so the declaration is machine readable, and the
    reason follows it, because a declaration carrying no reason is evidence
    nobody reasoned about it rather than a decision (L233).

    IT LIVES HERE RATHER THAN IN THE CHECK THAT INVENTED IT because a second
    check now asks the same question. `check-design-sidebar-card.sh` compares
    the rail across the files that DRAW an app window, and the file that draws
    none is the file that already declares it carries no window.css. Sharing the
    declaration while copying the code that reads it is not consolidation
    (L370): the two would drift, and each would go on reading as correct.
    """
    found = {}
    for raw in text.splitlines():
        if DECLARES_UNSHELLED not in raw:
            continue
        said = raw.split(DECLARES_UNSHELLED, 1)[1]
        said = said.replace("*/", " ").strip()
        match = re.match(r"([A-Za-z0-9_.\-]+)[,:\s]+(.*)", said)
        if not match:
            continue
        reason = " ".join(match.group(2).split())
        if reason:
            found[match.group(1)] = reason
    return found
