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
harness_begin "output privacy tests" 120

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
        if grep -qiF -- "$n" <<< "$text"; then
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
# EVERY SOURCE IS A FIXTURE (ovation#278). This run used to set three of the
# guard's five, so the store and the booking queue fell back to Dan's live ones
# on every push. The check at the end of this file refuses any guard run in any
# suite that leaves one unset.
# An empty fingerprint file: zero fingerprints is a valid state, and this run is
# about the identity branch rather than the fingerprint one.
: > "$WORK/fingerprints-none.txt"
OUT_GUARD="$(OVATION_GUARD_EXPORT="$EXPORT" \
    OVATION_GUARD_CUSTODY_DIR="$WORK/no-custody" \
    OVATION_GUARD_STORE="$WORK/no-store/Ovation.store" \
    OVATION_GUARD_QUEUE_DIR="$WORK/no-queue" \
    OVATION_GUARD_FINGERPRINTS="$WORK/fingerprints-none.txt" \
    OVATION_GUARD_SCAN_ROOT="$TREE" \
    ./scripts/check-identity-leaks.sh 2>&1)"
check "the identity guard found the planted identity, so its reporting branch ran" \
    "$(printf '%s' "$OUT_GUARD" | grep -c 'REFUSED')" "1"
check "and the identity guard prints no identity" "$(leaks_in "$OUT_GUARD")" "clean"

# 1b. THE EMBEDDED INVOICE PAGE CHECK (ovation#167). It reads the invoice PDF
#     design, whose fixtures carry client, venue and shoot names, and it reports
#     drift. The planted names sit in the design's page builder, which is what
#     reaches the drift branch, so the case prints from the one branch that could
#     carry them.
EMBED="$WORK/embedded-design"; mkdir -p "$EMBED"
cp docs/design/invoice-pdf.html docs/design/review-send.html "$EMBED/"
python3 - "$EMBED/invoice-pdf.html" "$CLIENT" "$VENUE" <<'PYEMBED'
import sys
path, client, venue = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()
old = 'settled ? "Paid in full" : "Amount due"'
assert old in text, "the planted change matched nothing, so this case tests nothing"
open(path, "w", encoding="utf-8").write(text.replace(old, '"Due to %s at %s"' % (client, venue), 1))
PYEMBED
OUT_EMBED="$(OVATION_DESIGN_ROOT="$EMBED" ./scripts/check-design-embedded-page.sh 2>&1)"
check "the embedded page check reached its drift branch over a design carrying names" \
    "$(printf '%s' "$OUT_EMBED" | grep -c '^DRIFTED:')" "1"
check "and the embedded page check prints no identity" "$(leaks_in "$OUT_EMBED")" "clean"

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

# 4b. The hooks path check (ovation#430), which prints a configured path.
check "the hooks path check prints no identity" \
    "$(leaks_in "$( cd "$CUSTODY_REPO" && git config core.hooksPath "$CUSTODY_REPO/scripts/git-hooks" \
        && "$OLDPWD/scripts/check-hooks-path.sh" 2>&1)")" "clean"

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
# The motion owner guard (ovation#124). It walks Swift sources and prints paths,
# line numbers and construct names. A comment beside an animation is as good a
# place for a client's name as any other, so the line itself must never travel
# out with the refusal.
# ---------------------------------------------------------------------------
MOTION_ROOT="$WORK/motion-sources"
mkdir -p "$MOTION_ROOT/Roster" "$MOTION_ROOT/App"
cat > "$MOTION_ROOT/Roster/OvationMotion.swift" <<'SWIFT'
enum OvationMotion {
    static func animation(_ kind: Kind, reduceMotion: Bool) -> Animation? { nil }
}
SWIFT
cat > "$MOTION_ROOT/App/Screen.swift" <<SWIFT
// The pane $CLIENT opens for the $SHOOT at $VENUE.
func open() {
    withAnimation(.easeInOut) { showing = true }
}
SWIFT
check "the motion owner guard prints no identity when it refuses" \
    "$(leaks_in "$(OVATION_MOTION_SCAN_ROOT="$MOTION_ROOT" ./scripts/check-motion-owner.sh 2>&1)")" \
    "clean"
check "and that refusal really did name the construct, so the case reached the line that prints" \
    "$(OVATION_MOTION_SCAN_ROOT="$MOTION_ROOT" ./scripts/check-motion-owner.sh 2>&1 \
        | grep -c 'App/Screen.swift:3: withAnimation')" "1"
printf 'struct Screen: View {\n    var body: some View { list.ovationMotion(.slide, value: open) }\n}\n' \
    > "$MOTION_ROOT/App/Screen.swift"
check "and none when every screen goes through the component" \
    "$(leaks_in "$(OVATION_MOTION_SCAN_ROOT="$MOTION_ROOT" ./scripts/check-motion-owner.sh 2>&1)")" \
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

# The rule inlining guard reads a record of the same shape, and an earlier
# version of it QUOTED A LINE OF THE RULE back to say where the copy stopped
# matching, which is the one thing here that would print file CONTENT rather than
# a filename. So the fixture puts a client and a venue INSIDE the rule as well as
# inside the design file, and the guard now names the line number instead.
#
# ITS OWN ROOT, rather than the one above with a rules/ folder added and taken
# away again. The harness owns every removal in this suite (ovation#19), so a
# fixture that needs a different shape gets a different directory.
RULES_ROOT="$WORK/design-with-rules"
mkdir -p "$RULES_ROOT/rules"
cat > "$RULES_ROOT/rules/duration.js" <<JS
function who() {
  return "$CLIENT at $VENUE";
}
JS
cat > "$RULES_ROOT/invoice-list.html" <<HTML
<h1>$CLIENT at $VENUE</h1>
<script>
function who() {
  return "somebody else entirely";
}
</script>
HTML
check "the rule inlining guard prints no identity when a copy has drifted" \
    "$(leaks_in "$(OVATION_DESIGN_ROOT="$RULES_ROOT" \
        ./scripts/check-design-rules-inline.sh 2>&1)")" "clean"
check "and none when it cannot compare anything at all" \
    "$(leaks_in "$(OVATION_DESIGN_ROOT="$RULES_ROOT/nowhere" \
        ./scripts/check-design-rules-inline.sh 2>&1)")" "clean"

# THE MEASUREMENT MARKING GUARD (ovation#201). It reads the design record's PROSE,
# which is where a client name would sit, and it QUOTES back the inside of a
# marking it could not read. So the fixture puts an identity in the prose, in the
# marking itself, and in the paragraph whose unmarked numbers get counted, which
# are the three places anything it prints could come from.
MARKS_ROOT="$WORK/design-with-markings"
mkdir -p "$MARKS_ROOT/lib"
printf '# A fixture inventory.\ncheck-nothing.sh\tgated\tA repo wide guard.\n' \
    > "$MARKS_ROOT/lib/script-roles.tsv"
cat > "$MARKS_ROOT/README.md" <<MD
# The design record

