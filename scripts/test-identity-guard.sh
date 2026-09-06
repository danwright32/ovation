#!/bin/bash
# The identity guard must find real names anywhere in the tree, must REFUSE when
# it has nothing to look for, and must not fire on ordinary prose.
#
# ovation#5. The repository is PUBLIC for the whole build, and Ovation's whole
# subject matter is real clients, real venues and real vendors.
#
# THE DESIGN THIS DELIBERATELY DOES NOT COPY. The port source's guard reads its
# needles from a machine local list. On this Mac that list did not exist, so it
# reported `noList`, examined nothing, and a real venue name sat in four test
# files the whole time (L217). Ovation DERIVES its needles from the populations
# that actually exist, and an empty derivation is a REFUSAL, not a clean report.
#
# FIXTURE NAMES CARRY A MARKER NO REAL BUSINESS WOULD USE, and that is not
# fussiness. The first version invented plausible names, and one of them,
# a two word seasonal one, COLLIDED with a real shoot name: the guard flagged this
# very file on its first real run against Dan's export. An invented fixture that
# looks realistic is one draw from the same distribution as the real data (L48).
#
# The colliding value is NOT named here either. Writing it into the comment that
# explains the collision puts it straight back into the tree, which is exactly
# what happened on the first attempt at this fix.
#
# Every case runs against throwaway trees and throwaway needle sources. Nothing
# reads Dan's real export except the one case that deliberately does, and that
# case prints counts only (L2, and the privacy floor in ovation#6).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "identity guard tests" 23

TARGET="scripts/check-identity-leaks.sh"
require_target "$TARGET"
harness_temp_dir WORK

# A stand-in export carrying the same field names as the real one.
make_export() {
    cat > "$1" <<JSON
{"version":3,"exportedAt":"2026-01-01T00:00:00Z",
 "clients":[{"id":"c1","displayName":"Zzfixture Chorale","contractEmail":"info@zzfixture-chorale.invalid","email":"x@y.com"},
            {"id":"c2","displayName":"Qqfixture Ensemble","contractEmail":"a@qqfixture-ensemble.invalid","email":""}],
 "venues":[{"id":"v1","name":"Zzfixture Hall"}],
 "bookings":[{"id":"b1","clientId":"c1","clientDisplayName":"Zzfixture Chorale","venueName":"Zzfixture Hall","shootName":"Zzfixture Concert"}]}
JSON
}
tree() { local d="$WORK/$1"; rm -rf "$d"; mkdir -p "$d"; printf '%s\n' "$d"; }

EXPORT="$WORK/export.json"; make_export "$EXPORT"
run_guard() {
    OVATION_GUARD_EXPORT="${2-$EXPORT}" \
    OVATION_GUARD_CUSTODY_DIR="${3-$WORK/nocustody}" \
    OVATION_GUARD_SCAN_ROOT="$1" \
        "./$TARGET" 2>&1
}

# 1. A clean tree passes, and says how many needles it actually used, so a run
#    that examined almost nothing cannot read as a thorough one.
T1="$(tree clean)"; printf 'ordinary source code\nlet x = 1\n' > "$T1/a.swift"
OUT1="$(run_guard "$T1")"; ST1=$?
check "a clean tree passes" "$ST1" "0"
check "and it reports how many needles it derived" \
    "$(printf '%s' "$OUT1" | grep -cE '[0-9]+ needle')" "1"
check "and how many files it examined" \
    "$(printf '%s' "$OUT1" | grep -cE '[0-9]+ file')" "1"

# 2. A client name in a TRACKED file is caught.
T2="$(tree tracked)"; printf 'let venue = "Zzfixture Chorale"\n' > "$T2/a.swift"
OUT2="$(run_guard "$T2")"; ST2=$?
check "a client display name in the tree is caught" \
    "$([ "$ST2" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and it names the FILE" "$(printf '%s' "$OUT2" | grep -c "a.swift")" "1"

# 3. AND IT NEVER PRINTS THE NAME. The guard's own output goes into transcripts,
#    scrollback and the end of turn review, by a route no file scanner inspects
#    (L222). Counts, paths and field names only.
check "and it does NOT print the name it found" \
    "$(printf '%s' "$OUT2" | grep -c "Zzfixture")" "0"
