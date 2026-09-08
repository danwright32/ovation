#!/bin/bash
# The suite for scripts/check-migration-stages.sh.
#
# ovation#119. Every case runs against a THROWAWAY schema file through the
# script's own seam, and the real one is checked once, deliberately, because a
# seam that hides the real path from every test leaves the real path untested
# (L246).
#
# THE CASE THE GUARD EXISTS FOR IS PLANTED HERE, more than once: a version added
# with no stage, and a stage naming a pair that is not a step. A source level
# scanner is easy to get subtly wrong in a way that matches nothing, so it is
# seen to fail before it is trusted (L1).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "migration stage tests" 18

TARGET="scripts/check-migration-stages.sh"
require_target "$TARGET"
harness_temp_dir WORK

run_on() { OVATION_SCHEMA_FILE="$1" "./$TARGET" 2>&1; }
status_on() {
    OVATION_SCHEMA_FILE="$1" "./$TARGET" >/dev/null 2>&1
    printf '%s' "$?"
}

# Today's shape: one version, no stages, which is correct and must not be
# reported as a chain that was verified.
ONE="$WORK/one.swift"
cat > "$ONE" <<'SWIFT'
enum OvationMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [OvationSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
SWIFT
check "one version with no stages passes" "$(status_on "$ONE")" "0"
check "and it says there was no chain to check, rather than implying one was verified" \
    "$(run_on "$ONE" | grep -c 'no chain to check')" "1"

# Two versions, correctly carried.
TWO="$WORK/two.swift"
cat > "$TWO" <<'SWIFT'
enum OvationMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OvationSchemaV1.self, OvationSchemaV2.self]
    }
    static var stages: [MigrationStage] {
        [MigrationStage.lightweight(fromVersion: OvationSchemaV1.self,
                                    toVersion: OvationSchemaV2.self)]
    }
}
SWIFT
check "two versions with the step between them covered passes" "$(status_on "$TWO")" "0"
check "and it says WHICH chain it verified" \
    "$(run_on "$TWO" | grep -c 'OvationSchemaV1 to OvationSchemaV2')" "1"

# THE CASE THE GUARD EXISTS FOR. A second version added, stages left empty.
UNCOVERED="$WORK/uncovered.swift"
cat > "$UNCOVERED" <<'SWIFT'
enum OvationMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OvationSchemaV1.self, OvationSchemaV2.self]
    }
    static var stages: [MigrationStage] { [] }
}
SWIFT
check "a version added with no stage is refused" "$(status_on "$UNCOVERED")" "1"
check "and the refusal names the step nothing carries" \
    "$(run_on "$UNCOVERED" | grep -c 'OvationSchemaV1 to OvationSchemaV2')" "1"
check "and says what the symptom would be, which is not a crash" \
    "$(run_on "$UNCOVERED" | grep -c 'opens a store that looks fine')" "1"

# Three versions, two stages, both steps covered.
THREE="$WORK/three.swift"
cat > "$THREE" <<'SWIFT'
enum OvationMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OvationSchemaV1.self, OvationSchemaV2.self, OvationSchemaV3.self]
    }
    static var stages: [MigrationStage] {
        [
            MigrationStage.lightweight(fromVersion: OvationSchemaV1.self,
                                       toVersion: OvationSchemaV2.self),
            MigrationStage.custom(fromVersion: OvationSchemaV2.self,
                                  toVersion: OvationSchemaV3.self,
                                  willMigrate: nil, didMigrate: nil),
        ]
    }
}
SWIFT
check "three versions with both steps covered passes" "$(status_on "$THREE")" "0"

# Three versions, only the first step carried. The count alone catches this, and
# it is a different fixture from the two version one so the count and the pairing
# are not proved by one case.
GAP="$WORK/gap.swift"
cat > "$GAP" <<'SWIFT'
enum OvationMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OvationSchemaV1.self, OvationSchemaV2.self, OvationSchemaV3.self]
    }
    static var stages: [MigrationStage] {
        [MigrationStage.lightweight(fromVersion: OvationSchemaV1.self,
                                    toVersion: OvationSchemaV2.self)]
    }
}
SWIFT
check "a chain missing its last step is refused" "$(status_on "$GAP")" "1"
check "and it names the step that is missing, not the one that is there" \
    "$(run_on "$GAP" | grep -c 'OvationSchemaV2 to OvationSchemaV3')" "1"

# A stage that is present but does not name a step in the chain. Same count, so
# counting alone would pass it: this is what makes the pairing check load bearing.
SKIPPING="$WORK/skipping.swift"
cat > "$SKIPPING" <<'SWIFT'
enum OvationMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OvationSchemaV1.self, OvationSchemaV2.self, OvationSchemaV3.self]
    }
    static var stages: [MigrationStage] {
        [
            MigrationStage.lightweight(fromVersion: OvationSchemaV1.self,
                                       toVersion: OvationSchemaV3.self),
            MigrationStage.lightweight(fromVersion: OvationSchemaV2.self,
                                       toVersion: OvationSchemaV3.self),
        ]
    }
}
SWIFT
check "a stage that jumps a version is its own outcome" "$(status_on "$SKIPPING")" "3"
check "and it is NOT reported as a missing stage" \
    "$(run_on "$SKIPPING" | grep -c 'UNCOVERED')" "0"

# A stage written backwards. The right number of stages naming the right two
# versions, and it carries nothing.
BACKWARDS="$WORK/backwards.swift"
cat > "$BACKWARDS" <<'SWIFT'
enum OvationMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OvationSchemaV1.self, OvationSchemaV2.self]
    }
    static var stages: [MigrationStage] {
        [MigrationStage.lightweight(fromVersion: OvationSchemaV2.self,
                                    toVersion: OvationSchemaV1.self)]
    }
}
SWIFT
check "a stage written in the wrong direction is refused" "$(status_on "$BACKWARDS")" "3"

# Nothing to scan is not a pass.
check "a missing schema file cannot measure" "$(status_on "$WORK/nowhere.swift")" "2"

NOPLAN="$WORK/noplan.swift"
cat > "$NOPLAN" <<'SWIFT'
enum OvationSchema {
    static let models: [any PersistentModel.Type] = [Invoice.self]
}
SWIFT
check "a file with no migration plan in it cannot measure" "$(status_on "$NOPLAN")" "2"

EMPTY="$WORK/empty.swift"
cat > "$EMPTY" <<'SWIFT'
enum OvationMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [] }
    static var stages: [MigrationStage] { [] }
}
SWIFT
check "a plan naming no versions at all cannot measure" "$(status_on "$EMPTY")" "2"

# The real file, so the seam is not the only thing ever exercised.
check "the real schema file passes" "$(OVATION_SCHEMA_FILE= "./$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "0"
check "and it reports the one version there actually is" \
    "$(./$TARGET | grep -c '1 schema version')" "1"

harness_end
