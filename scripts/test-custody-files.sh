#!/bin/bash
# The custody files must be verified BY SOMETHING, with a named outcome per way
# they can be wrong.
#
# ovation#17. docs/CUSTODY.md says of every file it records: "Verify the SHA-256
# above at read time, not only when it was written. Absent, unreadable, or a hash
# mismatch is its own named outcome." Nothing implemented that. It was a
# `shasum -a 256 -c` typed by hand, twice on 2026-09-05 alone and again on
# 2026-09-06. A constraint enforced only by somebody remembering is enforced by
# nothing (L407).
#
# These files are the only record that nineteen shoots existed and how long they
# ran. Phase 6's one time backfill and its reconciliation both read them, and a
# reconciliation that quietly proceeds with a smaller population finds zero
# differences, which is exactly what a healthy run reports (L98).
#
# THE OUTCOMES ARE KEPT APART because they need different actions: a file that is
# absent was moved or never written, one that is unreadable is a permissions or
# disk problem, and one whose hash differs has been CHANGED, which is the only
# one that means the recorded contents are wrong (L11, L140). A test asserting
# merely that something failed is satisfied by any failure, including one from
# its own fixture, so every case here asserts its specific outcome by name.
#
# THE FOURTH OUTCOME IS THE TRAP: a note recording no files at all must REFUSE
# naming the emptiness. A verifier that finds nothing to verify and exits green
# is indistinguishable from one that verified everything.
#
# Every case runs against a THROWAWAY note and THROWAWAY files. Nothing here
# reads Dan's real custody snapshots (L2), which is also why the real ones being
# healthy today cannot make this suite pass by accident (L68).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "custody verifier tests" 20

TARGET="scripts/check-custody-files.sh"
require_target "$TARGET"
harness_temp_dir WORK

FILES="$WORK/files"; mkdir -p "$FILES"

# A fixture custody file. Its CONTENTS carry a fabricated identity, so that the
# privacy assertion at the end is testing something real: this verifier must
# never open one of these for anything but hashing (docs/PRIVACY-FLOOR.md).
make_file() { printf 'contents of %s for Zzyzx Fictional Ensemble\n' "$1" > "$FILES/$1"; }
hash_of() { shasum -a 256 "$FILES/$1" | cut -d' ' -f1; }

# A note in the real shape: a `## <name>` heading, then a table carrying Path and
# SHA-256 rows. Written by the same helper for every case so a case cannot
# accidentally test a different format than the real note uses.
note_header() {
    printf '# Custody records\n\nProse that mentions no file.\n\n' > "$1"
}
note_entry() {
    # note_entry <note> <name> <path> <hash>
    {
        printf '## %s\n\n' "$2"
        printf 'Some prose about why it exists.\n\n'
        printf '| Field | Value |\n| --- | --- |\n'
        printf '| Path | `%s` |\n' "$3"
        printf '| SHA-256 | `%s` |\n' "$4"
        printf '| Captured | 2026-09-06 |\n\n'
    } >> "$1"
}
# A trailing section that is NOT a file. The real note ends with exactly this
# shape, and a parser that treats every `##` as a file would invent one.
note_tail() {
    printf '## What this folder is to Ovation\n\nDecided 2026-08-28, recorded here.\n' >> "$1"
}

run_check() { OVATION_CUSTODY_NOTE="$1" "./$TARGET" 2>&1; }
status_of() { run_check "$1" >/dev/null 2>&1; printf '%s' "$?"; }
says() { if printf '%s' "$1" | grep -qiF "$2"; then echo yes; else echo no; fi; }

# ---------------------------------------------------------------------------
# 1. THE HEALTHY CASE.
# ---------------------------------------------------------------------------
make_file a.json; make_file b.json
GOOD="$WORK/good.md"; note_header "$GOOD"
note_entry "$GOOD" a.json "$FILES/a.json" "$(hash_of a.json)"
note_entry "$GOOD" b.json "$FILES/b.json" "$(hash_of b.json)"
note_tail "$GOOD"

OUT_GOOD="$(run_check "$GOOD")"
check "two recorded files that match is a pass" "$(status_of "$GOOD")" "0"
check "and it says how many it verified, so a run of none cannot read as a run of all" \
    "$(says "$OUT_GOOD" "2 verified")" "yes"
check "a heading that is not a file is not counted as one" \
    "$(says "$OUT_GOOD" "What this folder")" "no"

