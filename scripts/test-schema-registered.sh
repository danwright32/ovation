#!/bin/bash
# The suite for scripts/check-schema-registered.sh.
#
# ovation#60. Every case runs against a THROWAWAY scan root through the script's
# own seams, and the real sources are scanned once, deliberately, because a seam
# that hides the real path from every test leaves the real path untested (L246).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "schema registration tests" 29

TARGET="scripts/check-schema-registered.sh"
require_target "$TARGET"
harness_temp_dir WORK

run_on() {
    OVATION_SCHEMA_SCAN_ROOT="$1" OVATION_SCHEMA_FILE="$2" "./$TARGET" 2>&1
}
status_on() {
    OVATION_SCHEMA_SCAN_ROOT="$1" OVATION_SCHEMA_FILE="$2" "./$TARGET" >/dev/null 2>&1
    printf '%s' "$?"
}

# A tree with one model, and a schema that knows about it.
GOOD="$WORK/good"
mkdir -p "$GOOD/Persistence"
cat > "$GOOD/Invoice.swift" <<'SWIFT'
@Model
final class Invoice {
    var id: UUID = UUID()
}
SWIFT
cat > "$GOOD/Persistence/OvationSchema.swift" <<'SWIFT'
enum OvationSchema {
    static let models: [any PersistentModel.Type] = [Invoice.self]
}
SWIFT
check "a registered model passes" "$(status_on "$GOOD" "$GOOD/Persistence/OvationSchema.swift")" "0"

# THE CASE THE GUARD EXISTS FOR. A second model, absent from the schema.
BAD="$WORK/bad"
cp -R "$GOOD" "$BAD"
cat > "$BAD/Payment.swift" <<'SWIFT'
@Model
final class Payment {
    var id: UUID = UUID()
}
SWIFT
check "an unregistered model is refused" \
    "$(status_on "$BAD" "$BAD/Persistence/OvationSchema.swift")" "1"
check "and the refusal NAMES it" \
    "$(run_on "$BAD" "$BAD/Persistence/OvationSchema.swift" | grep -c 'Payment')" "1"
check "and says what the symptom would have been" \
    "$(run_on "$BAD" "$BAD/Persistence/OvationSchema.swift" | grep -c 'returns nothing')" "1"

# An attribute or a comment between the macro and the class does not hide it.
SPACED="$WORK/spaced"
cp -R "$GOOD" "$SPACED"
cat > "$SPACED/Expense.swift" <<'SWIFT'
/// What Ovation spent.
@Model
// a comment nobody expected
final class Expense {
    var id: UUID = UUID()
}
SWIFT
check "a model with a comment under the macro is still found" \
    "$(status_on "$SPACED" "$SPACED/Persistence/OvationSchema.swift")" "1"

# The other direction: a schema naming something the sources no longer declare.
STALE="$WORK/stale"
cp -R "$GOOD" "$STALE"
cat > "$STALE/Persistence/OvationSchema.swift" <<'SWIFT'
enum OvationSchema {
    static let models: [any PersistentModel.Type] = [Invoice.self, Booking.self]
}
SWIFT
check "a schema naming a type that is gone is its own outcome" \
    "$(status_on "$STALE" "$STALE/Persistence/OvationSchema.swift")" "3"
check "and it is NOT reported as an unregistered model" \
    "$(run_on "$STALE" "$STALE/Persistence/OvationSchema.swift" | grep -c 'UNREGISTERED')" "0"

# Nothing to scan is not a pass.
EMPTY="$WORK/empty"
mkdir -p "$EMPTY/Persistence"
cat > "$EMPTY/Persistence/OvationSchema.swift" <<'SWIFT'
enum OvationSchema {
    static let models: [any PersistentModel.Type] = []
}
SWIFT
check "a tree with no models at all cannot measure" \
    "$(status_on "$EMPTY" "$EMPTY/Persistence/OvationSchema.swift")" "2"
check "and says so rather than reporting a clean tree" \
    "$(run_on "$EMPTY" "$EMPTY/Persistence/OvationSchema.swift" | grep -c 'CANNOT SCAN')" "1"
check "a missing scan root cannot measure" \
    "$(status_on "$WORK/nowhere" "$GOOD/Persistence/OvationSchema.swift")" "2"
check "a missing schema file cannot measure" \
    "$(status_on "$GOOD" "$WORK/nowhere.swift")" "2"

