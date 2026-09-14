#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Refuse a construct Ovation has ruled out, anywhere in its app sources.

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

RULE THREE, BLOCKING WORK ON THE COOPERATIVE POOL (plan 1.9, ovation#85). Ported
IN SUBSTANCE from danwright32/downbeat Downbeat/DownbeatTests/
CooperativePoolTests.swift @ 66966ccf9bab12427fff9949cf566d188616bafe, and
deliberately NOT line by line, which is recorded here because a port that changes
shape has to say so.

Downbeat's is a Swift suite carrying its own file walk, its own comment stripper
borrowed from a third suite, and its own "there are sources to check" floor.
Ovation already has all three, here, and they are the parts most easily got
subtly wrong. Copying the suite would have shared the DATA (one token) while
copying the LOGIC beside it, which is not consolidation and is the exact defect
this file's own header cites (L370). What survives the port unchanged is
everything that MATTERS about the original: the token, the empty exemption list,
the reason each exemption must carry, comments stripped so the file explaining
the trap is not itself the first violation, and the scope.

THE SCOPE IS THE SAME AND SO IS ITS REASON. Downbeat scans app sources only,
because a test suite that starves itself fails loudly and immediately, which is
its own report, and the harm being guarded against is an app that goes quiet in
Dan's hands. Ovation's scan root is the app sources, so that holds without
anything being added.

WHY IT MATTERS HERE SPECIFICALLY, in the plan's own words: "Ovation runs Vision
on every receipt, so this defect is otherwise pre-ordained." Vision on a receipt
image blocks, and so does a keychain read (ovation#76).

RULE FOUR, DISK WORK WHILE DRAWING (ovation#255). Written after the same mistake
was made twice in one file in one evening, in the Settings window (ovation#247):
the archive list, which VERIFIES every backup by hashing every file in it, was
read from a view's body, and an archive's manifest was read from a confirmation
dialog's message. A body is re-evaluated constantly, on the main thread, so both
put disk work on the drawing thread on every redraw, which on a folder that syncs
to a NAS is a frozen window: the defect ovation#246 exists to prevent. Neither
was caught by anything, and the class reads as harmless at every call site,
because a body "just describes the screen" and a read there looks like a getter.

It is the one rule with a SCOPE rather than a token list, because the same call
is right in one place and wrong in another. It applies only in a file declaring
a SwiftUI view, and only inside the code that DRAWS: `body`, anything declared
to return `some View`, anything marked `@ViewBuilder`, and every computed
property, since those are what a body reads. Inside that, the closures a press
or an appearance runs are NOT drawing and are skipped: a Button's action,
`.task`, `.onAppear`, `.onDisappear`, `.onChange`, `.onReceive`, `.onSubmit`,
`.onTapGesture`, `.refreshable`, and anything passed as `action:`. A Button's
label still is drawing.

It names the READERS rather than every filesystem call: Ovation's own backup
and store readers, which are short, live here and are what actually cost
something, plus `FileManager` and a read `contentsOf:` a URL. Every reader in
its pattern has a call in `DRAWING_RULE["readers"]`, which the suite writes into
a body (refused) and into an action (allowed), so the scope is seen to fail in
both directions before it is trusted (L1).

Its known gaps, stated rather than discovered: a plain `func` a body calls is not
followed into; an extension of a view that does not restate the conformance is
not recognised as a view; a computed property on some OTHER type in a file that
also declares a view is treated as drawing; and a multi line string literal
holding a brace can end a region early. The alternative to all four is a Swift
parser.

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
            "Money is Int64 minor units and hours are HUNDREDTHS of an hour (plan 1.4, "
            "corrected by ovation#127). A single "
            "conversion through a floating point type is a rounding error small "
            "enough to survive review and large enough to matter across a tax year."
        ),
    },
    {
        "name": "blocking work on the cooperative pool",
        "tokens": ("Task.detached",),
        "because": (
            "The cooperative pool is about one thread per core and does not grow, "
            "so work that BLOCKS a thread never gives it back and enough of them "
            "starve every other await in the app (L241, plan 1.9). Task.detached "
            "reads like 'run this somewhere else', and somewhere else is that same "
            "fixed pool. Use a dispatch global queue, which grows. Ovation runs "
            "Vision on every receipt and reads the keychain, which is exactly this "
            "shape, so the rule is that the tree stays free of it."
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

# RULE FOUR, which is scoped rather than tokenised (see the header). `readers` is
# one call per reader, written the way it appears in code, and the suite puts each
# into a body and into an action. A reader added to the pattern belongs here too,
# or it is forbidden by a check nothing exercises (L217).
DRAWING_RULE = {
    "name": "disk work while drawing",
    "readers": (
        "restore.archives()",
        "service.verify(archive: url)",
        "service.manifest(of: url)",
        "restore.consequence(of: name)",
        "restore.restore(name)",
        "service.takeBackup(now: now)",
        "service.reverifyOneArchive(now: now)",
        "service.folderBytes()",
        "service.preRestoreSnapshots()",
        "FileManager.default.fileExists(atPath: path)",
        "Data(contentsOf: url)",
        "String(contentsOf: url)",
        "StoreDocumentReferences.read(from: store)",
    ),
    "pattern": re.compile(
        r"\.(archives|verify|manifest|consequence|restore|takeBackup|reverifyOneArchive"
        r"|folderBytes|preRestoreSnapshots)\s*\("
        r"|\b(FileManager)\b"
        r"|\b(Data|String)\s*\(\s*contentsOf\s*:"
        r"|\b(StoreDocumentReferences)\b"
    ),
    "because": (
        "A SwiftUI body, anything returning some View, and the computed properties a "
        "body reads are evaluated on every redraw, on the main thread. Reading files "
        "or verifying backups there freezes the window, and worst on a folder that "
        "syncs to a NAS (ovation#255, ovation#246). Do the work once, where a press "
        "or an appearance starts it, off the main actor where it is heavy, and draw "
        "what it stored."
    ),
}

VIEW_TYPE = re.compile(r"\b(?:struct|class|extension)\s+\w+[^{]*?:\s*[^{]*?\bView\b[^{]*\{")
DRAWING_REGIONS = (
    re.compile(r"\bvar\s+\w+\s*:\s*some\s+View\s*\{"),
    re.compile(r"\bfunc\s+\w+\s*\([^{]*?\)\s*->\s*some\s+View\s*\{"),
    re.compile(r"@ViewBuilder\s+(?:(?:private|fileprivate|internal|public)\s+)?(?:var|func)\s[^{]*\{"),
    # A computed property of any other type in a view is read by the body.
    re.compile(r"\bvar\s+\w+\s*:\s*[^={}\n]+\{"),
)
# The closures a press or an appearance runs. Each ends at the brace that opens
# the closure, and everything from there to its matching brace is skipped.
ACTION_OPENERS = re.compile(
    r"(?:\bButton\s*(?:\((?:[^()]|\([^()]*\))*\))?\s*"
    r"|\.(?:task|onAppear|onDisappear|onSubmit|onTapGesture|refreshable)"
    r"\s*(?:\((?:[^()]|\([^()]*\))*\))?\s*"
    r"|\.(?:onChange|onReceive)\s*\((?:[^()]|\([^()]*\))*\)\s*"
    r"|\baction\s*:\s*)\{"
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

# THE EXEMPTION LIST STARTS EMPTY FOR RULE THREE TOO, and that is a finding
# rather than an oversight: no Ovation source uses `Task.detached` at all today,
# so the rule is that it stays that way. An inherited exemption carrying no
# written reason is evidence nobody reasoned about it rather than evidence it was
# considered (L233), so nothing was carried across from the sibling.
#
# EMPTY ON PURPOSE, and it stays that way until something earns a place.
# Each entry is "<path relative to the scan root> : <rule name> # <the reason>",
# and it lifts THAT rule from THAT file and nothing else (ovation#210). An entry
# with no reason is refused rather than honoured: an exemption carrying no
# written reason, sitting beside neighbours that have one, is evidence nobody
# reasoned about it (L233). An entry naming no rule, or one that does not exist,
# is refused too.
DEFAULT_ALLOWLIST = (
    # A COLOUR CHANNEL IS NOT MONEY, and this is the one place the distinction
    # has to be written down. The rule above forbids floating point because
    # Ovation's money is Int64 minor units and its hours are hundredths, and a
    # single conversion through a Double is a rounding error small enough to
    # survive review. `Color(.sRGB, red:green:blue:opacity:)` takes Doubles and
    # there is no integer form of it, so drawing the agreed palette at all
    # requires three of them.
    #
    # THE HONEST ALTERNATIVES WERE BOTH WORSE. Writing the channels as bare
    # decimal literals removes the word `Double` and passes this check while
    # changing nothing about the arithmetic, and it would throw away the hex the
    # design record is written in, which is what keeps this file comparable with
    # docs/design/shell/palette.css. Converting through `CGFloat` passes for the
    # same empty reason: it is not in the token list above and it is still
    # floating point. Either would be evading the rule by spelling.
    #
    # THIS EXEMPTION IS WRONG THE MOMENT THAT FILE HOLDS ANYTHING BUT COLOUR.
    # It is scoped to one file that contains nothing else, and the parser above
    # refuses an entry naming a file that is not there, so the reason cannot
    # outlive what it exempts.
    "Roster/OvationPalette.swift : floating point money # colour channels, not money: SwiftUI's Color "
    "takes Doubles and has no integer form, and this file holds nothing but the "
    "palette quoted from docs/design/shell/palette.css",
)

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


def blank_strings(code):
    """The same text with every single line string literal's contents blanked, so
    a brace inside a string is not counted, and every offset still lines up."""
    out = []
    in_string = False
    escaped = False
    for ch in code:
        if in_string:
            if escaped:
                escaped = False
                out.append(" ")
            elif ch == "\\":
                escaped = True
                out.append(" ")
            elif ch == '"' or ch == "\n":
                in_string = False
                out.append(ch)
            else:
                out.append(" ")
        else:
            if ch == '"':
                in_string = True
            out.append(ch)
    return "".join(out)


def matching_brace(text, open_index):
    depth = 0
    for index in range(open_index, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    return len(text) - 1


def drawing_findings(lines):
    """(line number, reader) for every reader inside code that draws, in a file
    declaring a view. Nothing at all for a file that declares none."""
    code = blank_strings("\n".join(text for _, text in strip_comments(lines)))
    if not VIEW_TYPE.search(code):
        return []

    regions = []
    for pattern in DRAWING_REGIONS:
        for match in pattern.finditer(code):
            start = match.end() - 1
            regions.append((start, matching_brace(code, start)))
    regions.sort()
    outermost = []
    for start, end in regions:
        if outermost and start <= outermost[-1][1]:
            continue
        outermost.append((start, end))

    findings = []
    for start, end in outermost:
        drawn = list(code[start:end + 1])
        text = "".join(drawn)
        for opener in ACTION_OPENERS.finditer(text):
            brace = opener.end() - 1
            for index in range(brace, matching_brace(text, brace) + 1):
                if drawn[index] != "\n":
                    drawn[index] = " "
        for reader in DRAWING_RULE["pattern"].finditer("".join(drawn)):
            token = next(group for group in reader.groups() if group)
            findings.append((code.count("\n", 0, start + reader.start()) + 1, token))
    return findings


def rule_names():
    """Every rule an exemption can name, the scoped one included, in order."""
    return [rule["name"] for rule in RULES] + [DRAWING_RULE["name"]]


def parse_allowlist(entries, root, problems):
    """The (file, rule name) pairs the allowlist exempts.

    AN ENTRY NAMES A RULE AS WELL AS A FILE (ovation#210). It used to name only a
    file, and the scan skipped that file entirely, so an exemption written for one
    rule silently lifted all of them: the palette's, written for floating point
    colour channels, took the file out of the Task and calendar rules too, and the
    scanned count dropping by one was the only sign. An entry naming no rule is
    refused rather than read as covering every rule, because that reading is the
    defect, and an entry naming a rule that does not exist is refused because it
    exempts nothing while reading as an exemption.
    """
    known = rule_names()
    allowed = set()
    unknown_rule = False
    for entry in entries:
        entry = entry.strip()
        if not entry:
            continue
        target, separator, reason = entry.partition("#")
        path, colon, rule = target.partition(":")
        path, rule = path.strip(), rule.strip()
        if not separator or not reason.strip():
            problems.append(f"the allowlist entry '{path or entry}' carries no reason")
            continue
        if not colon or not rule:
            problems.append(
                f"the allowlist entry '{path}' names no rule, and an exemption from "
                "every rule is not one anybody reasoned about: write it as "
                "'<file> : <rule> # <reason>'"
            )
            continue
        if rule not in known:
            problems.append(f"the allowlist entry '{path}' names a rule that does not exist, '{rule}'")
            unknown_rule = True
            continue
        if not os.path.isfile(os.path.join(root, path)):
            problems.append(
                f"the allowlist entry '{path}' names a file that is not there, "
                "so its reason has outlived it"
            )
            continue
        allowed.add((path, rule))
    if unknown_rule:
        problems.append("the rules are: " + ", ".join(known))
    return allowed


def main(argv):
    if "--list" in argv:
        for rule in RULES:
            for token in rule["tokens"]:
                print(token)
        return 0
    if "--list-drawing" in argv:
        for reader in DRAWING_RULE["readers"]:
            print(reader)
        return 0
    if "--list-rules" in argv:
        for name in rule_names():
            print(name)
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
            # Only the rules this file is not exempt from. A file exempt from
            # EVERY rule was not scanned at all, and is not counted as scanned, so
            # an allowlist that has grown to cover everything still reads as
            # nothing checked rather than as a clean tree (L98).
            applying = [rule for rule in RULES if (relative, rule["name"]) not in allowed]
            drawing_applies = (relative, DRAWING_RULE["name"]) not in allowed
            if not applying and not drawing_applies:
                continue
            scanned += 1
            with open(path, "r", encoding="utf-8", errors="replace") as handle:
                lines = handle.read().splitlines()
            for number, code in strip_comments(lines):
                for rule in applying:
                    for match in rule["pattern"].finditer(code):
                        findings.append((relative, number, match.group(1), rule["name"]))
            if drawing_applies:
                for number, token in drawing_findings(lines):
                    findings.append((relative, number, token, DRAWING_RULE["name"]))

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
        fired = [rule for rule in RULES + (DRAWING_RULE,)
                 if any(f[3] == rule["name"] for f in findings)]
        for rule in fired:
            print(f"{rule['name']}: {rule['because']}")
        print(f"{len(findings)} occurrence(s). If one of these is genuinely outside the")
        print("rule, add it to DEFAULT_ALLOWLIST in this script, naming the file AND the")
        print("rule, WITH ITS REASON.")
        return 1

    print(f"OK: scanned {scanned} Swift file(s) under {root}, no forbidden constructs.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
