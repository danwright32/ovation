#!/bin/bash
# No script may PRINT a real identity, and this is the half that had no
# enforcement at all.
#
# ovation#6, plan 0.1 steps 5 and 6. The .gitignore says what may be committed
# and scripts/check-custody-not-staged.sh enforces it. The identity guard says
# what may sit in a file and enforces that. Nothing said what may be PRINTED,
# and printed output reaches agent transcripts, terminal scrollback and the end
# of turn review by a route no file scanner inspects (L222). From there it goes
# wherever somebody pastes it.
#
# That is not hypothetical. On 2026-09-06 a full screen capture taken during
# this project's own work put roughly twenty real client names and their email
# addresses into a transcript in one action, and every file scanner in this
# repository was green throughout, correctly, because nothing had been written
# to a file.
#
# WHAT THIS DOES. It seeds a throwaway export carrying FABRICATED names in every
# field the guard derives identities from, points each check script at that
# fixture through the script's own seams, and asserts that none of those names
# appears in what the script prints. Counts, paths, ids and field names are
# fine. A display name, an address or a subject line is not.
#
# THE NEEDLES COME FROM THE GUARD'S OWN DERIVATION, imported rather than
# rewritten. A second copy of that logic would be a second definition of what
# counts as an identity, and it would drift in the flattering direction (L70,
# L107). Teaching the guard a new field therefore extends this suite's coverage
# on its own, with nobody having to remember.
#
# NOTHING HERE TOUCHES LIVE DATA. Every seam is pointed at a disposable fixture,
# and the fabricated names exist so that a leak in a test is a leak of nothing
# (L2, L155).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "output privacy tests" 29

require_target "scripts/check-identity-leaks.sh"
harness_temp_dir WORK

# ---------------------------------------------------------------------------
# The fixture. One fabricated identity in every field the guard reads.
# ---------------------------------------------------------------------------
CLIENT="Zzyzx Fictional Ensemble"
VENUE="Nowhere Concert Hall"
SHOOT="Winter Gala Of Nowhere"
DOMAIN="zzyzxfictional.example"

EXPORT="$WORK/export.json"
cat > "$EXPORT" <<JSON
{
  "version": 3,
  "clients": [
    {"id": "C1", "displayName": "$CLIENT",
     "email": "someone@$DOMAIN", "contractEmail": "contracts@$DOMAIN"}
  ],
  "venues": [{"id": "V1", "name": "$VENUE"}],
  "bookings": [
    {"id": "B1", "clientId": "C1", "clientDisplayName": "$CLIENT",
     "venueName": "$VENUE", "shootName": "$SHOOT",
     "startDate": "2026-10-25", "endDate": "2026-10-25"}
  ]
}
JSON

# Derived by the GUARD, not by this file. One needle per line.
NEEDLE_FILE="$WORK/needles.txt"
python3 -B - "$EXPORT" "$NEEDLE_FILE" <<'PY'
import importlib.util, sys
from importlib.machinery import SourceFileLoader
loader = SourceFileLoader("guard", "scripts/check-identity-leaks.sh")
spec = importlib.util.spec_from_loader("guard", loader)
guard = importlib.util.module_from_spec(spec)
loader.exec_module(guard)
problems = []
needles = guard.needles_from_export(sys.argv[1], "the fixture", problems)
needles = {n for n in needles if n.strip().lower() not in guard.PLACEHOLDERS}
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    for n in sorted(needles):
        fh.write(n + "\n")
sys.exit(1 if problems else 0)
PY
NEEDLE_COUNT="$(wc -l < "$NEEDLE_FILE" | tr -d ' ')"

# A run whose needle set is empty examines everything and finds nothing, which is
# indistinguishable from a clean tree (L98). So the set is asserted before it is
# used for anything.
check "the guard derives needles from the fixture at all" \
    "$([ "${NEEDLE_COUNT:-0}" -ge 5 ] && echo enough || echo "only ${NEEDLE_COUNT:-0}")" "enough"
check "and it reaches the venue, which only the venues list carries" \
    "$(grep -cxF "$VENUE" "$NEEDLE_FILE")" "1"
check "and the mail domain, which is derived rather than read" \
    "$(grep -cxF "$DOMAIN" "$NEEDLE_FILE")" "1"