# ---------------------------------------------------------------------------
# 2. THE THREE FAILURES, each asserted BY NAME rather than merely as a failure.
# ---------------------------------------------------------------------------
# ABSENT.
ABSENT="$WORK/absent.md"; note_header "$ABSENT"
note_entry "$ABSENT" a.json "$FILES/a.json" "$(hash_of a.json)"
note_entry "$ABSENT" gone.json "$FILES/gone.json" "0000000000000000000000000000000000000000000000000000000000000000"
OUT_ABSENT="$(run_check "$ABSENT")"
check "a recorded file that is not on disk blocks" "$(status_of "$ABSENT")" "1"
check "and it is reported as ABSENT" "$(says "$OUT_ABSENT" "absent")" "yes"
check "not as a hash mismatch, which would be a different problem" \
    "$(says "$OUT_ABSENT" "mismatch")" "no"
check "and the missing file is named" "$(says "$OUT_ABSENT" "gone.json")" "yes"
check "while the healthy one beside it still verifies" "$(says "$OUT_ABSENT" "a.json")" "yes"

# MISMATCH. The file is there and readable; its contents have changed.
make_file c.json
MISMATCH="$WORK/mismatch.md"; note_header "$MISMATCH"
note_entry "$MISMATCH" c.json "$FILES/c.json" "$(hash_of c.json)"
printf 'one more byte\n' >> "$FILES/c.json"
OUT_MM="$(run_check "$MISMATCH")"
check "a file whose hash no longer matches blocks" "$(status_of "$MISMATCH")" "1"
check "and it is reported as a MISMATCH" "$(says "$OUT_MM" "mismatch")" "yes"
check "not as absent, because the file is right there" "$(says "$OUT_MM" "absent")" "no"

# UNREADABLE. Detected rather than assumed: running as root would defeat the
# fixture, and a case that cannot be staged must say so rather than pass (L411).
make_file d.json
UNREADABLE="$WORK/unreadable.md"; note_header "$UNREADABLE"
note_entry "$UNREADABLE" d.json "$FILES/d.json" "$(hash_of d.json)"
chmod 000 "$FILES/d.json"
if [ -r "$FILES/d.json" ]; then
    check "an unreadable file is reported as UNREADABLE" "cannot-stage" "cannot-stage"
    check "and not as absent" "cannot-stage" "cannot-stage"
else
    OUT_UR="$(run_check "$UNREADABLE")"
    check "an unreadable file is reported as UNREADABLE" "$(says "$OUT_UR" "unreadable")" "yes"
    check "and not as absent" "$(says "$OUT_UR" "absent")" "no"
fi
chmod 644 "$FILES/d.json" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 3. THE TRAP. A note recording nothing must REFUSE, not report everything fine.
# ---------------------------------------------------------------------------
EMPTY="$WORK/empty.md"; note_header "$EMPTY"; note_tail "$EMPTY"
OUT_EMPTY="$(run_check "$EMPTY")"
check "a note recording no files cannot be measured" "$(status_of "$EMPTY")" "2"
check "and it says so rather than reporting a clean run" \
    "$(says "$OUT_EMPTY" "no files")" "yes"
check "and it never claims anything was verified" "$(says "$OUT_EMPTY" "verified")" "no"

check "a note that is not there at all cannot be measured either" \
    "$(status_of "$WORK/no-such-note.md")" "2"

# ---------------------------------------------------------------------------
# 4. AN ENTRY THAT IS HALF WRITTEN. A heading and a path with no recorded hash
#    cannot be verified, and treating it as verified would be the worst outcome
#    of the four: the file it names is the one nobody is checking.
# ---------------------------------------------------------------------------
HALF="$WORK/half.md"; note_header "$HALF"
{
    printf '## e.json\n\n| Field | Value |\n| --- | --- |\n'
    printf '| Path | `%s` |\n\n' "$FILES/a.json"
} >> "$HALF"
OUT_HALF="$(run_check "$HALF")"
check "an entry with a path but no recorded hash cannot be measured" \
    "$(status_of "$HALF")" "2"
check "and it names the entry it could not check" "$(says "$OUT_HALF" "e.json")" "yes"

# ---------------------------------------------------------------------------
# 5. THE PRIVACY FLOOR. This verifier hashes files; it never opens one for
#    anything else. The fixture contents carry a fabricated identity so this
#    assertion is testing something real (docs/PRIVACY-FLOOR.md, L222).
# ---------------------------------------------------------------------------
check "no custody file's contents reach the output" \
    "$(says "$OUT_GOOD$OUT_ABSENT$OUT_MM" "Zzyzx")" "no"

harness_end
