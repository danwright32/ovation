''''exec python3 "$0" "$@" #'''
__doc__ = """Refuse a writer the app declares and never uses, unless it is listed with the issue that wires it.

    check-writers-wired.sh

ovation#441. InvoiceNumberAllocator, InvoiceCloser and PaymentAllocator were each
built as a @ModelActor with its own tests and called by nothing in the app, so each
read as done from every angle except the one that counts (L3: built is not wired),
and the backlog read through the domain layer said the milestone was further along
than it is. Found by accident, twice.

WHAT COUNTS AS USED: the type's name referenced, constructed or through a static
member, in a Swift file of the app other than its own. A test is not the app. It
asks about the TYPE rather than its methods, because method names collide
(`cancel`, `release` and `allocate` are all ordinary words), and a type nothing in
the app ever names cannot have a caller.

THE LIST OF THE LEGITIMATELY UNWIRED is scripts/unwired-writers.tsv, one writer per
line with the issue that wires it and why: a writer landing a commit before its
screen is ordinary. An entry with no issue is refused, because an exemption must
say what ends it (L129, L233), and an entry for a writer that is now wired is
refused as stale, or the list would go on excusing what no longer needs it (L346).
Each listed writer is still printed, with its issue, so the list is read.

THE SECOND HALF OF THE JOURNEY, ovation#485. A writer the app constructs can still
never reach Dan. Each invoice write is built in the app as a closure and passed
down by name, OvationApp to RootView to ShellView to the screen or the Edit menu,
and nil is a legitimate value at every layer, meaning this launch has no store. So
a layer that forgets one draws exactly the screen of a launch that cannot write,
and a lost menu action leaves an entry present, enabled and doing nothing. The
hops from RootView down are driven for real by
OvationHostedTests/WritersReachTheScreenTests.swift. The hop above it cannot be,
because an App's scene cannot be built in a test, so it is judged here:

  - every `write...` closure RootView declares is passed by every call that builds
    RootView, and not as a literal nil;
  - that call passes the Edit menu's command object as `edits:`;
  - every action the menu's command object declares, InvoiceEditCommand's closure
    properties, is READ back through that same object in the file that builds
    RootView, which is where the menu is declared.

The list of writers is read off RootView and the list of actions off
InvoiceEditCommand, never typed here, so the next one added is judged without
anybody remembering to add it (L41, L96). The read is matched through the object
passed as `edits:` rather than by the action's bare name, because a writer's own
method shares it (`InvoiceReferralCreditWriter.applyReferralCredit`) and counting
that passed a menu action nothing reads.

Exit codes: 0 every writer used or listed and every closure passed on, 1 an
unwired writer unlisted, a listing with no issue, a stale listing, or a closure or
menu action the app drops, 2 nothing could be judged.
"""
import os
import re
import sys

ROOT = os.environ.get("OVATION_WRITERS_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LISTING = os.path.join(ROOT, "scripts", "unwired-writers.tsv")
SKIP_DIRS = {".git", "DerivedData", "build", "worktrees", "node_modules", "scripts", "docs"}
WRITER = re.compile(r'@ModelActor\s+(?:public\s+|final\s+)*(?:actor|class)\s+([A-Z][A-Za-z0-9_]*)')


def without_comments(text):
    """The code, with // comments and /* */ blocks removed. A comment naming a
    writer, `InvoiceCloser.cancel` in a header, is not a caller, and counting it
    passed exactly the writers this exists to find. String literals are kept: a
    type named inside a string is rare here and the cost of a false pass is small."""
    text = re.sub(r'/\*.*?\*/', ' ', text, flags=re.S)
    return re.sub(r'//[^\n]*', ' ', text)


def app_sources():
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.endswith("Tests")]
        for name in files:
            if name.endswith(".swift"):
                yield os.path.join(base, name)


def declaring(sources, pattern, what):
    """The one source declaring `what`, or an exit code. More than one is refused
    rather than picking one, because two declarations means this cannot tell which
    the app uses (L521)."""
    found = [path for path, text in sources.items() if re.search(pattern, text)]
    if len(found) != 1:
        print("CANNOT MEASURE: expected one declaration of %s, found %d, so the closures it "
              "passes down were not judged." % (what, len(found)))
        return 2
    return found[0]


def call_arguments(text, name):
    """The argument text of every call `name(...)` in `text`, by counting brackets.
    Comments are already gone, and a bracket inside a string literal is rare here."""
    calls = []
    for match in re.finditer(r'\b' + re.escape(name) + r'\s*\(', text):
        depth, start = 1, match.end()
        for index in range(start, len(text)):
            if text[index] in "([{":
                depth += 1
            elif text[index] in ")]}":
                depth -= 1
                if depth == 0:
                    calls.append(text[start:index])
                    break
    return calls