check "nor the venue name" "$(printf '%s' "$OUT2" | grep -c "Zzfixture Hall")" "0"
check "nor a contract email" "$(printf '%s' "$OUT2" | grep -c "zzfixture-chorale")" "0"

# 4. A name in a GITIGNORED file is caught too. The highest risk content on this
#    disk is exactly what .gitignore excludes, and a guard built on `git
#    ls-files` reads "do not track" as "do not look" (L250, L234).
T4="$(tree ignored)"
mkdir -p "$T4/.receipt-samples"
printf '.receipt-samples\n' > "$T4/.gitignore"
printf 'vendor: Zzfixture Hall\n' > "$T4/.receipt-samples/r.txt"
OUT4="$(run_guard "$T4")"; ST4=$?
check "a name inside a gitignored file is still found" \
    "$([ "$ST4" -ne 0 ] && echo nonzero || echo zero)" "nonzero"

# 5. Nested checkouts are skipped BY NAME. A recursive walk otherwise scans a
#    second full copy of everything, and Overture's .claude/worktrees proves they
#    exist in this estate (L234).
T5="$(tree nested)"
mkdir -p "$T5/.git/objects" "$T5/.claude/worktrees/agent-1"
printf 'Zzfixture Chorale\n' > "$T5/.git/objects/blob"
printf 'Zzfixture Chorale\n' > "$T5/.claude/worktrees/agent-1/copy.swift"
printf 'clean\n' > "$T5/ok.swift"
OUT5="$(run_guard "$T5")"; ST5=$?
check "a nested checkout is not scanned" "$ST5" "0"

# 6. THE REFUSAL THAT MATTERS MOST. An empty needle set must refuse NAMING the
#    emptiness. Through Phases 0b, 3 and 4, exactly when real receipts are on
#    this disk, a store derived needle set is near empty, and a guard that
#    reported clean would be examining almost nothing (L98, L214).
EMPTY="$WORK/empty.json"; printf '{"version":3,"clients":[],"venues":[],"bookings":[]}\n' > "$EMPTY"
T6="$(tree emptyneedles)"; printf 'Zzfixture Chorale\n' > "$T6/a.swift"
OUT6="$(run_guard "$T6" "$EMPTY")"; ST6=$?
check "a run that derived ZERO needles is refused" \
    "$([ "$ST6" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and it names the emptiness rather than reporting clean" \
    "$(printf '%s' "$OUT6" | grep -ci "no needles")" "1"
check "and it never claims nothing was found" \
    "$(printf '%s' "$OUT6" | grep -c "No derived identity appears")" "0"

# 7. An UNREADABLE source is CANNOT MEASURE, not a pass and not zero needles.
T7="$(tree unreadable)"
OUT7="$(run_guard "$T7" "$WORK/does-not-exist.json")"; ST7=$?
check "an unreadable needle source does not pass" \
    "$([ "$ST7" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and it says it could not measure, distinctly from finding nothing" \
    "$(printf '%s' "$OUT7" | grep -ci "cannot measure")" "1"

# 8. THE FALSE POSITIVE MEASURED ON THIS REPOSITORY, 2026-09-05. A trial run over
#    the six tracked files matched once: a six character single word client name
#    that is also an ordinary English word, inside a sentence about something
#    else. A substring match over needles derived from real business names WILL
#    over match, and an over match reads exactly like the feature working (L104).
#    So the guard must be tested against what it has to PRESERVE.
STOPWORDS="$WORK/stop.json"
cat > "$STOPWORDS" <<'JSON'
{"version":3,"clients":[{"id":"c1","displayName":"Stored","contractEmail":"a@b.com","email":""}],
 "venues":[{"id":"v1","name":"Counted"}],"bookings":[]}
JSON
T8="$(tree prose)"
printf 'The value is stored in the database and counted once.\nSee storedProcedure and countedRows.\n' > "$T8/notes.md"
OUT8="$(run_guard "$T8" "$STOPWORDS")"; ST8=$?
check "ordinary prose containing a name-shaped common word does not fire" "$ST8" "0"

