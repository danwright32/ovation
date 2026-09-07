#!/bin/bash
# The suite for scripts/check-schema-registered.sh.
#
# ovation#60. Every case runs against a THROWAWAY scan root through the script's
# own seams, and the real sources are scanned once, deliberately, because a seam
# that hides the real path from every test leaves the real path untested (L246).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "schema registration tests" 13

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

# The real sources, once, so the seams are not the only thing ever exercised.
check "the real tree passes" "$(OVATION_SCHEMA_SCAN_ROOT= OVATION_SCHEMA_FILE= "./$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "0"
check "and it found every model, not a handful" \
    "$(./$TARGET | grep -c '10 model type(s)')" "1"

harness_end
