#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Refuse a hosted test that runs without a time limit.

    check-hosted-time-limits.sh

ovation#652. The hosted suite prints its test lines only when the whole run
ends, so a hosted test that hangs holds the macOS CI job silent until the job's
own cutoff, and the log cannot say which test it was. On 2026-09-30 a click
test hung that way twice (runs 36747839715 and 36794027294) and cost two hours
to diagnose. A one minute `.timeLimit` on that suite turned the same hang into
a failure that named the test, which is what proved the cause (L110).

So every hosted test carries a limit, and this scan is what keeps the next
suite from being added without one (L613). A rule each new file has to
remember is enforced by nothing unless something reads the files.

WHAT COVERS A TEST. Swift Testing hands a suite's traits to everything inside
it, nested suites included, so a test is covered by a `.timeLimit` on its own
`@Test`, or on the `@Suite` of any type enclosing it. A test written in an
extension belongs to the type extended, so it is covered when that type's own
declaration carries the limit. A test at file scope has only its own.

THE CEILING IS ONE MINUTE, MEASURED. Over the three most recent green runs of
main (CI runs 36893962432, 37021948571 and 37055609828, 2026-10-01 and 02) the
slowest hosted test took 13.5 seconds, the invoice screen capture, and the
whole hosted run 68 to 75 seconds, one test at a time. One minute is over four
times the slowest, and the shortest limit Swift Testing can express. A limit
longer than the ceiling is refused, because a limit too long to fire before
the job is cancelled names nothing, and a test that genuinely needs more is a
change to CEILING_MINUTES here with its measurement, not a quiet number in a
test file. A limit this scan cannot read (a variable, an expression) is
refused for the same reason: a limit nobody can see the length of cannot be
judged against anything.

WHAT THE LIMIT CANNOT DO, said so it is not mistaken for more. Swift Testing
records the failure when the limit passes, but a test stuck on the main thread
inside AppKit may still hold the process, so the CI job's own timeout stays as
the backstop. The limit is what makes the common hang, an await nothing ever
answers, fail by name.

COMMENTS AND STRINGS ARE NOT READ. A limit written in a comment is prose, and a
test name holding a brace must not end its suite early, so both are blanked
before anything is matched, line breaks kept so line numbers stay true.

A RUN THAT JUDGED NOTHING IS REFUSED: no hosted folder, or one holding no
`@Test`, would otherwise read as every suite having a limit (L98).

