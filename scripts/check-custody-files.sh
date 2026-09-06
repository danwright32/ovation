#!/bin/bash
# Verify every file docs/CUSTODY.md records, with a named outcome per way it can
# be wrong.
#
# ovation#17. The note has always said to do this: "Verify the SHA-256 above at
# read time, not only when it was written. Absent, unreadable, or a hash mismatch
# is its own named outcome that BLOCKS the backfill." Nothing implemented it. It
# was a `shasum -a 256 -c` typed by hand, and a constraint enforced only by
# somebody remembering is enforced by nothing (L407).
#
# THE LIST COMES FROM THE NOTE. docs/CUSTODY.md is already the single record of
# where these files live and what they hash to, so this derives its work from it
# rather than carrying a second copy that would drift (L41).
#
# WHY IT MATTERS MORE THAN AN ORDINARY CHECKSUM. These files are the only record
# that nineteen shoots existed and how long they ran. Phase 6's one time backfill
# and its reconciliation both read them, and a reconciliation that quietly
# proceeds with a smaller population finds zero differences, which is exactly
# what a healthy run reports (L98).
#
# FOUR OUTCOMES, KEPT APART, because they need different actions:
#
#   absent      the file the note records is not on disk: moved, or never written
#   unreadable  it is there but cannot be read: permissions, or a bad disk
#   mismatch    it reads, and its contents are NOT what was recorded
#   no hash     the note names a file but records no hash for it
#
# Collapsing any into another would let a file nobody is checking read like a
# file that passed (L11, L140).
#
#   0  every recorded file verified
#   1  at least one absent, unreadable or mismatched, which BLOCKS
#   2  nothing could be verified: no note, no entries, or an entry with no hash
#
# PRIVACY FLOOR. It hashes files and never opens one for anything else. It prints
# paths, hashes, names and outcomes, never a byte of content
# (docs/PRIVACY-FLOOR.md, L222).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTE="${OVATION_CUSTODY_NOTE:-${REPO_ROOT}/docs/CUSTODY.md}"

if [ ! -f "$NOTE" ]; then
    echo "CANNOT MEASURE: the custody note is not at ${NOTE}"
    echo "    It is the record of which files exist and what they hash to, so"
    echo "    without it there is no list to verify. This is not a pass."
    exit 2
fi

# Parse the note into "name<TAB>path<TAB>hash" lines.
#
# An entry is a `## <name>` heading FOLLOWED BY a table carrying a Path row, and
# a heading with no such table is not an entry. The real note ends with a section
# called "What this folder is to Ovation", and a parser that treated every
# heading as a file would invent one and then report it absent for ever.
ENTRIES="$(awk '
    /^## / {
        if (name != "" && path != "") print name "\t" path "\t" hash
        name = substr($0, 4); path = ""; hash = ""; next
    }
    /^\| *Path *\|/ {
        line = $0
        if (match(line, /`[^`]*`/)) path = substr(line, RSTART + 1, RLENGTH - 2)
        next
    }
    /^\| *SHA-256 *\|/ {
        line = $0
        if (match(line, /`[^`]*`/)) hash = substr(line, RSTART + 1, RLENGTH - 2)
        next
    }
    END { if (name != "" && path != "") print name "\t" path "\t" hash }
' "$NOTE")"

if [ -z "$ENTRIES" ]; then
    echo "CANNOT MEASURE: ${NOTE} records no files."
    echo "    A verifier with nothing to verify examines nothing and would"
    echo "    otherwise exit green, which is indistinguishable from having"
    echo "    checked everything. This is not a pass."
    exit 2
fi

TOTAL=0
OK=0
BLOCKING=0
UNVERIFIABLE=0

while IFS=$'\t' read -r name path hash; do
    [ -n "$name" ] || continue
    TOTAL=$((TOTAL+1))
    # The note writes paths with a tilde, deliberately, so they survive being
    # read on either Mac. Expand it here rather than storing a real home path.
    case "$path" in
        "~/"*) full="${HOME}/${path#\~/}" ;;
        *) full="$path" ;;
    esac

    if [ -z "$hash" ]; then
        echo "  NO RECORDED HASH  ${name}"
        echo "                    the note names it but records no SHA-256, so"
        echo "                    nothing can say whether it is intact"
        UNVERIFIABLE=$((UNVERIFIABLE+1))
        continue
    fi

    if [ ! -e "$full" ]; then
        echo "  ABSENT            ${name}"
        echo "                    recorded at ${path}"
        BLOCKING=$((BLOCKING+1))
        continue
    fi

    if [ ! -r "$full" ]; then
        echo "  UNREADABLE        ${name}"
        echo "                    it is there, and could not be opened"
        BLOCKING=$((BLOCKING+1))
        continue
    fi

    actual="$(shasum -a 256 "$full" 2>/dev/null | cut -d' ' -f1)"
    if [ -z "$actual" ]; then
        echo "  UNREADABLE        ${name}"
        echo "                    it is there, and could not be hashed"
        BLOCKING=$((BLOCKING+1))
        continue
    fi

    if [ "$actual" != "$hash" ]; then
        # Both hashes are printed. They are not content, and the difference is
        # the whole finding: a hash that differs means the recorded contents are
        # wrong, which is the one outcome that cannot be fixed by looking again.
        echo "  MISMATCH          ${name}"
        echo "                    recorded ${hash}"
        echo "                    on disk  ${actual}"
        BLOCKING=$((BLOCKING+1))
        continue
    fi

    echo "  OK                ${name}"
    OK=$((OK+1))
done <<< "$ENTRIES"

echo
echo "Checked ${TOTAL} recorded file(s): ${OK} verified, ${BLOCKING} blocking, ${UNVERIFIABLE} unverifiable."

[ "$BLOCKING" -gt 0 ] && exit 1
[ "$UNVERIFIABLE" -gt 0 ] && exit 2
exit 0