The band for $CLIENT at $VENUE was 318px wide, \`measured $CLIENT\`.

$SHOOT drew 12 rows at 1246px and nothing behind it.
MD
check "the measurement marking guard prints no identity when it refuses" \
    "$(leaks_in "$(OVATION_DESIGN_ROOT="$MARKS_ROOT" OVATION_SCRIPTS_ROOT="$MARKS_ROOT" \
        ./scripts/check-design-measurements-marked.sh 2>&1)")" "clean"
check "and that refusal really did reach the line that quotes a marking" \
    "$(OVATION_DESIGN_ROOT="$MARKS_ROOT" OVATION_SCRIPTS_ROOT="$MARKS_ROOT" \
        ./scripts/check-design-measurements-marked.sh 2>&1 | grep -c 'UNREADABLE DATE line 3')" "1"
check "and none when it is only counting the numbers nothing marks" \
    "$(leaks_in "$(OVATION_DESIGN_ROOT="$MARKS_ROOT" OVATION_SCRIPTS_ROOT="$MARKS_ROOT" \
        ./scripts/check-design-measurements-marked.sh 2>&1 | grep unmarked)")" "clean"

# The shell inlining guard (ovation#120) has the same three ways of speaking
# about a file it disagrees with, and one more the rules guard does not have: it
# repeats the file's OWN SENTENCE back when the file declares it carries no
# shell. A design file's prose is where a client name would sit, so the fixture
# puts one in the declaration as well as in the CSS and in the page.
SHELL_ROOT="$WORK/design-with-shell"
mkdir -p "$SHELL_ROOT/shell"
cat > "$SHELL_ROOT/shell/window.css" <<CSS
.win { content: "$CLIENT at $VENUE"; }
CSS
cat > "$SHELL_ROOT/invoice-list.html" <<HTML
<h1>$CLIENT at $VENUE</h1>
<style>
.win { content: "somebody else entirely"; }
</style>
HTML
check "the shell inlining guard prints no identity when a copy has drifted" \
    "$(leaks_in "$(OVATION_DESIGN_ROOT="$SHELL_ROOT" \
        ./scripts/check-design-shell-inline.sh 2>&1)")" "clean"
cat > "$SHELL_ROOT/invoice-list.html" <<HTML
<style>
/* NOT SHELLED: window.css, this page is for $CLIENT at $VENUE and draws no window. */
.unrelated { color: red; }
</style>
HTML
check "and none when it repeats a file's own reason for carrying no shell" \
    "$(leaks_in "$(OVATION_DESIGN_ROOT="$SHELL_ROOT" \
        ./scripts/check-design-shell-inline.sh 2>&1)")" "clean"
check "and none when it cannot compare anything at all either" \
    "$(leaks_in "$(OVATION_DESIGN_ROOT="$SHELL_ROOT/nowhere" \
        ./scripts/check-design-shell-inline.sh 2>&1)")" "clean"

# The dead rule guard, ovation#166. It names a SELECTOR and the classes in it,
# both of which are things we wrote in a stylesheet, and never the element's
# text, which is where a client name would sit. The fixture puts a name in the
# page's prose, in a class attribute and in a declaration, because the check
# reads all three and prints from none of them.
DEAD_ROOT="$WORK/design-dead"
mkdir -p "$DEAD_ROOT"
cat > "$DEAD_ROOT/invoice-list.html" <<HTML
<h1>$CLIENT at $VENUE</h1>
<style>
.gone { content: "$CLIENT at $VENUE"; }
.here { color: #111; }
</style>
<div class="here">$CLIENT at $VENUE</div>
HTML
check "the dead rule guard prints no identity when it refuses a rule" \
    "$(leaks_in "$(OVATION_DESIGN_ROOT="$DEAD_ROOT" \
        python3 ./scripts/check-design-dead-rules.sh 2>&1)")" "clean"
cat > "$DEAD_ROOT/invoice-list.html" <<HTML
<h1>$CLIENT at $VENUE</h1>
<style>
.here { color: #111; }
</style>
<div class="here">x</div>
HTML
check "and none on the clean run either" \
    "$(leaks_in "$(OVATION_DESIGN_ROOT="$DEAD_ROOT" \
        python3 ./scripts/check-design-dead-rules.sh 2>&1)")" "clean"
check "and none when it cannot measure at all" \
    "$(leaks_in "$(OVATION_DESIGN_ROOT="$DEAD_ROOT/nowhere" \
        python3 ./scripts/check-design-dead-rules.sh 2>&1)")" "clean"

# The shared component guard, ovation#149. It names a CLASS and a file, both of
# which are things we wrote, and never any element's text. The fixture puts a
# name in the page's prose and in a class attribute.
COMPONENT_ROOT="$WORK/design-components"
mkdir -p "$COMPONENT_ROOT"
cat > "$COMPONENT_ROOT/invoice-list.html" <<HTML
<h1>$CLIENT at $VENUE</h1>
<style>
.choicelist { position: absolute; }
.choicelist button { display: block; }
</style>
<div class="choicelist">$CLIENT at $VENUE</div>
HTML
check "the shared component guard prints no identity when it refuses" \
    "$(leaks_in "$(OVATION_DESIGN_ROOT="$COMPONENT_ROOT" \
        python3 ./scripts/check-design-shared-components.sh 2>&1)")" "clean"
check "and none when it cannot measure" \
    "$(leaks_in "$(OVATION_DESIGN_ROOT="$COMPONENT_ROOT/nowhere" \
        python3 ./scripts/check-design-shared-components.sh 2>&1)")" "clean"

# The design record's open list, ovation#172. It prints issue numbers and line
# numbers, and never the sentence, which is prose and is where a client or a
# venue would be named. The fixture puts one in the section it reads.
OPENLIST="$WORK/design-openlist"
mkdir -p "$OPENLIST"
cat > "$OPENLIST/README.md" <<MD
# The design record

## What is still open

The screen for $CLIENT at $VENUE is ovation#100 and ovation#101.
MD
cat > "$WORK/openlist-reader.sh" <<'SH'
#!/bin/bash
  [ "$1" = "100" ] && { printf 'OPEN'; exit 0; }
  printf 'CLOSED'
SH
chmod +x "$WORK/openlist-reader.sh"
check "the design record status check prints no identity when it refuses" \
    "$(leaks_in "$(OVATION_DESIGN_ROOT="$OPENLIST" \
        OVATION_ISSUE_STATE_COMMAND="bash $WORK/openlist-reader.sh {n}" \
        python3 ./scripts/check-design-record-open.sh 2>&1)")" "clean"
check "and none when it cannot measure" \
    "$(leaks_in "$(OVATION_DESIGN_ROOT="$OPENLIST/nowhere" \
        python3 ./scripts/check-design-record-open.sh 2>&1)")" "clean"

# The CI liveness watcher, ovation#155. It prints two instants, a grace period
# and a verdict, and it is in the set for the reason above rather than because
# anybody thought a date could name a client. The dates are fed in, so all three
# of its outcomes are reachable here.
check "the CI liveness watcher prints no identity when it passes" \
    "$(leaks_in "$(OVATION_CI_NOW=2026-09-09T12:00:00Z \
        OVATION_CI_LAST_SUCCESS=2026-09-09T11:00:00Z \
        OVATION_CI_LAST_COMMIT=2026-09-09T10:00:00Z \
        ./scripts/check-ci-liveness.sh 2>&1)")" "clean"
check "and none when it refuses" \
    "$(leaks_in "$(OVATION_CI_NOW=2026-09-09T12:00:00Z \
        OVATION_CI_LAST_SUCCESS=2026-09-01T11:00:00Z \
        OVATION_CI_LAST_COMMIT=2026-09-08T10:00:00Z \
        ./scripts/check-ci-liveness.sh 2>&1)")" "clean"
check "and none when it cannot measure" \
    "$(leaks_in "$(OVATION_CI_NOW=2026-09-09T12:00:00Z \
        ./scripts/check-ci-liveness.sh 2>&1)")" "clean"

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
# The icon currency guard. It prints FILENAMES and PATHS, which the privacy floor
# permits, and never the content of anything. The fixture puts a client name
# where the guard would have to reach in order to leak it: inside the catalog, as
# a stray file's own bytes, on the path that NAMES a file no derivation produces.
# ---------------------------------------------------------------------------
ICON_WORK="$WORK/icon"
mkdir -p "$ICON_WORK/catalog"
python3 -c 'import sys
from PIL import Image
Image.new("RGB", (1254, 1254), (12, 34, 56)).save(sys.argv[1] + "/art.png")' \
    "$ICON_WORK" 2>/dev/null || true
printf 'a note about %s at %s\n' "$CLIENT" "$VENUE" > "$ICON_WORK/catalog/stray.txt"
check "the icon currency guard prints no identity when it refuses" \
    "$(leaks_in "$(OVATION_ICON_SOURCE="$ICON_WORK/art.png" \
        OVATION_ICON_CATALOG="$ICON_WORK/catalog" \
        ./scripts/check-app-icon-current.sh 2>&1)")" "clean"
check "and none when it cannot measure at all" \
    "$(leaks_in "$(OVATION_ICON_SOURCE="$ICON_WORK/nowhere.png" \
        OVATION_ICON_CATALOG="$ICON_WORK/catalog" \
        ./scripts/check-app-icon-current.sh 2>&1)")" "clean"

# ---------------------------------------------------------------------------
# The invoice history tool. It is the one script here that opens Dan's REAL
# records, so it is the one where a leak would be a real client rather than a
# fixture. It prints counts and shares only.
# ---------------------------------------------------------------------------
HISTORY="$WORK/history.csv"
cat > "$HISTORY" <<CSV
Invoice #,Invoice Status,Client Name,Item Name,Quantity,Line Subtotal,Discount Percentage,Tax 1 Amount,Date Issued
1101,Paid,$CLIENT,$VENUE,2,500,0,44.38,2026-01-04
1102,Sent,$CLIENT,$VENUE,1,250,0,22.19,2026-01-06
CSV
check "the invoice history tool prints no identity from a real export" \
    "$(leaks_in "$(./scripts/measure-invoice-history.py "$HISTORY" 2>&1)")" "clean"
printf 'Invoice #,Invoice Status,Client Name,Item Name,Quantity,Line Subtotal,Discount Percentage,Tax 1 Amount,Date Issued\n1103,Draft,%s,%s,1,250,0,0,2026-01-06\n' \
    "$CLIENT" "$VENUE" > "$HISTORY"
check "and none when it refuses because nothing was issued" \
    "$(leaks_in "$(./scripts/measure-invoice-history.py "$HISTORY" 2>&1)")" "clean"

# The Downbeat export measurement, ovation#121. It opens the file that carries
# every real client, shoot, venue and hosting site name in plain text, and
# prints counts and shares only. The fixture puts a name in every field it
# reads, including the ones it groups by.
BOOKINGS="$WORK/bookings.json"
cat > "$BOOKINGS" <<JSON
{ "version": 3, "exportedAt": "2026-08-29T15:07:27Z", "blockedDates": [],
  "venues": [{"id": "v1", "name": "$VENUE"}],
  "bookings": [{"id": "b1", "clientDisplayName": "$CLIENT",
                "shootName": "$VENUE", "venueName": "$VENUE",
                "startsAt": "2026-10-25T19:00:00Z", "endsAt": "2026-10-25T20:00:00Z"}],
  "clients": [{"id": "c1", "displayName": "$CLIENT", "hostingSite": "$VENUE",
               "email": "$CLIENT", "contractEmail": "$VENUE",
               "specialBehaviors": ["$CLIENT"]}] }
JSON
BOOKINGS_SHA="$(shasum -a 256 "$BOOKINGS" | cut -d' ' -f1)"
check "the booking export measurement prints no identity when it measures" \
    "$(leaks_in "$(./scripts/measure-booking-export.py "$BOOKINGS" "$BOOKINGS_SHA" 2>&1)")" "clean"
check "and none when the hash does not match" \
    "$(leaks_in "$(./scripts/measure-booking-export.py "$BOOKINGS" \
        0000000000000000000000000000000000000000000000000000000000000000 2>&1)")" "clean"
# THE LIVE COMPARISON (ovation#216) reads a second file carrying every real
# client, and prints field names and differences. The live fixture differs from
# the snapshot in a name, a count and a field whose NAME is harmless and whose
# value is an identity, so every line the comparison can print is reached.
BOOKINGS_LIVE="$WORK/bookings-live.json"
cat > "$BOOKINGS_LIVE" <<JSON
{ "version": 3, "exportedAt": "2026-09-13T15:07:27Z", "blockedDates": [],
  "venues": [{"id": "v1", "name": "$VENUE", "notes": "$SHOOT"}],
  "bookings": [{"id": "b1", "clientDisplayName": "$CLIENT",
                "startsAt": "2026-10-25T19:00:00Z", "endsAt": "2026-10-25T20:00:00Z"},
               {"id": "b2", "clientDisplayName": "$CLIENT", "shootName": "$SHOOT",
                "startsAt": "2026-10-26T19:00:00Z", "endsAt": "2026-10-26T21:00:00Z"}],
  "clients": [{"id": "1D6F2C3A-0000-4000-8000-000000000001", "displayName": "$CLIENT",
               "email": "$CLIENT", "contractEmail": "$VENUE", "isTaxExempt": true,
               "hostingSite": "$VENUE", "specialBehaviors": ["$CLIENT"]}] }
JSON
LIVE_OUT="$(./scripts/measure-booking-export.py "$BOOKINGS" "$BOOKINGS_SHA" --live "$BOOKINGS_LIVE" 2>&1)"
check "and none when it compares the live export with the snapshot" "$(leaks_in "$LIVE_OUT")" "clean"
check "and it really did compare them, so the case reached every line that prints" \
    "$(printf '%s' "$LIVE_OUT" | grep -c 'figure(s) differ, and')" "1"
printf 'not json at all, it is about %s\n' "$CLIENT" > "$BOOKINGS"
check "and none when the file cannot be read at all" \
    "$(leaks_in "$(./scripts/measure-booking-export.py "$BOOKINGS" \
        "$(shasum -a 256 "$BOOKINGS" | cut -d' ' -f1)" 2>&1)")" "clean"

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# THE PAYMENT TERMS GUARD (ovation#98 round D). It compares the term list the
# Clients screen offers against the one the invoice screen offers, and its
# refusal PRINTS the terms that do not agree.
#
# THE NEEDLE IS IN THE PROSE, NOT IN THE TERMS, and that is the case worth
# testing rather than a way around one. The terms are PRD 7's fixed vocabulary,
# four constants in code; a client's name can never be one. What a design file
# genuinely does carry is prose, paragraphs of it, and that is where a name
# would sit. So the fixture puts one in each file's prose and in a comment
# beside the very declaration the guard reads, and the claim is that a guard
# which prints part of a file prints only the part it is about.
# ---------------------------------------------------------------------------
TERMS_DIR="$WORK/terms"
mkdir -p "$TERMS_DIR"
cat > "$TERMS_DIR/clients.html" <<HTML
<p>The Clients screen, drawn from the roster $CLIENT is on, photographed at $VENUE.</p>
<script>
/* $CLIENT asked for these terms after the shoot at $VENUE. */
var TERMS = ["On receipt", "7 days", "14 days", "21 days", "30 days"];
</script>
HTML
cat > "$TERMS_DIR/invoice.html" <<HTML
<p>The invoice screen, as sent to $CLIENT for the run at $VENUE.</p>
<script>
/* $CLIENT is invoiced on these. */
var TERMS = [["On receipt", 0], ["7 days", 7], ["14 days", 14], ["30 days", 30]];
</script>
HTML
check "the payment terms guard prints no identity when the two lists disagree" \
    "$(leaks_in "$(./scripts/check-design-terms-agree.sh \
        "$TERMS_DIR/clients.html" "$TERMS_DIR/invoice.html" 2>&1)")" "clean"
# AND IT REALLY DID REFUSE, naming the term. Without this the case above would
# pass just as well on a guard that printed nothing at all, having never reached
# the line that prints anything (L159).
check "and that refusal really did name the term, so the case reached it" \
    "$(./scripts/check-design-terms-agree.sh \
        "$TERMS_DIR/clients.html" "$TERMS_DIR/invoice.html" 2>&1 | grep -c '21 days')" "1"
# The other thing it prints is a file it cannot read, and it names that file by
# PATH. A path is permitted output in this repository, alongside counts, ids and
# field names, so the fixture does not plant a name in one: an assertion that a
# guard may not print a path it was HANDED would be stricter than the rule, and
# would be answered by making the refusal say less rather than by making it safe.
# What is asserted is that a guard which cannot read its subject still prints
# nothing OUT of it.
check "and none when it cannot read a file" \
    "$(leaks_in "$(./scripts/check-design-terms-agree.sh \
        "$TERMS_DIR/clients.html" "$TERMS_DIR/not-there.html" 2>&1)")" "clean"

# ---------------------------------------------------------------------------
# THE PRD CITATION GUARD (ovation#199). It reads every file git tracks, which on
# Dan's machine includes the design record and the issues, and it refuses by
# naming a FILE, a LINE NUMBER and a requirement number. It never prints the line
# it found, and that is the property asserted here: the fixture puts an identity
# on the very line that carries the bad citation, so a refusal that quoted its
# context would fail this.
# ---------------------------------------------------------------------------
# The word is held in a variable for the reason check-prd-citations.sh records:
# a file that spells a broken citation is refused by the check it is driving.
CITE_WORD="PRD"
CITE="$WORK/citetree"
mkdir -p "$CITE"
cp PRD.md "$CITE/PRD.md"
cat > "$CITE/notes.md" <<MD
Agreed with $CLIENT at $VENUE during $SHOOT, recorded at ${CITE_WORD} 999.
MD
( cd "$CITE" && git init -q -b main . && git add -A ) >/dev/null 2>&1
check "the PRD citation guard prints no identity when it refuses" \
    "$(leaks_in "$(./scripts/check-prd-citations.sh "$CITE" 2>&1)")" "clean"
# AND IT REALLY DID REFUSE, naming the citation, or the case above would pass on
# a guard that printed nothing at all, having never reached the line that prints
# anything (L159).
check "and that refusal really did name the citation, so the case reached it" \
    "$(./scripts/check-prd-citations.sh "$CITE" 2>&1 | grep -c "notes.md:1 cites ${CITE_WORD} 5.999")" "1"

# ---------------------------------------------------------------------------
# THE PLAN CLAIMS GUARD (ovation#181). It became a gated check when the push gate
# learned to treat its exit 3 as "no siblings here", and a gated check is one this
# suite must cover. It reads TWO OTHER CHECKOUTS, whose files carry comments, and
# a comment beside a booking is exactly where a client name sits (L222). What it
# prints is paths, line numbers and the PLAN's own quoted literals, and the
# fixture below puts an identity in each of the three places it could leak from:
# the sibling source it reads, the plan row it quotes, and the file name itself.
# ---------------------------------------------------------------------------
PLANDIR="$WORK/planclaims"
# BOTH siblings have to be present or the guard answers "no Overture here" and
# never opens the file carrying the name, which would pass this case without
# reaching anything (L159).
mkdir -p "$PLANDIR/siblings/Downbeat/Downbeat" "$PLANDIR/siblings/Overture"
cat > "$PLANDIR/siblings/Downbeat/Downbeat/Booking.swift" <<SWIFT
// Booked by $CLIENT for $SHOOT at $VENUE.
let marker = "anchored"
SWIFT
cat > "$PLANDIR/plan.md" <<MD
# A plan

| what | where | says |
| --- | --- | --- |
| the booking | \`Downbeat/Downbeat/Booking.swift:2\` | \`anchored\`, written for $CLIENT |
| the missing one | \`Downbeat/Downbeat/$VENUE.swift:9\` | \`gone\` |
MD
# THE FIFTH KIND READS THREE MORE PLACES A NAME SITS (ovation#215): the record's
# prose around a claim, Downbeat's contract, and the live export, whose values
# are every real client. Each carries one here, and the claim is one that
# refuses, so the lines that print field names are the ones reached.
mkdir -p "$PLANDIR/siblings/Downbeat/Downbeat/Integration/OvertureExport"
printf '# Contract\n\nWritten for %s. OvertureClient: `id`, `isTaxExempt` (bool).\n' "$CLIENT" \
    > "$PLANDIR/siblings/Downbeat/Downbeat/Integration/OvertureExport/CONTRACT.md"
printf 'The Downbeat export has no field for a tax status, which %s asked about at %s.\n' \
    "$CLIENT" "$VENUE" > "$PLANDIR/record.md"
printf '{"version": 3, "clients": [{"id": "c1", "displayName": "%s", "isTaxExempt": true}]}\n' \
    "$CLIENT" > "$PLANDIR/live.json"
PLAN_OUT="$(OVATION_PLAN="$PLANDIR/plan.md" OVATION_SIBLING_ROOT="$PLANDIR/siblings" \
    OVATION_SIBLING_INSTALL_CHECK="/nonexistent" OVATION_BOOKING_EXPORT="/nonexistent" \
    OVATION_EXPORT_RECORDS="$PLANDIR/record.md" OVATION_LIVE_EXPORT="$PLANDIR/live.json" \
    ./scripts/check-plan-claims.sh 2>&1)"
check "the plan claims guard prints no identity" "$(leaks_in "$PLAN_OUT")" "clean"
# AND IT REALLY DID READ THE ESTATE, or the case above would pass on a guard that
# printed nothing at all, having never reached the line that prints anything
# (L159). The anchored row is the one it can only answer by opening the sibling
# file that carries the name.
check "and it really did anchor a row in the sibling file, so the case reached it" \
    "$(printf '%s' "$PLAN_OUT" | grep -c 'HELD')" "1"
check "and it really did judge the record against the contract and the live export" \
    "$(printf '%s' "$PLAN_OUT" | grep -c 'DERIVABLE .*CONTRACT.md:3.*the live export')" "1"

# ---------------------------------------------------------------------------
# THE SIX RENDERING CHECKS (ovation#214). They were declared `tool` while
# .github/workflows/ci.yml was running them, and `tool` is the one role in the
# inventory this suite does not cover. Declaring them truthfully brought them
# into the set, which is the obligation working rather than a side effect: these
# READ A PAGE AND QUOTE WHAT THEY FOUND ON IT, and they print into a CI log of a
# repository that is public on purpose, which is a more public place than a
# terminal, not a less public one.
#
# ONE PLANTED PAGE TRIPS ALL SIX, and it carries a fabricated client and venue in
# its visible text, which is where a rendered reading would pick them up: it
# names a token nothing defines, throws on load, draws almost nothing, carries no
# sidebar card, and declares no app window.
# ---------------------------------------------------------------------------
DESIGN="$WORK/design"; mkdir -p "$DESIGN"
cat > "$DESIGN/staged.html" <<HTML
<!doctype html>
<title>A staged design file</title>
<style>.win { color: var(--nowhere-defined); }</style>
<div class="win">A shoot for $CLIENT at $VENUE</div>
<script>notAFunction();</script>
HTML

# WHICH PATH THE RUN TOOK, so a case cannot pass on the branch that speaks about
# nothing. Without a browser every one of these refuses at the lookup, before it
# has read a page, and a clean output there says nothing at all about the branch
# that quotes one (L98, L411).
verdict_of() {
    case "$1" in
        *"CANNOT MEASURE"*) printf 'no browser' ;;
        *REFUSED*|*FAIL*|*UNRESOLVED*|*"NO CARD"*) printf 'read the page' ;;
        *) printf 'said nothing either way' ;;
    esac
}
# DETECTED, NOT ASSUMED, and through the same lookup the checks themselves use,
# so the expectation cannot disagree with what they will do (L70).
STAGED_BROWSER="$(python3 -B -c 'import sys; sys.path.insert(0, "scripts/lib"); import design_render; print(design_render.find_browser() or "")' 2>/dev/null)"
if [ -n "$STAGED_BROWSER" ]; then
    RENDER_PATH="read the page"
else
    RENDER_PATH="no browser"
    echo "NOTE: there is no headless browser here, so the six rendering checks below"
    echo "      were driven into their CANNOT MEASURE path. Their output was clean,"
    echo "      and the branch that quotes a page was not reached on this machine."
fi

OUT="$(OVATION_DESIGN_ROOT="$DESIGN" ./scripts/check-design-draws.sh 2>&1)"
check "the every file rendering check prints no identity" "$(leaks_in "$OUT")" "clean"
check "and it took the path this machine can reach" "$(verdict_of "$OUT")" "$RENDER_PATH"

OUT="$(OVATION_DESIGN_ROOT="$DESIGN" ./scripts/check-design-tokens-resolve.sh 2>&1)"
check "the token resolution check prints no identity" "$(leaks_in "$OUT")" "clean"
check "and it too took the path this machine can reach" "$(verdict_of "$OUT")" "$RENDER_PATH"

OUT="$(OVATION_DESIGN_ROOT="$DESIGN" ./scripts/check-design-sidebar-card.sh 2>&1)"
check "the sidebar card check prints no identity" "$(leaks_in "$OUT")" "clean"
check "and the card check took the path this machine can reach" "$(verdict_of "$OUT")" "$RENDER_PATH"

OUT="$(OVATION_DESIGN_ROOT="$DESIGN" ./scripts/check-design-window-top.sh 2>&1)"
check "the window ceiling check prints no identity" "$(leaks_in "$OUT")" "clean"
check "and the ceiling check took the path this machine can reach" "$(verdict_of "$OUT")" "$RENDER_PATH"

# These two take the file as an argument rather than a root, and they print the
# path they rendered, which is a path and not an identity. The fixture is named
# for nobody so that stays true.
OUT="$(./scripts/check-invoice-screen-draws.sh "$DESIGN/staged.html" 2>&1)"
check "the invoice screen check prints no identity" "$(leaks_in "$OUT")" "clean"
check "and the invoice screen check took the path this machine can reach" \
    "$(verdict_of "$OUT")" "$RENDER_PATH"

OUT="$(./scripts/check-clients-screen-draws.sh "$DESIGN/staged.html" 2>&1)"
check "the clients screen check prints no identity" "$(leaks_in "$OUT")" "clean"
check "and the clients screen check took the path this machine can reach" \
    "$(verdict_of "$OUT")" "$RENDER_PATH"

# ---------------------------------------------------------------------------
# THE BACKUP GRANT RECORD (ovation#232). It prints dates and verdicts, and the
# record it reads deliberately carries no path, because this repository is
# public and where Dan's records are copied to is his business. Covered like
# every other gated script, because the rule is that every one is checked, not
# every one somebody thought was risky (L129, L96).
# ---------------------------------------------------------------------------
GRANT="$WORK/grant.tsv"
printf '# header\n2026-09-12\tlapsed\t%s at %s\n' "$CLIENT" "$VENUE" > "$GRANT"
check "the backup grant check prints no identity, even from a record somebody edited" \
    "$(leaks_in "$(OVATION_GRANT_RECORD="$GRANT" ./scripts/check-backup-grant.sh 2>&1)")" "clean"
check "and it really did report a verdict, so the case reached the line that prints" \
    "$(OVATION_GRANT_RECORD="$GRANT" ./scripts/check-backup-grant.sh 2>&1 | grep -c 'BLOCKED')" "1"

# ---------------------------------------------------------------------------
# THE PROBLEM KINDS CHECK (ovation#262). It prints file names, line numbers and
# kind names, never a source line, and the line it refuses here carries a client
# and a venue, which is exactly where a sentence about a real booking would sit.
# ---------------------------------------------------------------------------
KINDS="$WORK/kinds"
mkdir -p "$KINDS"
printf 'extension ProblemKind {\n    static let folderMissing = ProblemKind("backup.folder-missing")\n}\n' \
    > "$KINDS/Problem.swift"
printf 'for p in problems.open where p.kind == .folderMissing { note("%s at %s") }\n' \
    "$CLIENT" "$VENUE" > "$KINDS/Settings.swift"
check "the problem kinds check prints no identity when it refuses" \
    "$(leaks_in "$(OVATION_KINDS_SCAN_ROOT="$KINDS" ./scripts/check-problem-kinds-raised.sh 2>&1)")" "clean"
check "and that refusal really did print a finding, so the case reached the line that prints" \
    "$(OVATION_KINDS_SCAN_ROOT="$KINDS" ./scripts/check-problem-kinds-raised.sh 2>&1 | grep -c 'matched here, raised nowhere')" "1"

# ---------------------------------------------------------------------------
# THE PULL REQUEST DESCRIPTION CHECK (ovation#261). It reads a description a
# person wrote, which is exactly where a sentence about a real booking sits, and
# it prints into the log of a repository that is public on purpose. It prints the
# reference it refused and its corrected spelling, never the line around it.
# ---------------------------------------------------------------------------
PR_BODY="$WORK/pr-body.md"
printf 'The invoice for %s at %s was wrong. Closes ovation#9.\n' "$CLIENT" "$VENUE" > "$PR_BODY"
check "the pull request description check prints no identity when it refuses" \
    "$(leaks_in "$(OVATION_PR_BODY_FILE="$PR_BODY" ./scripts/check-pr-closing-keywords.sh 2>&1)")" "clean"
check "and that refusal really did name the reference, so the case reached the line that prints" \
    "$(OVATION_PR_BODY_FILE="$PR_BODY" ./scripts/check-pr-closing-keywords.sh 2>&1 | grep -c 'Closes ovation#9')" "1"

# ---------------------------------------------------------------------------
# THE XCODE SELECTOR (ovation#270). It prints versions and paths, and the one
# thing it quotes that a person wrote is the pin file. A pin carrying a sentence
# rather than a version is refused, and the refusal quotes it, so that is the
# path this drives: covered because every workflow script is, not because this
# one looked risky (L129, L96).
# ---------------------------------------------------------------------------
XPIN="$WORK/xcode-version"
printf '%s at %s\n' "$CLIENT" "$VENUE" > "$XPIN"
XSEL_OUT="$(OVATION_XCODE_VERSION_FILE="$XPIN" OVATION_XCODE_APPS_DIR="$WORK" \
    OVATION_XCODE_SELECT_COMMAND=/nonexistent OVATION_XCODEBUILD=/nonexistent \
    ./scripts/select-xcode.sh 2>&1)"
check "the Xcode selector prints no identity, even from a pin somebody edited" \
    "$(leaks_in "$XSEL_OUT")" "clean"
check "and it really did refuse the pin, so the case reached the line that quotes one" \
    "$(printf '%s' "$XSEL_OUT" | grep -c 'CANNOT MEASURE')" "1"

# ---------------------------------------------------------------------------
# THE INVOICE FOOTER SOURCE CHECK (ovation#319). It reads every Swift file under
# the app and prints the PATHS of the ones that read the shipped footer text. It
# must never print a LINE of any of them: the file it is refusing is the one that
# builds an invoice, so the lines around the match are where a real client's name
# would sit if one were ever written into a fixture or a comment.
# ---------------------------------------------------------------------------
FOOTER_TREE="$WORK/footer-tree"
mkdir -p "$FOOTER_TREE/Ovation/App" "$FOOTER_TREE/Ovation/Document"
printf 'struct InvoiceFooter {}\n' > "$FOOTER_TREE/Ovation/Document/InvoiceDocument.swift"
printf '// the page for %s at %s\nlet d = InvoiceFooter.fixed\n' \
    "$CLIENT" "$VENUE" > "$FOOTER_TREE/Ovation/App/InvoiceScreen.swift"
FOOTER_OUT="$(OVATION_REPO_ROOT="$FOOTER_TREE" ./scripts/check-invoice-footer-source.sh 2>&1)"
check "the invoice footer source check prints no identity from the file it refuses" \
    "$(leaks_in "$FOOTER_OUT")" "clean"
check "and it really did refuse, so the case reached the lines that name a file" \
    "$(printf '%s' "$FOOTER_OUT" | grep -c 'REFUSED')" "1"

# ---------------------------------------------------------------------------
# THE ONE ACTION WORD CHECK (ovation#450). It reads every Swift file under the
# app and prints the PATHS and LINE NUMBERS of the ones drawing an underlined
# control. It must never print a LINE of any of them: the files it refuses are
# the ones that draw invoices and rows, so the lines around a match are exactly
# where a real client's name would sit if one were ever written into a preview,
# a fixture or a comment.
# ---------------------------------------------------------------------------
WORD_TREE="$WORK/action-word-tree"
mkdir -p "$WORD_TREE/Ovation/Invoices"
printf 'struct ActionWord: View { var body: some View { Text("x").underline() } }\n' \
    > "$WORD_TREE/Ovation/Invoices/ActionWord.swift"
printf '// the row for %s at %s\nText(action).underline()\n' \
    "$CLIENT" "$VENUE" > "$WORD_TREE/Ovation/Invoices/InvoiceListView.swift"
WORD_OUT="$(OVATION_REPO_ROOT="$WORD_TREE" ./scripts/check-one-action-word.sh 2>&1)"
check "the one action word check prints no identity from the file it refuses" \
    "$(leaks_in "$WORD_OUT")" "clean"
check "and it really did refuse, so the case reached the lines that name a file" \
    "$(printf '%s' "$WORD_OUT" | grep -c 'REFUSED')" "1"

# ---------------------------------------------------------------------------
# THE WAITING SENTENCE GUARD (ovation#117). Its whole subject is COPY: the
# sentences the app says to Dan and the design record's own words for them. When
# they disagree it prints the sentence that is missing, which is the one thing
# here that prints CONTENT by design rather than a filename.
#
# THAT IS SAFE AND IS ASSERTED RATHER THAN ASSUMED. Neither file holds client
# data: `waiting.js` is a rule in the design record and `ReviewGate.swift` is
# app source. But nothing stops somebody putting a real name in an example, and
# this is the case that would find it, so the fixture PUTS ONE THERE and requires
# the guard to stay clean about everything except the sentence itself (L129).
# ---------------------------------------------------------------------------
WAIT_JS="$WORK/waiting-leak.js"
cat > "$WAIT_JS" <<JS
function waitingOnFor(start, end) {
  if (start === null) {
    return { reason: "start", says: "Needs it",
             tip: "Waiting on the time the shoot started." };
  }
  return null;
}
JS
WAIT_SWIFT="$WORK/gate-leak.swift"
printf 'enum ReviewGate {
    // the draft for %s at %s
    static func sentence() -> String {
        return "Waiting on something else entirely."
    }
}
' \
    "$CLIENT" "$VENUE" > "$WAIT_SWIFT"
WAIT_OUT="$(./scripts/check-waiting-sentences-agree.sh "$WAIT_JS" "$WAIT_SWIFT" 2>&1)"
check "the waiting sentence guard prints no identity from the file it refuses" \
    "$(leaks_in "$WAIT_OUT")" "clean"
check "and it really did refuse, so the case reached the line that quotes a sentence" \
    "$(printf '%s' "$WAIT_OUT" | grep -c 'DRIFTED')" "1"

# ---------------------------------------------------------------------------
# THE RUNNER XCODE WATCHER (ovation#320). It reads three things it did not write
# and prints about all three: the pin, the CI workflow, and a manifest fetched
# from GitHub. It runs only in a workflow, so its log is published, which is why
# it is covered here rather than because any one path looked risky (L129).
#
# ALL THREE ARE DRIVEN, because covering whichever seemed likeliest is how the
# other two come to have no reviewer at all. Each case also asserts its branch was
# REACHED, since a refusal earlier than the line that prints would leave this
# passing while covering nothing (L159).
# ---------------------------------------------------------------------------
RX_PIN="$WORK/runner-xcode-pin"
printf '%s at %s\n' "$CLIENT" "$VENUE" > "$RX_PIN"
RX_FETCH="$WORK/runner-xcode-fetch"
printf '#!/bin/bash\nprintf "### Xcode\\n| Version | Build |\\n| 26.6 (default) | %s at %s |\\n"\n' \
    "$CLIENT" "$VENUE" > "$RX_FETCH"
chmod +x "$RX_FETCH"
RX_WF_ONE="$WORK/runner-xcode-ci.yml"
printf '# CI for %s at %s\njobs:\n  mac:\n    runs-on: macos-26\n' "$CLIENT" "$VENUE" > "$RX_WF_ONE"
RX_WF_TWO="$WORK/runner-xcode-ci-two.yml"
printf '# CI for %s at %s\njobs:\n  a:\n    runs-on: macos-26\n  b:\n    runs-on: macos-15\n' \
    "$CLIENT" "$VENUE" > "$RX_WF_TWO"
RX_GOOD_PIN="$WORK/runner-xcode-good-pin"
printf '26.6\n' > "$RX_GOOD_PIN"

RX_PIN_OUT="$(OVATION_XCODE_VERSION_FILE="$RX_PIN" OVATION_CI_WORKFLOW="$RX_WF_ONE" \
    OVATION_RUNNER_MANIFEST_COMMAND="$RX_FETCH" ./scripts/check-runner-xcode.sh 2>&1)"
check "the runner Xcode watcher prints no identity from a pin somebody edited" \
    "$(leaks_in "$RX_PIN_OUT")" "clean"
check "and it really did refuse that pin, so the case reached the line about one" \
    "$(printf '%s' "$RX_PIN_OUT" | grep -c 'CANNOT MEASURE')" "1"

# THE MANIFEST IS THE ONE IT DOES NOT CONTROL AT ALL. A build column carrying a
# sentence is what a changed upstream format looks like, and the versions it
# reads back are the only part of that document it may repeat.
RX_MAN_OUT="$(OVATION_XCODE_VERSION_FILE="$RX_GOOD_PIN" OVATION_CI_WORKFLOW="$RX_WF_ONE" \
    OVATION_RUNNER_MANIFEST_COMMAND="$RX_FETCH" ./scripts/check-runner-xcode.sh 2>&1)"
check "and it prints no identity from the manifest it fetched" \
    "$(leaks_in "$RX_MAN_OUT")" "clean"
check "and it really did read that manifest, so the case reached the lines that list it" \
    "$(printf '%s' "$RX_MAN_OUT" | grep -c 'is the newest')" "1"

# AND THE WORKFLOW, whose refusal prints back the runner names it found there.
RX_WF_OUT="$(OVATION_XCODE_VERSION_FILE="$RX_GOOD_PIN" OVATION_CI_WORKFLOW="$RX_WF_TWO" \
    OVATION_RUNNER_MANIFEST_COMMAND="$RX_FETCH" ./scripts/check-runner-xcode.sh 2>&1)"
check "and it prints no identity from the workflow it read" \
    "$(leaks_in "$RX_WF_OUT")" "clean"
check "and it really did refuse over the two runners, so the case reached that list" \
    "$(printf '%s' "$RX_WF_OUT" | grep -c 'REFUSED')" "1"

# ---------------------------------------------------------------------------
# THE XCODE PROJECT CURRENCY CHECK (ovation#206). It prints file paths and
# counts, never a line of the project file or of project.yml, and both of those
# carry a client and a venue here, which is where a comment about a real booking
# would sit.
# ---------------------------------------------------------------------------
PROJTREE="$WORK/projtree"
mkdir -p "$PROJTREE/App" "$PROJTREE/Ovation.xcodeproj"
printf '# sources for %s at %s\ntargets:\n  Ovation:\n    sources:\n      - path: App\n' \
    "$CLIENT" "$VENUE" > "$PROJTREE/project.yml"
printf 'struct Listed {}\n' > "$PROJTREE/App/Listed.swift"
printf 'struct Unlisted {}\n' > "$PROJTREE/App/Unlisted.swift"
printf '// %s at %s\n{\n\t\t000000000000000000000001 /* Listed.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Listed.swift; sourceTree = "<group>"; };\n}\n' \
    "$CLIENT" "$VENUE" > "$PROJTREE/Ovation.xcodeproj/project.pbxproj"
check "the Xcode project currency check prints no identity when it refuses" \
    "$(leaks_in "$(OVATION_REPO_ROOT="$PROJTREE" OVATION_XCODE_PROJECT="$PROJTREE/Ovation.xcodeproj" ./scripts/check-xcode-project-current.sh 2>&1)")" "clean"
check "and that refusal really did name a file, so the case reached the line that prints" \
    "$(OVATION_REPO_ROOT="$PROJTREE" OVATION_XCODE_PROJECT="$PROJTREE/Ovation.xcodeproj" ./scripts/check-xcode-project-current.sh 2>&1 | grep -c 'App/Unlisted.swift')" "1"

# ---------------------------------------------------------------------------
# THE FINDING REPORTER (ovation#339). It is handed a TITLE and a BODY FILE that
# a workflow composed, and both are free text that could carry anything, so this
# plants an identity in each and asserts that what the script itself prints
# carries neither. It prints issue numbers and counts, which name the finding
# exactly and carry nothing (L15). The tracker is an injected stub that answers
# from a file and writes nowhere, so this reaches nothing real (L2).
# ---------------------------------------------------------------------------
REPORT="$WORK/report"; mkdir -p "$REPORT/bin"
cat > "$REPORT/bin/gh" <<'STUB'
#!/bin/bash
# Answers the lookup with two issues carrying one marker title, so the run takes
# the MANY refusal: that is the outcome which prints the most about what it
# found, and it writes nothing. Indented because scripts/test-run-tests.sh reads
# a heredoc's lines exactly like a suite's own and refuses a `$1` on one of them.
    [ "${1:-} ${2:-}" = "issue list" ] && printf '%s' "$OVATION_TEST_LIST_JSON"
    exit 0
STUB
chmod +x "$REPORT/bin/gh"
printf 'A finding about %s at %s.\n' "$CLIENT" "$VENUE" > "$REPORT/body.md"
REPORT_OUT="$(OVATION_GH="$REPORT/bin/gh" \
    OVATION_TEST_LIST_JSON='[{"number":44,"title":"A finding naming '"$CLIENT"'"},{"number":91,"title":"A finding naming '"$CLIENT"'"}]' \
    ./scripts/report-finding.sh stands --title "A finding naming $CLIENT" \
        --body-file "$REPORT/body.md" --comment-file "$REPORT/body.md" 2>&1)"
check "the finding reporter prints no identity from the title or the body it was given" \
    "$(leaks_in "$REPORT_OUT")" "clean"
check "and it really did report a refusal, so the case reached the lines that print" \
    "$(printf '%s' "$REPORT_OUT" | grep -c 'MANY')" "1"

# ---------------------------------------------------------------------------
# THE BROWSER RESTART REPORTER (ovation#352). It prints the run it read, the
# artifact it looked for and how many restarts it found, and it PASSES ON the
# record's own lines to the reporter rather than printing them. The record is
# written by the renderer and names pages under docs/design/, but a run this
# public repository publishes must be checked rather than reasoned about, so the
# record here carries an identity in the one field that is free text (L129). The
# tracker and the reporter are stubs, so this reaches nothing real (L2).
# ---------------------------------------------------------------------------
RESTART="$WORK/restart"; mkdir -p "$RESTART/bin" "$RESTART/payload"
cat > "$RESTART/bin/gh" <<'STUB'
#!/bin/bash
# Lists the artifact and unpacks the staged record. Indented for the reason the
# stub above is: a heredoc's lines are read like a suite's own (L135).
    if [ "${1:-}" = "api" ]; then printf 'browser-restarts\n'; exit 0; fi
    dir=""
    while [ "$#" -gt 0 ]; do
        [ "$1" = "--dir" ] && dir="${2:-}"
        shift
    done
    [ -n "$dir" ] && mkdir -p "$dir" && cp "$OVATION_TEST_RECORD" "$dir/browser-restarts.tsv"
    exit 0
STUB
chmod +x "$RESTART/bin/gh"
printf '#!/bin/bash\nexit 1\n' > "$RESTART/bin/reporter"
chmod +x "$RESTART/bin/reporter"
printf '2026-09-15T10:00:00Z\tPage.navigate\t%s at %s\n' "$CLIENT" "$VENUE" > "$RESTART/record.tsv"
RESTART_OUT="$(OVATION_GH="$RESTART/bin/gh" \
    OVATION_REPORT_FINDING="$RESTART/bin/reporter" \
    OVATION_RESTART_RECORD_DIR="$RESTART/out" \
    OVATION_RESTART_RUN_ID=4242 \
    OVATION_TEST_RECORD="$RESTART/record.tsv" \
    GITHUB_REPOSITORY="danwright32/ovation" \
    ./scripts/report-browser-restarts.sh 2>&1)"
check "the browser restart reporter prints no identity from the record it read" \
    "$(leaks_in "$RESTART_OUT")" "clean"
check "and it really did report an occurrence, so the case reached the lines that print" \
    "$(printf '%s' "$RESTART_OUT" | grep -c 'reported on the issue')" "1"

# ---------------------------------------------------------------------------
# THE REVIEW SAMPLES CHECK (ovation#318). It prints the terms it found in a product,
# and those terms are read out of the SOURCES, so a source that named a real client
# would put that name in a CI log of a public repository. The identity is planted in
# the sample source here and the check is driven over staged products, so nothing
# real is read and nothing is built (L2).
# ---------------------------------------------------------------------------
SAMPLES="$WORK/samples"; mkdir -p "$SAMPLES/Ovation/Document" \
    "$SAMPLES/products/Debug/Ovation.app/Contents/MacOS" \
    "$SAMPLES/products/Release/Ovation.app/Contents/MacOS"
printf '#if DEBUG\nlet sample = "%s at %s"\n#endif\n' "$CLIENT" "$VENUE" \
    > "$SAMPLES/Ovation/Document/ReviewSamples.swift"
printf '#if DEBUG\nlet world = "Autumn Concert"\n#endif\n' \
    > "$SAMPLES/Ovation/Document/ReviewSampleWorld.swift"
printf 'x%s at %sx\nxAutumn Concertx\n' "$CLIENT" "$VENUE" \
    > "$SAMPLES/products/Debug/Ovation.app/Contents/MacOS/Ovation"
printf 'x%s at %sx\n' "$CLIENT" "$VENUE" \
    > "$SAMPLES/products/Release/Ovation.app/Contents/MacOS/Ovation"
SAMPLES_OUT="$(OVATION_REPO_ROOT="$SAMPLES" OVATION_PRODUCTS_DIR="$SAMPLES/products" \
    ./scripts/check-review-samples-absent.sh 2>&1)"
check "the review samples check prints no identity from the sources it read" \
    "$(leaks_in "$SAMPLES_OUT")" "clean"
check "and it really did report a leak, so the case reached the lines that print" \
    "$(printf '%s' "$SAMPLES_OUT" | grep -c 'reached the Release')" "1"

# ---------------------------------------------------------------------------
# THE PRIVATE PACKAGE CREDENTIAL (ovation#424). This one holds an actual SECRET,
# which no other script in the set does, and it runs in a workflow whose logs are
# published because this repository is public on purpose. So the question here is
# not only whether it prints Dan's identity, it is whether it prints the TOKEN.
#
# BOTH PATHS ARE DRIVEN, because the refusing one quotes the NAME of the secret
# and the configuring one is handed its VALUE. A test of only the refusal would
# never hold a token at all and would pass without measuring anything (L159).
#
# HOME IS A THROWAWAY, so `git config --global` writes into the temp directory
# and this case cannot touch the real machine's git config (L2).
# ---------------------------------------------------------------------------
PKG_TOKEN="ghp_NOTAREALTOKEN000000000000000000000000"
mkdir -p "$WORK/pkgauth" "$WORK/pkgauth2"
PKG_OUT="$(env HOME="$WORK/pkgauth" CI=1 BACKSTAGE_READ_TOKEN="$PKG_TOKEN" \
    ./scripts/configure-private-package-access.sh 2>&1)"
check "the private package credential step never prints the token it was given" \
    "$(printf '%s' "$PKG_OUT" | grep -c "$PKG_TOKEN")" "0"
check "and it really did configure, so the case reached the line that holds one" \
    "$(grep -c 'insteadOf' "$WORK/pkgauth/.gitconfig" 2>/dev/null)" "1"
check "and it prints no identity either" "$(leaks_in "$PKG_OUT")" "clean"
PKG_REFUSED="$(env HOME="$WORK/pkgauth2" CI=1 BACKSTAGE_READ_TOKEN= \
    ./scripts/configure-private-package-access.sh 2>&1)"
check "the refusal names the secret, and cannot leak a value it never had" \
    "$(printf '%s' "$PKG_REFUSED" | grep -c 'BACKSTAGE_READ_TOKEN is not set')" "1"
check "and the refusal prints no identity" "$(leaks_in "$PKG_REFUSED")" "clean"

# COMPLETENESS, derived from the script inventory rather than from a hand
# written list (ovation#86). A list somebody maintains silently exempts whatever
# nobody remembered to add, and the exempted one is the one this suite exists for
# (L96, L247). The inventory says which scripts can print about real data:
# everything `gated`, because a guard reads the tree and Dan's own files, and
# everything `reads-real-data`. A new one of either fails HERE until it is
# pointed at a fixture above.
# ---------------------------------------------------------------------------
. scripts/lib/script-roles.sh
# WORKFLOW SCRIPTS ARE IN THE SET TOO (ovation#172). This repository is
# PUBLIC on purpose, so a CI log is a published document and a script that
# only ever runs in a workflow prints somewhere MORE public than a gated one,
# not less. Leaving them out was a habit rather than a decision, and a
# category exempted for no recorded reason has no reviewer at all (L129).
MUST_BE_COVERED="$( { roles_with gated; roles_with reads-real-data; roles_with workflow; } | sort -u | tr '\n' ' ' | sed 's/ $//')"
# What this suite actually exercises, read from its own text rather than
# declared beside it, so the two cannot drift (L70).
#
# `select-` IS IN THE PATTERN BECAUSE A ROLE, NOT A NAME, PUTS A SCRIPT IN THE
# SET (ovation#270). scripts/select-xcode.sh is run by a workflow and so must be
# covered, and it is not called check-: it CHANGES which Xcode a machine builds
# with, and a name that reads like an inspection must not modify anything
# (L206). A pattern blind to it would refuse a script this suite covers (L63).
# `report-` joined it for the same reason (ovation#339): scripts/report-finding.sh
# is run by two workflows, so the inventory puts it in the set, and it WRITES to
# the tracker rather than inspecting anything.
# `configure-` joined it on 2026-09-20 for the third instance of the same thing
# (ovation#424): scripts/configure-private-package-access.sh is run by both macOS
# jobs, so the inventory puts it in the set, and it CONFIGURES a credential rather
# than inspecting anything. It is also the only script in the set that holds a
# secret, which is the strongest reason for it to be covered here, not the
# weakest.
EXERCISED="$(grep -oE './scripts/(check|configure|measure|report|select)-[a-z-]+\.(sh|py)' "$0" \
    | sed 's|^./scripts/||' | sort -u | tr '\n' ' ' | sed 's/ $//')"
check "every script that can print about real data is covered by this suite" \
    "$EXERCISED" "$MUST_BE_COVERED"

# ---------------------------------------------------------------------------
# THE CI WORKFLOW GUARD (ovation#143). It reads a YAML file and prints job names,
# file names and counts. A workflow is an unlikely place for a client name, which
# is exactly why it is covered: the rule is that every gated script is checked,
# not every gated script somebody thought was risky (L129, L96).
# ---------------------------------------------------------------------------
WF="$WORK/workflows"
mkdir -p "$WF"
# The job key is a plain token ON PURPOSE, because the guard's refusal PRINTS
# the job name and a key with spaces in it would not parse as one: the case would
# then pass without ever reaching the line that prints anything (L159).
cat > "$WF/ci.yml" <<YML
name: A run for $CLIENT at $VENUE
jobs:
  a-job:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "$CLIENT at $VENUE"
YML
check "the CI workflow guard prints no identity when it refuses" \
    "$(leaks_in "$(OVATION_WORKFLOW_DIR="$WF" ./scripts/check-ci-workflow.sh 2>&1)")" "clean"
check "and that refusal really did print a job name, so the case reached it" \
    "$(OVATION_WORKFLOW_DIR="$WF" ./scripts/check-ci-workflow.sh 2>&1 | grep -c 'NO TIMEOUT: a-job')" "1"

# ---------------------------------------------------------------------------
# EVERY TEST RUN OF THE IDENTITY GUARD POINTS EVERY SOURCE AT A FIXTURE
# (ovation#278).
#
# This suite promises at its head that it touches no live data, and its own
# guard run above set three of the guard's five sources, so the other two fell
# back to Dan's live store and booking queue on every push. A run that sets SOME
# of a script's seams runs every unset one for real, and nothing looked (L284,
# L2).
#
# So this is the class rather than the instance (L30): every place any suite
# RUNS the real guard must set every source the guard reads. The list is read
# from the guard's own environment lookups rather than typed out here, so a
# source added to the guard tomorrow is covered without anybody remembering
# (L41). The guard's name is assembled from pieces, because a scanner that
# spells out what it hunts for finds itself (L245).
# ---------------------------------------------------------------------------
unfixtured_guard_runs() {
    python3 -B - "$1" "scripts/check-identity-leaks.sh" <<'PYSEAMS'
import glob, os, re, sys
scan_dir, guard_path = sys.argv[1], sys.argv[2]
seams = sorted(set(re.findall(r'os\.environ\.get\("(OVATION_GUARD_[A-Z_]+)"',
                              open(guard_path, encoding="utf-8").read())))
if not seams:
    # A scanner that found no seams would pass every run it reads, which is the
    # silence this check exists to end, so it says so instead (L98).
    print("NO SEAMS FOUND in " + guard_path)
    sys.exit(0)
name = "check-" + "identity-leaks.sh"
direct = ["./scripts/" + name, "bash scripts/" + name, "python3 scripts/" + name]
found = []
for path in sorted(glob.glob(os.path.join(scan_dir, "test-*.sh"))):
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    target_is_guard = any(re.match(r'^\s*TARGET="scripts/' + re.escape(name) + '"', l)
                          for l in lines)
    for i, line in enumerate(lines):
        if line.lstrip().startswith("#"):
            continue
        runs = any(d in line for d in direct) or bool(
            target_is_guard and re.search(r'\./\$TARGET\b', line))
        if not runs:
            continue
        # The whole command, continuation lines and all, because that is where a
        # run sets its environment.
        start = i
        while start > 0 and lines[start - 1].rstrip().endswith("\\"):
            start -= 1
        command = " ".join(l.strip() for l in lines[start:i + 1])
        missing = [s for s in seams if s + "=" not in command]
        if missing:
            found.append("%s:%d %s" % (os.path.basename(path), i + 1,
                         ",".join(s[len("OVATION_GUARD_"):] for s in missing)))
print(" ".join(found))
PYSEAMS
}

# SEEN TO FAIL, on a staged suite, before it is trusted on the real tree (L1).
SEAMSCAN="$WORK/seamscan"; mkdir -p "$SEAMSCAN"
GUARD_CALL="./scripts/check-""identity-leaks.sh"
printf 'OUT="$(OVATION_GUARD_EXPORT=x \\\n    OVATION_GUARD_SCAN_ROOT=y \\\n    %s 2>&1)"\n' \
    "$GUARD_CALL" > "$SEAMSCAN/test-offender.sh"
printf 'OUT="$(OVATION_GUARD_EXPORT=x \\\n    OVATION_GUARD_CUSTODY_DIR=x \\\n    OVATION_GUARD_STORE=x \\\n    OVATION_GUARD_QUEUE_DIR=x \\\n    OVATION_GUARD_FINGERPRINTS=x \\\n    OVATION_GUARD_SCAN_ROOT=y \\\n    %s 2>&1)"\n' \
    "$GUARD_CALL" > "$SEAMSCAN/test-clean.sh"
SEAMS_SCANNED="$(unfixtured_guard_runs "$SEAMSCAN")"
check "a guard run that leaves a source unset is reported" \
    "$(printf '%s' "$SEAMS_SCANNED" | grep -c 'test-offender.sh')" "1"
check "and a guard run that sets every source is not" \
    "$(printf '%s' "$SEAMS_SCANNED" | grep -c 'test-clean.sh')" "0"
check "every suite that runs the identity guard points every source at a fixture" \
    "$(unfixtured_guard_runs "scripts")" ""

harness_end
