#!/bin/bash
# The Python programs behind a .sh name must behave the same however they are
# started, including by bash.
#
# ovation#257. Twenty six scripts under scripts/ are Python behind a `.sh` name.
# Started the obvious way, `bash scripts/check-identity-leaks.sh`, bash read the
# Python, printed a page of syntax errors and exited 2, and 2 is exactly what
# these scanners use for CANNOT SCAN, nothing was checked. A crash and an honest
# "nothing scanned" arrived as the same number, which is two causes behind one
# outcome (L11), and it misled a session on 2026-09-12 until the output was read
# by eye. The push gate was never affected, because it runs them through their
# shebang; the exposure is anybody running a check by hand.
#
# THE REMEDY IS THAT BASH RE-RUNS THEM UNDER PYTHON, rather than refusing, and
# rather than renaming them. Line two of each is
#
#     ''''exec python3 "$0" "$@" #'''
#
# which bash reads as `exec python3 <this file> <its arguments>` (four quotes are
# two empty strings joined to `exec`) and Python reads as a string literal, so
# nothing else in the file changes. Because the literal is the module's first
# statement it would take the docstring's place, and several scripts print lines
# of `__doc__`, so the docstring is assigned to `__doc__` explicitly.
#
# What is asserted is both halves: every such script carries the line and still
# parses with its docstring as `__doc__` (read from the tree, so a script added
# tomorrow is covered without anybody listing it, L41), and a real check started
# under bash returns the SAME exit code for every outcome it has, a genuinely
# failing one included, because a stand in that only reproduces success proves
# nothing about the codes a caller acts on (L404).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "Python scripts started by bash" 11

TARGET="scripts/check-forbidden-constructs.sh"
require_target "$TARGET"
harness_temp_dir WORK

# One pass over a directory tree. It prints `FOUND <n>` for the Python scripts
# named .sh it saw, then one line per fault. It takes the directory as an
# argument so it can be pointed at a fixture and SEEN to find each fault (L1).
python_script_faults() {
    python3 -B - "$1" <<'PY'
import ast, os, sys
root = sys.argv[1]
reexec = "''''exec python3 \"$0\" \"$@\" #'''"
found, faults = 0, []
for directory, _, filenames in os.walk(root):
    for filename in sorted(filenames):
        if not filename.endswith(".sh"):
            continue
        path = os.path.join(directory, filename)
        name = os.path.relpath(path, root)
        text = open(path, encoding="utf-8", errors="replace").read()
        lines = text.splitlines()
        if not lines or not lines[0].startswith("#!") or "python" not in lines[0]:
            continue
        found += 1
        if len(lines) < 2 or lines[1] != reexec:
            faults.append(name + ": no re-exec line")
            continue
        try:
            tree = ast.parse(text)
        except SyntaxError:
            faults.append(name + ": does not parse")
            continue
        if not any(isinstance(node, ast.Assign)
                   and any(isinstance(t, ast.Name) and t.id == "__doc__" for t in node.targets)
                   for node in tree.body[:3]):
            faults.append(name + ": docstring is not __doc__")
print("FOUND %d" % found)
for fault in sorted(faults):
    print(fault)
PY
}

# ---------------------------------------------------------------------------
# The real tree.
# ---------------------------------------------------------------------------
REAL="$(python_script_faults scripts)"
REAL_FOUND="$(printf '%s\n' "$REAL" | sed -n 's/^FOUND \([0-9][0-9]*\)$/\1/p')"
check "the scan finds Python scripts named .sh, so it measures something" \
    "$([ "${REAL_FOUND:-0}" -gt 0 ] && echo yes || echo "no, found '${REAL_FOUND}'")" "yes"
check "every one carries the line that re-runs it under python3, parses, and keeps its docstring" \
    "$(printf '%s\n' "$REAL" | grep -v '^FOUND ')" ""

# ---------------------------------------------------------------------------
# The scan, seen to find each fault it claims to (L1, L151).
# ---------------------------------------------------------------------------
FIXTURE="$WORK/scripts"
mkdir -p "$FIXTURE"
printf '#!/usr/bin/env python3\n"""A docstring."""\nprint("x")\n' > "$FIXTURE/bare.sh"
printf '#!/usr/bin/env python3\n%s\n"""A docstring."""\nprint("x")\n' \
    "''''exec python3 \"\$0\" \"\$@\" #'''" > "$FIXTURE/nodoc.sh"
printf '#!/bin/bash\necho "a shell script is not judged"\n' > "$FIXTURE/shell.sh"
FIXTURE_OUT="$(python_script_faults "$FIXTURE")"
check "a Python script with no re-exec line is found" \
    "$(printf '%s\n' "$FIXTURE_OUT" | grep -c '^bare.sh: no re-exec line$')" "1"
check "one whose docstring is no longer __doc__ is found" \
    "$(printf '%s\n' "$FIXTURE_OUT" | grep -c '^nodoc.sh: docstring is not __doc__$')" "1"

# ---------------------------------------------------------------------------
# A real check, started under bash, for every outcome it has. Fixture roots
# only, through the check's own seams, so nothing here reads Ovation's sources
# or anybody's data (L2).
# ---------------------------------------------------------------------------
CLEAN="$WORK/clean"; BAD="$WORK/bad"; EMPTY="$WORK/empty"
mkdir -p "$CLEAN" "$BAD" "$EMPTY"
printf 'struct Money {\n    let cents: Int64\n}\n' > "$CLEAN/Money.swift"
printf 'let amount: Double = 1\n' > "$BAD/Charge.swift"

under_bash() {
    OVATION_CONSTRUCT_SCAN_ROOT="$1" OVATION_CONSTRUCT_ALLOWLIST="${2-}" bash "$TARGET" 2>&1
}
status_under() {
    OVATION_CONSTRUCT_SCAN_ROOT="$2" OVATION_CONSTRUCT_ALLOWLIST="${3-}" "$1" "$TARGET" >/dev/null 2>&1
    printf '%s' "$?"
}

check "under bash, a clean tree exits 0" "$(status_under bash "$CLEAN")" "0"
check "under bash, a forbidden construct exits 1" "$(status_under bash "$BAD")" "1"
check "under bash, nothing to scan exits 2, the scanner's own CANNOT SCAN" \
    "$(status_under bash "$EMPTY")" "2"
check "under bash, a bad allowlist exits 3" \
    "$(status_under bash "$CLEAN" "Money.swift")" "3"
check "and bash prints exactly what the shebang does" \
    "$(under_bash "$BAD")" \
    "$(OVATION_CONSTRUCT_SCAN_ROOT="$BAD" OVATION_CONSTRUCT_ALLOWLIST="" "./$TARGET" 2>&1)"
check "under sh, a forbidden construct exits 1 too" "$(status_under sh "$BAD")" "1"

# WITH NO PYTHON AT ALL, the one outcome that must never read as CANNOT SCAN. The
# exec fails, the shell says python3 was not found, and it exits 127.
check "under bash with no python3 on the path, it exits 127, never 2" \
    "$(PATH="$WORK/no-such-dir" /bin/bash "$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "127"

harness_end
