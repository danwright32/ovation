#!/bin/bash
# The ported artifact check must report a port made from a commit that is not on
# its sibling's main, must say CANNOT MEASURE when the sibling repository is not
# on this machine, and must never report either of those as a pass.
#
# Ovation ports at least eleven files one line at a time from Downbeat and
# Overture (implementation plan 0.4.6). A clone copies the pattern AS FIRST
# WRITTEN, including every value already corrected in the original, and the
# clone's own note that it follows a proven pattern is what makes it read as safe
# (L501). This plan already caught one instance of exactly that in itself: an
# earlier draft ported Downbeat's identity guard as it stood before L217
# corrected it.
#
# Every outcome the check's contract enumerates is PRODUCED here, not merely
# described (L151), and each assertion names the specific outcome rather than
# accepting any failure (L140).
#
# The two that matter most and are easiest to get wrong:
#
#   CANNOT MEASURE must never be a pass. A checker that reports green because it
#   could not find the repository it was meant to check is indistinguishable from
#   one that checked everything (L98), and the green is then read as confirmation.
#
#   FINDING NOTHING must be its own outcome. Ovation has zero ported files today,
#   so a check that exits 0 on an empty tree would report success for months and
#   be trusted by the time it matters (L98, L182).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
check() {
    if [ "$2" = "$3" ]; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        echo "FAIL: $1"
        echo "      expected '$3', got '$2'"
    fi
}

TARGET="scripts/check-ported-artifacts.sh"
if [ ! -x "$TARGET" ]; then
    echo "FAIL: $TARGET is missing or not executable, so nothing was checked"
    exit 1
fi

# Everything below runs against throwaway repositories in a temp directory. The
# check only ever reads, so the risk is not that it writes somewhere real but
# that it READS a real sibling and reports about it. Section 6 proves the seam is
# honoured rather than assuming it (L322).
WORK="$(mktemp -d)"
# REFUSE rather than delete a path built from an empty variable. `set -u` catches
# an UNSET variable, not an empty one, so a failed mktemp would leave WORK empty
# and new_tree below would run `rm -rf "/tree1"` against a path at the filesystem
# root. That path almost certainly does not exist, and "it happens not to exist"
# is exactly the reasoning L5 exists to stop. Every rm here is scoped to a
# directory this file created seconds earlier, and this is what keeps that true.
if [ -z "${WORK:-}" ] || [ ! -d "$WORK" ]; then
    echo "FAIL: could not create a temp directory, so nothing was checked"
    echo "      refusing to run: every cleanup below is scoped to it"
    exit 1
fi
trap 'rm -rf "$WORK"' EXIT INT TERM

# A stand-in sibling: a real git repo with a main branch and a second commit on a
# branch that was never merged.
SIB="$WORK/roots/downbeat"
mkdir -p "$SIB"
(
    cd "$SIB" || exit 1
    git init -q -b main
    git config user.email t@t; git config user.name t
    git remote add origin https://github.com/danwright32/downbeat.git
    echo one > f.txt; git add f.txt; git commit -qm one
    git checkout -qb unmerged
    echo two > f.txt; git add f.txt; git commit -qm two
    git checkout -qm main 2>/dev/null || git checkout -q main
) >/dev/null 2>&1
ON_MAIN="$(cd "$SIB" && git rev-parse main)"
NOT_ON_MAIN="$(cd "$SIB" && git rev-parse unmerged)"

# The tree of "Ovation files" the check scans. A fresh one per case, so no case
# can pass because of a file another case left behind.
new_tree() { local d="$WORK/tree$1"; [ -n "$WORK" ] || exit 1; rm -rf "$d"; mkdir -p "$d"; echo "$d"; }
port_header() { printf '# Ported-From: %s %s @ %s\n' "$1" "$2" "$3"; }

run_check() {
    OVATION_SIBLING_SEARCH_ROOTS="$WORK/roots" \
    OVATION_PORT_SCAN_ROOT="$1" \
        "./$TARGET" 2>&1
}