# A NON MODEL `.self` IN THE SCHEMA FILE IS NOT A REGISTRATION. ovation#105 put
# OvationSchemaV1.self and OvationMigrationPlan.self in this file, and reading
# every `X.self` in it treated both as registered model types with no @Model
# declaration anywhere, so the guard reported the schema as stale. The subject is
# the models ARRAY, not the file (L100: a match found by loose spelling picks up
# what was never a subject).
VERSIONED="$WORK/versioned"
mkdir -p "$VERSIONED/Persistence" "$VERSIONED/Domain"
cat > "$VERSIONED/Domain/Invoice.swift" <<'SWIFT'
@Model
final class Invoice { var id: Int = 0 }
SWIFT
cat > "$VERSIONED/Persistence/OvationSchema.swift" <<'SWIFT'
enum OvationSchema {
    static let models: [any PersistentModel.Type] = [
        Invoice.self,
    ]
    static var schema: Schema { Schema(models, version: OvationSchemaV1.versionIdentifier) }
    static var versionedSchema: any VersionedSchema.Type { OvationSchemaV1.self }
    static func container(at url: URL) throws -> ModelContainer {
        try ModelContainer(for: schema, migrationPlan: OvationMigrationPlan.self,
                           configurations: ModelConfiguration(schema: schema, url: url))
    }
}

enum OvationSchemaV1: VersionedSchema {
    static var models: [any PersistentModel.Type] { [Invoice.self] }
}

enum OvationMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [OvationSchemaV1.self] }
}
SWIFT
check "a versioned schema beside the models is not read as a stale registration" \
    "$(status_on "$VERSIONED" "$VERSIONED/Persistence/OvationSchema.swift")" "0"
check "and an actually unregistered model is still caught in the same file" \
    "$(printf '@Model\nfinal class Payment { var id: Int = 0 }\n' > "$VERSIONED/Domain/Payment.swift"; \
       status_on "$VERSIONED" "$VERSIONED/Persistence/OvationSchema.swift")" "1"

# The real sources, once, so the seams are not the only thing ever exercised.
check "the real tree passes" "$(OVATION_SCHEMA_SCAN_ROOT= OVATION_SCHEMA_FILE= "./$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "0"
check "and it found every model, not a handful" \
    "$(./$TARGET | grep -c '10 model type(s)')" "1"

# ---------------------------------------------------------------------------
# A VERSION MUST DESCRIBE ITS OWN SHAPE (ovation#134).
#
# `OvationSchemaV1.models` read `OvationSchema.models`, which is the list of what
# the app holds RIGHT NOW. At one version those are the same sentence. The day a
# version 2 exists, version 1 silently describes version 2's models, both
# versions are the same shape, and any migration stage between them has nothing
# to carry.
#
# Nothing could see it. check-migration-stages.sh compares the LIST of versions
# and would pass, because the stage is present and correctly paired; it cannot
# compare what each version claims to hold, since both claims come from one
# expression. That is L70 exactly: a check whose two sides come from one lookup
# proves the lookup self consistent and nothing else.
#
# So the version holds its own list, and this is what keeps it honest. The list
# it is held to is the NEWEST version's, because that is the one that must match
# the app; an older version's shorter list is the whole point of having versions.
mk_versioned() {
    # $1 dir, $2 the app's model list, $3 the version enums
    mkdir -p "$1/Persistence"
    printf '@Model\nfinal class Invoice {\n    var id: UUID = UUID()\n}\n' > "$1/Invoice.swift"
    cat > "$1/Persistence/OvationSchema.swift" <<SCHEMA
enum OvationSchema {
    static let models: [any PersistentModel.Type] = [$2]
}

$3
SCHEMA
}

FROZEN="$WORK/frozen"
mk_versioned "$FROZEN" "Invoice.self" 'enum OvationSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Invoice.self] }
}'
check "a version holding its own list passes" \
    "$(status_on "$FROZEN" "$FROZEN/Persistence/OvationSchema.swift")" "0"

# THE DEFECT ITSELF.
DELEGATING="$WORK/delegating"
mk_versioned "$DELEGATING" "Invoice.self" 'enum OvationSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { OvationSchema.models }
}'
check "a version that delegates its list is refused" \
    "$(status_on "$DELEGATING" "$DELEGATING/Persistence/OvationSchema.swift")" "4"
