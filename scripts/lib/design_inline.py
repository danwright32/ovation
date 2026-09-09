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
