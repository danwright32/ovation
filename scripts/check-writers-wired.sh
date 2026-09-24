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

Exit codes: 0 every writer used or listed, 1 an unwired writer unlisted, a listing
with no issue, or a stale listing, 2 nothing could be judged.
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

    if problems:
        for problem in problems:
            print("  REFUSED  " + problem)
        print("REFUSED: %d problem(s) with the app's writers." % len(problems))
        return 1
    print("OK: %d writer(s) judged; every one is used by the app or listed with its issue." % len(writers))
    return 0


if __name__ == "__main__":
    sys.exit(main())