check "and the refusal names the version that is not describing itself" \
    "$(run_on "$DELEGATING" "$DELEGATING/Persistence/OvationSchema.swift" | grep -c 'OvationSchemaV1')" "1"
check "and it says DELEGATED rather than that it could not read the list" \
    "$(run_on "$DELEGATING" "$DELEGATING/Persistence/OvationSchema.swift" | grep -c 'DELEGATED')" "1"

# A VERSION THAT STATES NO LIST AT ALL is its own outcome. Reached for real while
# this was written: the list was moved to the app's own form, the search missed,
# and every version check passed in silence (L98).
SILENT="$WORK/silent"
mk_versioned "$SILENT" "Invoice.self" 'enum OvationSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
}'
check "a version stating no model list is refused, not skipped" \
    "$(status_on "$SILENT" "$SILENT/Persistence/OvationSchema.swift")" "6"
check "and it says nothing about that version was checked" \
    "$(run_on "$SILENT" "$SILENT/Persistence/OvationSchema.swift" | grep -c 'UNREADABLE')" "1"

# THE OTHER FORM READS TOO. A version writing its list as `= [ ... ]` is unusual
# but legal, and a guard that only understood one form would skip it in silence.
EQUALS="$WORK/equals"
mk_versioned "$EQUALS" "Invoice.self" 'enum OvationSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] = [Invoice.self]
}'
check "a version writing its list the other way is read, not skipped" \
    "$(status_on "$EQUALS" "$EQUALS/Persistence/OvationSchema.swift")" "0"

# A VERSION SHORT OF THE APP'S MODELS, which is a different fault from the
# app's own list being short of the sources, and needs a different answer.
SHORT="$WORK/short"
mk_versioned "$SHORT" "Invoice.self, Payment.self" 'enum OvationSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Invoice.self] }
}'
printf '@Model\nfinal class Payment {\n    var id: UUID = UUID()\n}\n' > "$SHORT/Payment.swift"
check "a newest version short of the app's models is refused" \
    "$(status_on "$SHORT" "$SHORT/Persistence/OvationSchema.swift")" "5"
check "and it names the type the version does not know about" \
    "$(run_on "$SHORT" "$SHORT/Persistence/OvationSchema.swift" | grep -c 'Payment')" "1"
# BOTH REMEDIES, because nothing in the sources can tell which situation this is
# and they are opposite actions (L11).
check "and it names both answers, since the code cannot tell which applies" \
    "$(run_on "$SHORT" "$SHORT/Persistence/OvationSchema.swift" | grep -ciE 'never been written|has been written')" "2"

# TWO VERSIONS: the newest is held to the app, and the older is left alone. This
# is the case the whole issue is about, and the one that cannot exist today.
TWO="$WORK/two"
mk_versioned "$TWO" "Invoice.self, Payment.self" 'enum OvationSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Invoice.self] }
}

enum OvationSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [Invoice.self, Payment.self] }
}'
printf '@Model\nfinal class Payment {\n    var id: UUID = UUID()\n}\n' > "$TWO/Payment.swift"
check "with two versions the newest is the one held to the app" \
    "$(status_on "$TWO" "$TWO/Persistence/OvationSchema.swift")" "0"
check "and the older version keeping a shorter list is not a fault" \
    "$(run_on "$TWO" "$TWO/Persistence/OvationSchema.swift" | grep -c 'OvationSchemaV1')" "0"

# A VERSIONED SCHEMA THIS CANNOT RECOGNISE IS NOT ONE IT MAY IGNORE.
#
# Versions are found by their name, so one named any other way would be invisible
# and every check above would pass by never looking at it. That is the same
# silent skip that was already reached twice while writing this guard, so it gets
# the same answer: seen and refused rather than not seen (L98, L96).
STRANGE="$WORK/strange"
mk_versioned "$STRANGE" "Invoice.self" 'enum OvationSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Invoice.self] }
}

enum LegacyShape: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(0, 9, 0) }
    static var models: [any PersistentModel.Type] { [Invoice.self] }
}'
check "a versioned schema this cannot recognise is refused, not ignored" \
    "$(status_on "$STRANGE" "$STRANGE/Persistence/OvationSchema.swift")" "7"
check "and it names the one it could not place" \
    "$(run_on "$STRANGE" "$STRANGE/Persistence/OvationSchema.swift" | grep -c 'LegacyShape')" "1"

harness_end