# 9. But the SAME word as a genuine standalone occurrence still fires, so the
#    specificity rule cannot simply be "ignore short names".
T9="$(tree exact)"
printf 'client: Stored\n' > "$T9/x.txt"
OUT9="$(run_guard "$T9" "$STOPWORDS")"; ST9=$?
check "a short name is still caught where it stands alone" \
    "$([ "$ST9" -ne 0 ] && echo nonzero || echo zero)" "nonzero"

# 10. A multi word name is matched as a phrase, not as its separate words. Half a
#     name is not the name, and matching on it would fire constantly.
T10="$(tree partial)"
printf 'the ensemble met at the hall\n' > "$T10/y.txt"
OUT10="$(run_guard "$T10")"; ST10=$?
check "half of a multi word name does not fire" "$ST10" "0"

# 11. The custody snapshot is a needle source too, because it carries the same
#     names as the live export and outlives it (plan 0.3).
CUST="$WORK/custody"; mkdir -p "$CUST"
make_export "$CUST/downbeat-export-v3-2026-09-05.json"
T11="$(tree custody)"; printf 'Qqfixture Ensemble\n' > "$T11/z.txt"
OUT11="$(run_guard "$T11" "$WORK/nosuch-but-custody-exists.json" "$CUST")"
ST11=$?
check "names are derived from the custody snapshot as well as the export" \
    "$([ "$ST11" -ne 0 ] && echo nonzero || echo zero)" "nonzero"

# 12. A PLACEHOLDER IS NOT AN IDENTITY, and must never become a needle.
#
#     Found on the first real run against Dan's data. The guard refused on
#     PRD.md, twice on one line. The needle was "TBD": one of the nineteen real
#     bookings carries venueName "TBD" because its venue is not decided yet, and
#     the PRD says TBD twice in ordinary prose meaning exactly that.
#
#     The fix is the RULE, not an exemption naming PRD.md (L362). A placeholder
#     is a value the data uses to mean "not set". It identifies nobody, it is by
#     construction a common word, and searching for it can only ever produce
#     noise, in every file, for ever.
PLACEHOLDER="$WORK/placeholder.json"
cat > "$PLACEHOLDER" <<'JSON'
{"version":3,"clients":[{"id":"c1","displayName":"Zzfixture Chorale","contractEmail":"a@zz.invalid","email":""}],
 "venues":[{"id":"v1","name":"TBD"}],
 "bookings":[{"id":"b1","clientId":"c1","clientDisplayName":"Zzfixture Chorale","venueName":"TBD","shootName":"N/A"}]}
JSON
T12="$(tree placeholder)"
printf 'The cost is TBD, see 9.1. The count is TBD, see 9.2.
Status: N/A
Owner: Unknown
' > "$T12/notes.md"
OUT12="$(run_guard "$T12" "$PLACEHOLDER")"; ST12=$?
check "placeholder values in the data do not become needles" "$ST12" "0"
check "and the guard SAYS it dropped them, so coverage is not overstated" \
    "$(if printf '%s' "$OUT12" | grep -qi "placeholder"; then echo yes; else echo no; fi)" "yes"

# 13. But a real name in the SAME export is still caught, so the placeholder
#     filter cannot have simply emptied the needle set (L159).
T13="$(tree placeholder_real)"
printf 'client: Zzfixture Chorale
' > "$T13/x.txt"
OUT13="$(run_guard "$T13" "$PLACEHOLDER")"; ST13=$?
check "and a real name from that same export is still caught" \
    "$([ "$ST13" -ne 0 ] && echo nonzero || echo zero)" "nonzero"

# 14. An export of NOTHING BUT placeholders derives no needles at all, and that
#     is the refusal, not a clean report. Otherwise the filter becomes a way to
#     silently empty the guard.
ALLPLACEHOLDER="$WORK/allplaceholder.json"
cat > "$ALLPLACEHOLDER" <<'JSON'
{"version":3,"clients":[],"venues":[{"id":"v1","name":"TBD"}],
 "bookings":[{"id":"b1","venueName":"Unknown","shootName":"N/A"}]}
JSON
T14="$(tree allplaceholder)"; printf 'TBD
' > "$T14/y.txt"
OUT14="$(run_guard "$T14" "$ALLPLACEHOLDER")"; ST14=$?
check "an export of nothing but placeholders is REFUSED, not reported clean" \
    "$([ "$ST14" -ne 0 ] && echo nonzero || echo zero)" "nonzero"

harness_end