Exit codes: 0 every hosted test is covered, 1 refused.
Seam: OVATION_REPO_ROOT, so the suite drives this over staged trees (L1, L2).
"""
import os
import re
import sys

REPO_ROOT = os.environ.get("OVATION_REPO_ROOT") or os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))
HOSTED = "OvationHostedTests"
CEILING_MINUTES = 1
ADVICE = "@Suite(.timeLimit(.minutes(%d)))" % CEILING_MINUTES

# Comments and string literals, in one alternation so a `//` inside a string is
# the string's and a quote inside a comment is the comment's. Multi line strings
# come first, because `\"\"\"` would otherwise read as an empty string and a quote.
PROSE = re.compile(r'"""[\s\S]*?"""|"(?:\\.|[^"\\\n])*"|/\*[\s\S]*?\*/|//[^\n]*')
DECLARATION = re.compile(r"\b(struct|class|enum|actor|extension)\s+([A-Za-z_][\w.]*)")
NOT_A_NAME = {"func", "var", "let", "subscript", "init", "deinit", "case"}
TEST = re.compile(r"@Test\b")
SUITE = re.compile(r"@Suite\b")
TIME_LIMIT = re.compile(r"\.timeLimit\s*\(")
MINUTES = re.compile(r"\A\.timeLimit\s*\(\s*\.minutes\s*\(\s*(\d+)\s*\)\s*\)\Z")


def blank(match):
    return re.sub(r"[^\n]", " ", match.group(0))


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def closing(code, opening):
    """Offset just past the bracket matching the one at `opening`."""
    pairs = {"(": ")", "{": "}"}
    want, depth = pairs[code[opening]], 0
    for i in range(opening, len(code)):
        if code[i] == code[opening]:
            depth += 1
        elif code[i] == want:
            depth -= 1
            if depth == 0:
                return i + 1
    return len(code)


def arguments(code, at):
    """The parenthesised arguments of the attribute starting at `at`, or ''."""
    name_end = at + re.match(r"@\w+\s*", code[at:]).end()
    if name_end < len(code) and code[name_end] == "(":
        return code[name_end:closing(code, name_end)]
    return ""


def attributes_before(code, start):
    """Everything written before a declaration back to the previous statement
    boundary at bracket depth zero: its attributes and modifiers."""
    depth = 0
    i = start - 1
    while i >= 0:
        c = code[i]
        if c == ")":
            depth += 1
        elif c == "(":
            depth -= 1
        elif c in "{};" and depth == 0:
            break
        i -= 1
    return code[i + 1:start]


def limits_in(region):
    """The text of each `.timeLimit(...)` inside the `@Suite(...)` or `@Test(...)`
    attributes of a region."""
    found = []
    for attribute in list(SUITE.finditer(region)) + list(TEST.finditer(region)):
        args = arguments(region, attribute.start())
        for limit in TIME_LIMIT.finditer(args):
            found.append(args[limit.start():closing(args, limit.end() - 1)])
    return found


def judge(limits):
    """None when a limit within the ceiling is present, else what is wrong."""
    if not limits:
        return "no limit"
    for text in limits:
        minutes = MINUTES.match(" ".join(text.split()))
        if not minutes:
            return "a limit this check cannot read (%s)" % " ".join(text.split())
        if int(minutes.group(1)) > CEILING_MINUTES:
            return "%s minutes, above the ceiling of %d" % (minutes.group(1), CEILING_MINUTES)
    return None


def main():
    os.chdir(REPO_ROOT)
    if not os.path.isdir(HOSTED):
        print("REFUSED: %s is not there, so this guard is checking nothing." % HOSTED)
        print("    It is the hosted target's folder, whose every test must carry a time limit.")
        return 1

    files = []
    for directory, _, names in os.walk(HOSTED):
        for name in sorted(names):
            if name.endswith(".swift"):
                path = os.path.join(directory, name)
                text = open(path, encoding="utf-8", errors="replace").read()
                files.append((path, PROSE.sub(blank, text)))
    files.sort()

    # Every type declaration, with its body's span and its own verdict.
    types = []
    for path, code in files:
        for match in DECLARATION.finditer(code):
            if match.group(2) in NOT_A_NAME:
                continue
            brace = code.find("{", match.end())
            if brace < 0:
                continue
            region = attributes_before(code, match.start())
            types.append({
                "path": path, "kind": match.group(1), "name": match.group(2).split(".")[-1],
                "line": line_of(code, match.start()), "open": brace, "close": closing(code, brace),
                "verdict": judge(limits_in(region)),
            })
    declared = {t["name"]: t["verdict"] for t in types if t["kind"] != "extension"}

    refused, suites, tests = {}, {}, 0
    for path, code in files:
        for match in TEST.finditer(code):
            tests += 1
            line = line_of(code, match.start())
            enclosing = sorted((t for t in types
                                if t["path"] == path and t["open"] < match.start() < t["close"]),
                               key=lambda t: t["open"])
            own = judge(limits_in("@Test" + arguments(code, match.start())))
            # A suite is named where it is declared, so the fix lands in one place;
            # a test at file scope has no suite and is named at its own line.
            key = ("%s:%d %s" % (path, enclosing[-1]["line"], enclosing[-1]["name"])
                   if enclosing else "%s:%d" % (path, line))
            suites[key] = suites.get(key, 0) + 1
            verdicts = [own] + [declared.get(t["name"], "no limit") if t["kind"] == "extension"
                                else t["verdict"] for t in enclosing]
            if any(v is None for v in verdicts):
                continue
            # The most telling reason: a limit that is there but wrong outranks none.
            reason = next((v for v in verdicts if v != "no limit"), "no limit")
            entry = refused.setdefault(key, {"reason": reason, "lines": []})
            entry["lines"].append(line)

    if tests == 0:
        print("REFUSED: %s holds no @Test, so this guard is checking nothing." % HOSTED)
        print("    Either the hosted tests moved or the way they are declared changed; say which, here.")
        return 1

    if refused:
        print("REFUSED: a hosted test runs without a time limit it can fail by. The hosted suite")
        print("         prints its results only when the run ends, so a test that hangs holds CI")
        print("         silent until the job is cancelled and never says which it was (ovation#652).")
        def place(key):
            path, _, rest = key.partition(":")
            return (path, int(rest.split(" ")[0]))
        for key in sorted(refused, key=place):
            entry = refused[key]
            if " " not in key:
                where = ""
            elif len(entry["lines"]) == suites[key]:
                where = (", on its one test" if suites[key] == 1
                         else ", on all %d of its tests" % suites[key])
            else:
                where = ", on the test%s at line %s" % (
                    "s" if len(entry["lines"]) > 1 else "", ", ".join(map(str, entry["lines"])))
            print("    %s: %s%s" % (key, entry["reason"], where))
        print("         Give the suite %s, or each of its tests" % ADVICE)
        print("         .timeLimit(.minutes(%d)). A test that needs longer is a change to" % CEILING_MINUTES)
        print("         CEILING_MINUTES in scripts/check-hosted-time-limits.sh, with its measurement.")
        return 1

    print("OK: all %d tests in %d hosted suites carry a time limit of at most %d minute%s."
          % (tests, len([k for k in suites if " " in k]), CEILING_MINUTES, "" if CEILING_MINUTES == 1 else "s"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
