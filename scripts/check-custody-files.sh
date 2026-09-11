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
# A SECTION MAY DECLARE ITSELF NOT A CUSTODY FILE, by carrying a
# `| Not a custody file | <reason> |` row (ovation#208). The note records the
# paths Ovation depends on outside the repository, and one of them is Downbeat's
# LIVE export, which Downbeat rewrites on every launch: it can never carry a hash,
# because a hash would fail on every correct read. Reported as unverifiable it
# would put a line in every run that is right by design, and a category of finding
# that is always present is the one people stop reading (L36, L233).
#
# THE ROW IS THE REASON, NOT THE NAME. Anything excluded here is excluded because
# something else rewrites it, so the next such path is covered by the same row
# rather than by a second exemption written for it (L362). The reason is REQUIRED:
# an empty one falls through and is verified like anything else, so the row cannot
# become a way to silence a file by accident.
# THE FIELD SEPARATOR IS A UNIT SEPARATOR RATHER THAN A TAB, and that is a fix
# rather than a preference. A tab is IFS WHITESPACE even when IFS is set to
# exactly a tab, so `read` collapses a run of them: a record whose MIDDLE field is
# empty then shifts every field after it one to the left, silently. It bit the
# moment a fourth field arrived, because the live export entry carries no SHA-256,
# so its record was name, path, EMPTY, reason, and the reason was read as the hash.
# The entry then looked verifiable and was reported absent.
SEP=$'\x1f'

ENTRIES="$(awk -v SEP="$SEP" '
    /^## / {
        if (name != "" && path != "") print name SEP path SEP hash SEP live
        name = substr($0, 4); path = ""; hash = ""; live = ""; next
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
    /^\| *Not a custody file *\|/ {
        line = $0
        sub(/^\| *Not a custody file *\| */, "", line)
        sub(/ *\|[ \t]*$/, "", line)
        gsub(/^[ \t]+|[ \t]+$/, "", line)
        if (line != "") live = line
        next
    }
    END { if (name != "" && path != "") print name SEP path SEP hash SEP live }
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
EXCLUDED=0
EXCLUDED_NAMES=""
BLOCKING=0
UNVERIFIABLE=0

while IFS="$SEP" read -r name path hash live; do
    [ -n "$name" ] || continue

    # Declared not a custody file, with a reason. Counted and named at the end
    # rather than dropped in silence, because an exclusion nothing reports is one
    # nobody can audit (L98, L233). It is NOT part of TOTAL: these are not files
    # this verifier is claiming to have checked.
    if [ -n "${live:-}" ]; then
        EXCLUDED=$((EXCLUDED+1))
        EXCLUDED_NAMES="${EXCLUDED_NAMES}${EXCLUDED_NAMES:+, }${name}"
        continue
    fi

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
if [ "$EXCLUDED" -gt 0 ]; then
    echo "Skipped ${EXCLUDED} section(s) declared not custody files: ${EXCLUDED_NAMES}"
fi

[ "$BLOCKING" -gt 0 ] && exit 1
[ "$UNVERIFIABLE" -gt 0 ] && exit 2
exit 0