# Does this text contain any derived identity? Word boundaries are NOT applied
# here, deliberately: this asks whether the name appears at all, in any form,
# and a looser question is the right one when the answer must be zero.
leaks_in() {
    local text="$1" n
    while IFS= read -r n; do
        [ -n "$n" ] || continue
        if printf '%s' "$text" | grep -qiF -- "$n"; then
            printf '%s' "LEAKED"
            return
        fi
    done < "$NEEDLE_FILE"
    printf '%s' "clean"
}

# ---------------------------------------------------------------------------
# SEEN TO FAIL FIRST (L1). A guard only ever seen to pass has not been seen to
# work, and the whole of this suite rests on leaks_in actually detecting one.
# ---------------------------------------------------------------------------
check "a script that prints a derived identity is caught" \
    "$(leaks_in "REFUSED: the booking for $CLIENT could not be read")" "LEAKED"
check "and one that prints a venue is caught" \
    "$(leaks_in "3 records, one at $VENUE")" "LEAKED"
check "while counts, ids and field names are not" \
    "$(leaks_in "PASS: 3 record(s), fields committedAt booking client, id B1")" "clean"

# ---------------------------------------------------------------------------
# EVERY check script, run so that it actually REPORTS something. A script that
# printed nothing would pass this suite while proving nothing about the branch
# that speaks (L98), so each is driven into a path that produces output.
# ---------------------------------------------------------------------------

# 1. The identity guard, driven into its REFUSED branch, which is the only one
#    that names the files it found and is therefore the one that could leak.
TREE="$WORK/tree"; mkdir -p "$TREE"
printf 'a file mentioning %s and %s\n' "$CLIENT" "$VENUE" > "$TREE/notes.md"
OUT_GUARD="$(OVATION_GUARD_EXPORT="$EXPORT" \
    OVATION_GUARD_CUSTODY_DIR="$WORK/no-custody" \
    OVATION_GUARD_SCAN_ROOT="$TREE" \
    ./scripts/check-identity-leaks.sh 2>&1)"
check "the identity guard found the planted identity, so its reporting branch ran" \
    "$(printf '%s' "$OUT_GUARD" | grep -c 'REFUSED')" "1"
check "and the identity guard prints no identity" "$(leaks_in "$OUT_GUARD")" "clean"

# 2. The booking queue reader, in both the branch that passes and the branch
#    that names a bad record.
QUEUE="$WORK/queue"; mkdir -p "$QUEUE"
cat > "$QUEUE/B1D4F0E2-8C3A-4F1B-9E77-0A2C6D5E4F31.json" <<JSON
{"version": 3, "committedAt": "2026-09-06T15:00:00Z",
 "booking": {"id": "B1", "clientDisplayName": "$CLIENT", "venueName": "$VENUE",
             "shootName": "$SHOOT"},
 "client": {"id": "C1", "displayName": "$CLIENT", "email": "someone@$DOMAIN"}}
JSON
check "the queue reader prints no identity when it passes" \
    "$(leaks_in "$(OVATION_BOOKING_QUEUE="$QUEUE" ./scripts/check-booking-queue.sh 2>&1)")" "clean"
printf 'not json\n' > "$QUEUE/7A2E9C10-4B6D-4E88-A3F5-C1094D7E2B60.json"
check "and none when it refuses a record it cannot read" \
    "$(leaks_in "$(OVATION_BOOKING_QUEUE="$QUEUE" ./scripts/check-booking-queue.sh 2>&1)")" "clean"

# 3. The sibling install verdict, which reads the export directly.
REPO="$WORK/repo"; git init -q "$REPO" 2>/dev/null
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty --no-verify -m first
GATE="$(git -C "$REPO" rev-parse HEAD)"
printf '{"commit":"%s","provenance":"main"}\n' "$GATE" > "$WORK/installed.json"
check "the sibling verdict prints no identity when it passes" \
    "$(leaks_in "$(OVATION_OVERTURE_BUILD_RECORD="$WORK/installed.json" \
        OVATION_OVERTURE_REPO="$REPO" OVATION_DOWNBEAT_EXPORT="$EXPORT" \
        OVATION_OVERTURE_GATE_COMMIT="$GATE" ./scripts/check-sibling-installs.sh 2>&1)")" "clean"