# 1. A port whose recorded commit IS on the sibling's main. The only case that
#    may exit 0, and it has to be produced or every refusal below is satisfied by
#    a check that refuses everything.
T1="$(new_tree 1)"
port_header "danwright32/downbeat" "scripts/install-git-hooks.sh" "$ON_MAIN" > "$T1/ported.sh"
OUT1="$(run_check "$T1")"; ST1=$?
check "a port from a commit on the sibling's main passes" "$ST1" "0"
check "and it says how many artifacts it actually examined" \
    "$(printf '%s' "$OUT1" | grep -c "1 ported artifact")" "1"

# 2. A port whose recorded commit is on a branch that was never merged. This is
#    the defect the check exists to find.
T2="$(new_tree 2)"
port_header "danwright32/downbeat" "scripts/install-git-hooks.sh" "$NOT_ON_MAIN" > "$T2/ported.sh"
OUT2="$(run_check "$T2")"; ST2=$?
check "a port from an unmerged commit is REPORTED" "$ST2" "1"
check "and it is named as not being on main" \
    "$(printf '%s' "$OUT2" | grep -c "NOT ON MAIN")" "1"
check "and it names the file it found the header in" \
    "$(printf '%s' "$OUT2" | grep -c "ported.sh")" "1"

# 3. A sibling repository that is not on this machine. CANNOT MEASURE, never a
#    pass, and distinct from case 2 so a missing checkout can never be read as a
#    clean port (L11).
T3="$(new_tree 3)"
port_header "danwright32/nosuchrepo" "some/file.sh" "$ON_MAIN" > "$T3/ported.sh"
OUT3="$(run_check "$T3")"; ST3=$?
check "an absent sibling repository does not pass" "$([ "$ST3" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and it says CANNOT MEASURE" \
    "$(printf '%s' "$OUT3" | grep -c "CANNOT MEASURE")" "1"
check "and it does NOT report it as not being on main" \
    "$(printf '%s' "$OUT3" | grep -c "NOT ON MAIN")" "0"
check "and its exit code is distinct from the not-on-main one" \
    "$([ "$ST3" != "$ST2" ] && echo distinct || echo same)" "distinct"

# 4. The sibling is present but the recorded commit is not in it. A different
#    cause again: the repo was found, the commit was not.
T4="$(new_tree 4)"
port_header "danwright32/downbeat" "scripts/install-git-hooks.sh" "0000000000000000000000000000000000000000" > "$T4/ported.sh"
OUT4="$(run_check "$T4")"; ST4=$?
check "an unknown commit in a present sibling does not pass" \
    "$([ "$ST4" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and it says the commit is unknown rather than not on main" \
    "$(printf '%s' "$OUT4" | grep -c "COMMIT NOT FOUND")" "1"

# 5. No ported artifacts at all. Ovation's real state today, and the one a naive
#    check reports as success for months (L98).
T5="$(new_tree 5)"
echo "a file with no port header" > "$T5/plain.sh"
OUT5="$(run_check "$T5")"; ST5=$?
check "finding no ported artifacts is NOT a pass" \
    "$([ "$ST5" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and it says so in its own words, naming the emptiness" \
    "$(printf '%s' "$OUT5" | grep -c "NO PORTED ARTIFACTS")" "1"
check "and it never claims anything was verified" \
    "$(printf '%s' "$OUT5" | grep -ci "all ported artifacts verified")" "0"

# 6. The search-root seam is honoured. `danwright32/overture` is genuinely on
#    this machine, so if the check ignored the seam and searched the real estate
#    it would resolve it and answer about a real repository. It must not.
T6="$(new_tree 6)"
port_header "danwright32/overture" "mac/project.yml" "$ON_MAIN" > "$T6/ported.sh"
OUT6="$(run_check "$T6")"; ST6=$?
check "a repo outside the search roots is not resolved from the real estate" \
    "$(printf '%s' "$OUT6" | grep -c "CANNOT MEASURE")" "1"
check "and the seam being honoured means it did not pass" \
    "$([ "$ST6" -ne 0 ] && echo nonzero || echo zero)" "nonzero"