def judge_passed_down(sources):
    """ovation#485. The problems with the closures the app passes RootView and the
    menu actions it reads back, or an exit code where it could not judge."""
    root = declaring(sources, r'\bstruct\s+RootView\b', "RootView")
    if isinstance(root, int):
        return root
    command = declaring(sources, r'\bclass\s+InvoiceEditCommand\b', "InvoiceEditCommand")
    if isinstance(command, int):
        return command

    writers = sorted(set(re.findall(r'\bvar\s+(write[A-Z][A-Za-z0-9_]*)\s*:', sources[root])))
    if not writers:
        print("CANNOT MEASURE: RootView declares no write closure, so none was judged.")
        return 2
    actions = sorted(set(re.findall(r'\bvar\s+([a-z][A-Za-z0-9_]*)\s*:\s*\(\(', sources[command])))
    if not actions:
        print("CANNOT MEASURE: InvoiceEditCommand declares no action, so none was judged.")
        return 2

    problems = []
    builders = [(path, call) for path, text in sources.items() if path != root
                for call in call_arguments(text, "RootView")]
    if not builders:
        return ["Nothing in the app builds RootView, so no writer can reach the screen."]
    for path, call in builders:
        where = os.path.relpath(path, ROOT)
        for name in writers:
            given = re.search(r'\b' + name + r'\s*:\s*(\S+)', call)
            if not given or re.match(r'nil\b', given.group(1)):
                problems.append("%s builds RootView without passing %s, so the control it "
                                "writes for is never drawn (ovation#485)." % (where, name))
        edits = re.search(r'\bedits\s*:\s*([A-Za-z_][A-Za-z0-9_]*)', call)
        if not edits or edits.group(1) == "nil":
            problems.append("%s builds RootView without passing the Edit menu's command as "
                            "edits:, so the menu cannot act on the invoice on screen." % where)
            continue
        for action in actions:
            read = re.compile(r'\b' + re.escape(edits.group(1)) + r'\??\.' + action
                              + r'\b(?!\s*=[^=])')
            if not read.search(sources[path]):
                problems.append("%s never reads %s.%s, so that Edit menu entry does nothing "
                                "when pressed (ovation#485)." % (where, edits.group(1), action))
    return problems


def main():
    sources = {}
    for path in app_sources():
        try:
            with open(path, encoding="utf-8") as handle:
                sources[path] = without_comments(handle.read())
        except (OSError, UnicodeDecodeError) as why:
            print("CANNOT MEASURE: %s could not be read: %s" % (path, why))
            return 2
    writers = {}
    for path, text in sources.items():
        for match in WRITER.finditer(text):
            writers[match.group(1)] = path
    if not writers:
        print("CANNOT MEASURE: no @ModelActor writer was found under %s, so nothing was judged." % ROOT)
        return 2

    listed = {}
    problems = []
    if os.path.exists(LISTING):
        with open(LISTING, encoding="utf-8") as handle:
            for number, line in enumerate(handle, 1):
                line = line.rstrip("\n")
                if not line.strip() or line.startswith("#"):
                    continue
                cells = line.split("\t")
                name = cells[0].strip()
                issue = cells[1].strip() if len(cells) > 1 else ""
                reason = cells[2].strip() if len(cells) > 2 else ""
                if not re.match(r'^ovation#[0-9]+$', issue) or not reason:
                    problems.append("scripts/unwired-writers.tsv line %d lists %s with no issue that wires it, or no reason."
                                    % (number, name or "a writer"))
                    continue
                listed[name] = (issue, reason)

    unwired = []
    for name, own in sorted(writers.items()):
        used = re.compile(r'\b' + re.escape(name) + r'\s*[(.]')
        if any(used.search(text) for path, text in sources.items() if path != own):
            if name in listed:
                problems.append("%s is used by the app now, so remove it from scripts/unwired-writers.tsv." % name)
            continue
        unwired.append(name)

    for name in unwired:
        if name in listed:
            issue, reason = listed[name]
            print("  UNWIRED, LISTED  %s: %s (%s)" % (name, issue, reason))
        else:
            problems.append("%s is a writer nothing in the app uses. Wire it, or list it in "
                            "scripts/unwired-writers.tsv with the issue that will." % name)

    passed_down = judge_passed_down(sources)
    if isinstance(passed_down, int):
        return passed_down
    problems.extend(passed_down)

    if problems:
        for problem in problems:
            print("  REFUSED  " + problem)
        print("REFUSED: %d problem(s) with the app's writers." % len(problems))
        return 1
    print("OK: %d writer(s) judged; every one is used by the app or listed with its issue." % len(writers))
    print("OK: every closure RootView is given is passed by the app, and every Edit menu action is read.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