# 4. The custody staging check, run inside a throwaway repository.
CUSTODY_REPO="$WORK/custodyrepo"; mkdir -p "$CUSTODY_REPO/.receipt-samples"
git init -q "$CUSTODY_REPO" 2>/dev/null
cp "$EXPORT" "$CUSTODY_REPO/.receipt-samples/export.json"
check "the custody check prints no identity" \
    "$(leaks_in "$( cd "$CUSTODY_REPO" && OVATION_CUSTODY_PATHS=".receipt-samples" \
        "$OLDPWD/scripts/check-custody-not-staged.sh" 2>&1)")" "clean"

# 5. The ported artifact check, which reads source files rather than data.
check "the ported artifact check prints no identity" \
    "$(leaks_in "$(OVATION_PORT_SCAN_ROOT="$TREE" ./scripts/check-ported-artifacts.sh 2>&1)")" "clean"

# 6. The preconditions entry point, which RELAYS other checks' output indented
#    under their names. A relay is worth covering in its own right: it can leak
#    something none of the scripts it runs would have leaked on their own, and it
#    is the one a person actually invokes, so its output is the one that reaches
#    a transcript. The seams below are inherited by the checks it launches.
check "the preconditions entry point prints no identity when a check passes" \
    "$(leaks_in "$(OVATION_PRECONDITION_CHECKS="$PWD/scripts/check-booking-queue.sh" \
        OVATION_BOOKING_QUEUE="$QUEUE" ./scripts/check-preconditions.sh 2>&1)")" "clean"

# 7. The custody verifier. Its whole job is to touch files whose CONTENTS are
#    the most sensitive on this disk, so the assertion that it never opens one
#    for anything but hashing is the point rather than a formality.
CUSTODY_FILE="$WORK/recorded.json"
cp "$EXPORT" "$CUSTODY_FILE"
NOTE="$WORK/note.md"
{
    printf '# Custody records\n\n'
    printf '## recorded.json\n\n| Field | Value |\n| --- | --- |\n'
    printf '| Path | `%s` |\n' "$CUSTODY_FILE"
    printf '| SHA-256 | `%s` |\n' "$(shasum -a 256 "$CUSTODY_FILE" | cut -d' ' -f1)"
} > "$NOTE"
check "the custody verifier prints no identity when a file verifies" \
    "$(leaks_in "$(OVATION_CUSTODY_NOTE="$NOTE" ./scripts/check-custody-files.sh 2>&1)")" "clean"
printf 'changed\n' >> "$CUSTODY_FILE"
check "and none when it reports a hash mismatch" \
    "$(leaks_in "$(OVATION_CUSTODY_NOTE="$NOTE" ./scripts/check-custody-files.sh 2>&1)")" "clean"

# ---------------------------------------------------------------------------
# The forbidden construct guard. It walks Swift sources, and a comment on a money
# or a date line is exactly where a client name would sit, so it reports the
# file, the line number and the construct and NEVER the line itself.
# ---------------------------------------------------------------------------
MONEY_ROOT="$WORK/money-sources"
mkdir -p "$MONEY_ROOT"
cat > "$MONEY_ROOT/Pricing.swift" <<SWIFT
// The rate agreed with $CLIENT for the $SHOOT at $VENUE.
struct Pricing {
    let rate: Double
}
SWIFT
check "the construct guard prints no identity when it finds a forbidden type" \
    "$(leaks_in "$(OVATION_CONSTRUCT_SCAN_ROOT="$MONEY_ROOT" ./scripts/check-forbidden-constructs.sh 2>&1)")" \
    "clean"
printf 'struct Pricing {\n    let rateInCents: Int64\n}\n' > "$MONEY_ROOT/Pricing.swift"
check "and none when the sources are clean" \
    "$(leaks_in "$(OVATION_CONSTRUCT_SCAN_ROOT="$MONEY_ROOT" ./scripts/check-forbidden-constructs.sh 2>&1)")" \
    "clean"