# 7. A header that is present but malformed. An operation that finds its target
#    by matching text reports success when it matches nothing (L100), so a header
#    the check cannot parse must be refused by name rather than skipped into the
#    "no artifacts" or the "all clear" bucket.
T7="$(new_tree 7)"
echo "# Ported-From: this is not three fields" > "$T7/ported.sh"
OUT7="$(run_check "$T7")"; ST7=$?
check "a malformed port header does not pass" \
    "$([ "$ST7" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and it is refused as unparseable rather than ignored" \
    "$(printf '%s' "$OUT7" | grep -c "UNREADABLE HEADER")" "1"
check "and it is not reported as no artifacts having been found" \
    "$(printf '%s' "$OUT7" | grep -c "NO PORTED ARTIFACTS")" "0"

# 8. Comment styles. Ovation ports shell, yaml and Swift, so the marker must be
#    found behind '#' and '//' alike. A check that only understood one would
#    silently examine none of the Swift ports and report the rest as everything.
T8="$(new_tree 8)"
printf '// Ported-From: %s %s @ %s\n' "danwright32/downbeat" "Persistence/StoreSchemaGuard.swift" "$ON_MAIN" > "$T8/Guard.swift"
OUT8="$(run_check "$T8")"; ST8=$?
check "a Swift style comment header is found" "$ST8" "0"
check "and it counted the Swift file as an artifact" \
    "$(printf '%s' "$OUT8" | grep -c "1 ported artifact")" "1"

# 9. A file that TALKS ABOUT port headers is not a ported artifact. The check has
#    to name its own marker in order to search for it, so it matches itself, its
#    own test, and every document describing the convention (L245). Found by
#    running it against the real repository, which no fixture case could reach,
#    because every case above scans an isolated temp tree.
#
#    The rule is the reason, not a list of filenames (L362): a real port header
#    is a HEADER, sitting at the start of its comment. Prose about one is
#    indented inside a block, so it is not a header and must not be counted.
T9="$(new_tree 9)"
{
    echo "# Some documentation about the convention:"
    echo "#"
    echo "#     Ported-From: <owner>/<repo> <path in that repo> @ <commit>"
    echo "#"
    echo "# and some more prose after it."
} > "$T9/doc.sh"
OUT9="$(run_check "$T9")"; ST9=$?
check "indented prose describing a port header is not counted as an artifact" \
    "$(printf '%s' "$OUT9" | grep -c "UNREADABLE HEADER")" "0"
check "and a tree holding only such prose reports no artifacts, not a failure" \
    "$ST9" "3"

# 10. The real repository, scanned with the real default roots. This is the case
#     the seam deliberately hides from every case above, and it is where case 9's
#     defect actually lived.
#
#     INVERTED 2026-09-05, in the same change that consumed it (L373). It used to
#     assert that Ovation had NO ported artifacts, which was true for about an
#     hour: project.yml then landed carrying a real header, ported from
#     Overture's mac/project.yml. A test whose premise is that a change has not
#     yet been made is consumed by that change shipping, and left behind it goes
#     permanently red for a reason that looks exactly like a real defect.
#
#     What it asserts now is the stronger thing anyway: the real ports resolve
#     against the real siblings, through the real default search roots, which no
#     other case can reach.
OUT10="$(OVATION_PORT_SCAN_ROOT="$PWD" "./$TARGET" 2>&1)"; ST10=$?
check "scanning Ovation itself verifies its real ports against the real siblings" \
    "$ST10" "0"
check "and project.yml is one of them, reported OK" \
    "$(printf '%s' "$OUT10" | grep -c '^OK: project.yml')" "1"
check "and it still does not match its own marker" \
    "$(printf '%s' "$OUT10" | grep -c "UNREADABLE HEADER")" "0"
check "and it does not report the repository as empty now that a port exists" \
    "$(printf '%s' "$OUT10" | grep -c "NO PORTED ARTIFACTS")" "0"

echo "ported artifact check tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
