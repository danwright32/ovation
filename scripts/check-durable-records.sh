''''exec python3 "$0" "$@" #'''
__doc__ = """Refuse a durable record written without asking the rule whether a staged run may write it.

    check-durable-records.sh

ovation#368. A run whose subject is injected (a stand in browser, an injected test
command) writes nothing to a durable record unless it declares the staging is what
it measures, and that rule lives in ONE place, scripts/lib/durable-record.sh. Two
records each carried their own copy of it and the copies disagreed: the browser
restart record refused a staged fault, and the lock wait record took any path it
was named, which is how staged faults were counted as real on ovation#353 (L2, L93).
A rule living in whoever remembers it reaches nothing, so this finds every writer
and asks whether it went through the rule (L27, L613).

WHAT COUNTS AS A DURABLE RECORD: a file APPENDED to, because a record is what
accumulates across runs and is read back as a count. That is `>>` and `tee -a` in
shell, and `open(..., "a")` in Python, in any script under scripts/ other than a
suite (test-*.sh), which writes only into its own throwaway directory. A file that
is overwritten whole is state rather than a record of occurrences, and is not
this check's subject.

ROUTED MEANS PER WRITE, not per file. Each append's target must be a variable the
same file assigns from `durable_record_path`. A file level match would pass a
second writer beside a routed one, which is where the next one would be added
(L135).

THE LIST OF THE LEGITIMATELY UNROUTED is scripts/durable-record-exemptions.tsv, a
script path relative to scripts/ and the reason nothing can stage its subject. An
entry with no reason is refused (L233), an entry for a file with no unrouted
writer is refused as stale (L346), and each listed one is still printed with its
reason, so the list is read.

Exit codes: 0 every durable writer routed or listed, 1 an unrouted writer unlisted,
a listing with no reason, or a stale listing, 2 nothing could be judged.
"""
import os
import re
import sys

ROOT = os.environ.get("OVATION_DURABLE_RECORDS_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(ROOT, "scripts")
LISTING = os.path.join(SCRIPTS, "durable-record-exemptions.tsv")
RULE = os.path.join("lib", "durable-record.sh")
SELF = "check-durable-records.sh"

# An append and its target. The target is read as far as the next space, quote
# boundary or shell operator; what is judged is the VARIABLE it names.
SHELL_APPEND = re.compile(r'(?:>>|\btee\s+-a)\s*("?)(\S+?)\1(?=[\s;|&)]|$)')
PY_APPEND = re.compile(r'\bopen\(\s*([^,()]+?)\s*,\s*(?:mode\s*=\s*)?["\']a[bt+]?["\']')
# What an append must not be mistaken for: a heredoc, and a stream.
NOT_A_FILE = re.compile(r'^(?:&\d|/dev/(?:null|stderr|stdout|fd/\d+))$')


def variable_in(target):
    """The variable a write target is built from, or None for a literal path."""
    found = re.match(r'^\$\{?([A-Za-z_][A-Za-z0-9_]*)', target)
    if found:
        return found.group(1)
    found = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)$', target)
    return found.group(1) if found else None


RULE_ASSIGNMENT = (r'="?\$\(\s*durable_record_path\b',
                   r'\s*=\s*(?:[A-Za-z_][A-Za-z0-9_]*\.)?durable_record_path\(')


def routed_names(text):
    """Every variable the file assigns ONLY from the rule, in either language.

    EVERY assignment, not one of them: a variable given the rule's answer on one
    line and a name straight from the environment on another writes wherever the
    second one left it, and that is the shape the lock wait record had (L178)."""
    names = set()
    for pattern in RULE_ASSIGNMENT:
        names |= set(re.findall(r'\b([A-Za-z_][A-Za-z0-9_]*)' + pattern, text))
    routed = set()
    for name in names:
        every = len(re.findall(r'(?<![\w.$])' + re.escape(name) + r'\s*=(?!=)', text))
        from_rule = sum(len(re.findall(r'(?<![\w.$])' + re.escape(name) + pattern, text))
                        for pattern in RULE_ASSIGNMENT)
        if every == from_rule:
            routed.add(name)
    return routed


def writers(path):
    """(line number, target) for every append in the file, comments skipped. A
    comment describing an append is not one, and a header explaining a record is
    exactly where one is described."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().splitlines()
    found = []
    for number, line in enumerate(lines, 1):
        if line.lstrip().startswith("#"):
            continue
        for match in SHELL_APPEND.finditer(line):
            if line[max(0, match.start() - 1):match.start()] == "<":
                continue
            target = match.group(2)
            if not NOT_A_FILE.match(target):
                found.append((number, target))
        for match in PY_APPEND.finditer(line):
            found.append((number, match.group(1).strip()))
    return lines, found


def scripts():
    for base, dirs, files in os.walk(SCRIPTS):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for name in sorted(files):
            if name.startswith("test-") or not name.endswith((".sh", ".py")):
                continue
            path = os.path.join(base, name)
            # The rule is what a writer asks, and this check NAMES every construct
            # it looks for, in its own documentation and patterns, so reading
            # itself it finds four writers that write nothing (L245).
            if os.path.relpath(path, SCRIPTS) in (RULE, SELF):
                continue
            yield path


def main():
    if not os.path.isdir(SCRIPTS):
        print("CANNOT JUDGE: there is no scripts directory at %s, so no writer was looked at." % SCRIPTS)
        return 2
    listed = {}
    problems = []
    if os.path.exists(LISTING):
        with open(LISTING, encoding="utf-8") as handle:
            for number, raw in enumerate(handle, 1):
                if not raw.strip() or raw.startswith("#"):
                    continue
                name, _, reason = raw.rstrip("\n").partition("\t")
                if not reason.strip():
                    problems.append("scripts/durable-record-exemptions.tsv line %d lists %s with no reason."
                                    % (number, name))
                listed[name.strip()] = reason.strip()

    judged = 0
    routed = []
    exempt = []
    unrouted_files = set()
    for path in scripts():
        judged += 1
        relative = os.path.relpath(path, SCRIPTS)
        lines, found = writers(path)
        if not found:
            continue
        names = routed_names("\n".join(line for line in lines if not line.lstrip().startswith("#")))
        for number, target in found:
            if variable_in(target) in names:
                routed.append("%s:%d" % (relative, number))
                continue
            unrouted_files.add(relative)
            if relative in listed:
                exempt.append("%s:%d" % (relative, number))
                continue
            problems.append("UNROUTED: scripts/%s:%d appends to %s without asking %s whether a staged run may "
                            "write it. Assign the path from durable_record_path, or list the file in "
                            "scripts/durable-record-exemptions.tsv with the reason nothing can stage its subject."
                            % (relative, number, target, "scripts/" + RULE))
    for name in sorted(listed):
        if name not in unrouted_files:
            problems.append("%s has no unrouted durable writer now, so remove it from "
                            "scripts/durable-record-exemptions.tsv." % name)
    if judged == 0:
        print("CANNOT JUDGE: no script under %s was found to look at." % SCRIPTS)
        return 2

    for where in routed:
        print("routed through the rule: scripts/%s" % where)
    for where in exempt:
        name = where.rsplit(":", 1)[0]
        print("listed, not routed: scripts/%s (%s)" % (where, listed.get(name, "")))
    print("%d script(s) looked at, %d durable writer(s) routed, %d listed."
          % (judged, len(routed), len(exempt)))
    if problems:
        for problem in problems:
            print(problem)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