# ---------------------------------------------------------------------------
# The isolation floor check. It walks Swift sources and prints paths, line
# numbers and resolver names. A comment on a resolver line is exactly where a
# client name would sit, so it must never print the line itself.
# ---------------------------------------------------------------------------
FLOOR_ROOT="$WORK/floor-sources"
mkdir -p "$FLOOR_ROOT/App"
cat > "$FLOOR_ROOT/Store.swift" <<SWIFT
enum Store {
    // Where the $CLIENT booking for the $SHOOT at $VENUE is kept.
    static func liveStoreURL() -> URL? { nil }
}
SWIFT
printf 'enum LiveDataFloor { static let entries: [Entry] = [] }\n' \
    > "$FLOOR_ROOT/App/LiveDataFloor.swift"
check "the isolation floor check prints no identity when it refuses" \
    "$(leaks_in "$(OVATION_FLOOR_SCAN_ROOT="$FLOOR_ROOT" \
        OVATION_FLOOR_REGISTER="$FLOOR_ROOT/App/LiveDataFloor.swift" \
        ./scripts/check-isolation-floor.sh 2>&1)")" "clean"
printf 'enum LiveDataFloor { static let entries = [Entry(name: "liveStoreURL")] }\n' \
    > "$FLOOR_ROOT/App/LiveDataFloor.swift"
check "and none when every resolver is registered" \
    "$(leaks_in "$(OVATION_FLOOR_SCAN_ROOT="$FLOOR_ROOT" \
        OVATION_FLOOR_REGISTER="$FLOOR_ROOT/App/LiveDataFloor.swift" \
        ./scripts/check-isolation-floor.sh 2>&1)")" "clean"

# ---------------------------------------------------------------------------
# The schema registration check. It prints TYPE NAMES and paths relative to the
# scan root, so a client name sitting in a model's source, which is exactly where
# one would sit, must not travel out with the refusal.
# ---------------------------------------------------------------------------
SCHEMA_ROOT="$WORK/schema-sources"
mkdir -p "$SCHEMA_ROOT/Persistence"
cat > "$SCHEMA_ROOT/Invoice.swift" <<SWIFT
@Model
final class Invoice {
    var client: String = "$CLIENT"
    var venue: String = "$VENUE"
}
SWIFT
printf 'enum OvationSchema { static let models: [any PersistentModel.Type] = [] }\n' \
    > "$SCHEMA_ROOT/Persistence/OvationSchema.swift"
check "the schema check prints no identity when it refuses" \
    "$(leaks_in "$(OVATION_SCHEMA_SCAN_ROOT="$SCHEMA_ROOT" \
        OVATION_SCHEMA_FILE="$SCHEMA_ROOT/Persistence/OvationSchema.swift" \
        ./scripts/check-schema-registered.sh 2>&1)")" "clean"
printf 'enum OvationSchema { static let models = [Invoice.self] }\n' \
    > "$SCHEMA_ROOT/Persistence/OvationSchema.swift"
check "and none when every model is registered" \
    "$(leaks_in "$(OVATION_SCHEMA_SCAN_ROOT="$SCHEMA_ROOT" \
        OVATION_SCHEMA_FILE="$SCHEMA_ROOT/Persistence/OvationSchema.swift" \
        ./scripts/check-schema-registered.sh 2>&1)")" "clean"

# ---------------------------------------------------------------------------
# The migration stage guard. It prints TYPE NAMES from the schema file and
# nothing else, so a client name sitting in a comment in that file must not
# reach the output, on the refusing path or the passing one.
# ---------------------------------------------------------------------------
STAGES_FILE="$WORK/stages.swift"
cat > "$STAGES_FILE" <<SWIFT
// A note about $CLIENT at $VENUE, which has no business in any output.
enum OvationMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OvationSchemaV1.self, OvationSchemaV2.self]
    }
    static var stages: [MigrationStage] { [] }
}
SWIFT
check "the migration stage guard prints no identity when it refuses" \
    "$(leaks_in "$(OVATION_SCHEMA_FILE="$STAGES_FILE" \
        ./scripts/check-migration-stages.sh 2>&1)")" "clean"
cat > "$STAGES_FILE" <<SWIFT
// A note about $CLIENT at $VENUE, which has no business in any output.
enum OvationMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [OvationSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
SWIFT
check "and none when the versions and stages are in step" \
    "$(leaks_in "$(OVATION_SCHEMA_FILE="$STAGES_FILE" \
        ./scripts/check-migration-stages.sh 2>&1)")" "clean"

# ---------------------------------------------------------------------------
# The design self containment guard. It prints the FILE, the LINE and the name
# of the construct, never the line itself, so a client name sitting in a design
# file beside a forbidden reference must not reach the output.
# ---------------------------------------------------------------------------
DESIGN_ROOT="$WORK/design"
mkdir -p "$DESIGN_ROOT"
cat > "$DESIGN_ROOT/invoice-list.html" <<HTML
<h1>$CLIENT at $VENUE</h1>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo">
HTML
check "the design self containment guard prints no identity when it refuses" \
    "$(leaks_in "$(OVATION_DESIGN_ROOT="$DESIGN_ROOT" \
        ./scripts/check-design-self-contained.sh 2>&1)")" "clean"
cat > "$DESIGN_ROOT/invoice-list.html" <<HTML
<h1>$CLIENT at $VENUE</h1>
HTML
check "and none when the record is self contained" \
    "$(leaks_in "$(OVATION_DESIGN_ROOT="$DESIGN_ROOT" \
        ./scripts/check-design-self-contained.sh 2>&1)")" "clean"

# ---------------------------------------------------------------------------
# The live data bracket. It prints watched PATHS relative to Application
# Support, which are Ovation's own filenames, never a client's.
# ---------------------------------------------------------------------------
LIVE_ROOT="$WORK/live-support"
mkdir -p "$LIVE_ROOT/Ovation"
printf 'a receipt for %s\n' "$CLIENT" > "$LIVE_ROOT/Ovation/problems.jsonl"
OVATION_LIVE_DATA_ROOT="$LIVE_ROOT" ./scripts/check-live-data-untouched.sh \
    snapshot "$WORK/live.json" >/dev/null 2>&1
printf 'and another for %s at %s\n' "$CLIENT" "$VENUE" >> "$LIVE_ROOT/Ovation/problems.jsonl"
check "the live data bracket prints no identity when it refuses" \
    "$(leaks_in "$(OVATION_LIVE_DATA_ROOT="$LIVE_ROOT" \
        ./scripts/check-live-data-untouched.sh compare "$WORK/live.json" 2>&1)")" "clean"

# ---------------------------------------------------------------------------
# The launch sequence wiring guard. It prints the PATH of the entry point and
# nothing from inside it, so a client name sitting in that file must not reach
# the output even when the guard refuses.
# ---------------------------------------------------------------------------
WIRED_ROOT="$WORK/wired"
mkdir -p "$WIRED_ROOT"
{
    printf '@main\n'
    printf 'struct OvationApp: App {\n'
    printf '    // A note about %s at %s, which has no business in any output.\n' "$CLIENT" "$VENUE"
    printf '    init() {}\n'
    printf '}\n'
} > "$WIRED_ROOT/OvationApp.swift"
check "the launch wiring guard prints no identity when it refuses" \
    "$(leaks_in "$(OVATION_ENTRY_POINT="$WIRED_ROOT/OvationApp.swift" \
        ./scripts/check-launch-sequence-wired.sh 2>&1)")" "clean"

# ---------------------------------------------------------------------------
# COMPLETENESS. A hand written list of covered scripts silently exempts whatever
# nobody remembered to add, and the exempted one is the one this suite exists
# for (L96, L247). So the list is asserted against what is actually on disk, and
# a new check script fails HERE until somebody points it at the fixture.
# ---------------------------------------------------------------------------
COVERED="check-booking-queue.sh check-custody-files.sh check-custody-not-staged.sh check-design-self-contained.sh check-forbidden-constructs.sh check-identity-leaks.sh check-isolation-floor.sh check-launch-sequence-wired.sh check-live-data-untouched.sh check-migration-stages.sh check-ported-artifacts.sh check-preconditions.sh check-schema-registered.sh check-sibling-installs.sh"
ON_DISK="$(cd scripts && ls -1 check-*.sh | sort | tr '\n' ' ')"
check "every check script on disk is covered by this suite" \
    "$(printf '%s' "$ON_DISK" | tr -s ' ' | sed 's/ $//')" \
    "$(printf '%s' "$COVERED" | tr -s ' ' | sed 's/ $//')"

harness_end
