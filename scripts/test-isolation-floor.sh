#!/bin/bash
# The suite for scripts/check-isolation-floor.sh.
#
# ovation#58, plan 1.9. Every case runs against a THROWAWAY scan root through the
# script's own seams. The real sources are scanned once, deliberately, because a
# seam that hides the real path from every test leaves the real path untested
# (L246).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "isolation floor tests" 15

TARGET="scripts/check-isolation-floor.sh"
require_target "$TARGET"
harness_temp_dir WORK

run_on() {
    OVATION_FLOOR_SCAN_ROOT="$1" OVATION_FLOOR_REGISTER="$2" "./$TARGET" 2>&1
}
status_on() {
    OVATION_FLOOR_SCAN_ROOT="$1" OVATION_FLOOR_REGISTER="$2" "./$TARGET" >/dev/null 2>&1
    printf '%s' "$?"
}

# A tree with one resolver, and a register that knows about it.
GOOD="$WORK/good"
mkdir -p "$GOOD/App"
cat > "$GOOD/Store.swift" <<'SWIFT'
enum Store {
    static func liveStoreURL() -> URL? { nil }
}
SWIFT
cat > "$GOOD/App/LiveDataFloor.swift" <<'SWIFT'
enum LiveDataFloor {
    static let entries = [
        Entry(name: "liveStoreURL", reaches: "the store", resolve: nil, issue: nil),
    ]
}
SWIFT
check "a registered resolver passes" "$(status_on "$GOOD" "$GOOD/App/LiveDataFloor.swift")" "0"
check "and it says how many it found" \
    "$(run_on "$GOOD" "$GOOD/App/LiveDataFloor.swift" | grep -c '1 live data resolver')" "1"

# The same tree with the register emptied.
BARE="$WORK/bare"
cp -R "$GOOD" "$BARE"
cat > "$BARE/App/LiveDataFloor.swift" <<'SWIFT'
enum LiveDataFloor {
    static let entries: [Entry] = []
}
SWIFT
check "an unregistered resolver is refused" \
    "$(status_on "$BARE" "$BARE/App/LiveDataFloor.swift")" "1"
check "and the refusal names the file and the line" \
    "$(run_on "$BARE" "$BARE/App/LiveDataFloor.swift" | grep -c 'Store.swift:2')" "1"
check "and it names the resolver" \
    "$(run_on "$BARE" "$BARE/App/LiveDataFloor.swift" | grep -c 'liveStoreURL')" "1"

# Every shape a resolver can be declared in, because a check that only knows
# `func` is blind to the same thing written as a property.
for KEYWORD in func var let; do
    SHAPE="$WORK/shape-$KEYWORD"
    mkdir -p "$SHAPE/App"
    printf 'enum Store {\n    static %s liveThing = 1\n}\n' "$KEYWORD" > "$SHAPE/Store.swift"
    printf 'enum LiveDataFloor { static let entries: [Entry] = [] }\n' \
        > "$SHAPE/App/LiveDataFloor.swift"
    check "a resolver declared as a static $KEYWORD is seen" \
        "$(status_on "$SHAPE" "$SHAPE/App/LiveDataFloor.swift")" "1"
done

# Prose about a resolver is not a resolver (L245): this script and the register
# both have to NAME them in order to check them.
COMMENTED="$WORK/commented"
mkdir -p "$COMMENTED/App"
printf 'enum Store {\n    // static func liveNothing() -> URL? { nil }\n}\nenum Other {\n    static func liveReal() -> URL? { nil }\n}\n' \
    > "$COMMENTED/Store.swift"
printf 'enum LiveDataFloor { static let entries = [Entry(name: "liveReal")] }\n' \
    > "$COMMENTED/App/LiveDataFloor.swift"
check "a resolver named only in a comment is not counted" \
    "$(status_on "$COMMENTED" "$COMMENTED/App/LiveDataFloor.swift")" "0"

# Two resolvers wearing one name would let a single registration answer for both.
AMBIGUOUS="$WORK/ambiguous"
mkdir -p "$AMBIGUOUS/App"
printf 'enum A {\n    static func liveURL() -> URL? { nil }\n}\n' > "$AMBIGUOUS/A.swift"
printf 'enum B {\n    static func liveURL() -> URL? { nil }\n}\n' > "$AMBIGUOUS/B.swift"
printf 'enum LiveDataFloor { static let entries = [Entry(name: "liveURL")] }\n' \
    > "$AMBIGUOUS/App/LiveDataFloor.swift"
check "two resolvers sharing a name are refused with their own code" \
    "$(status_on "$AMBIGUOUS" "$AMBIGUOUS/App/LiveDataFloor.swift")" "3"
check "and both places are named" \
    "$(run_on "$AMBIGUOUS" "$AMBIGUOUS/App/LiveDataFloor.swift" | grep -c 'A.swift:2, B.swift:2')" "1"

# NOTHING SCANNED IS NOT A PASS (L98).
EMPTY="$WORK/empty"
mkdir -p "$EMPTY/App"
printf 'enum LiveDataFloor { static let entries: [Entry] = [] }\n' > "$EMPTY/App/LiveDataFloor.swift"
check "a tree with no resolvers at all refuses rather than passing" \
    "$(status_on "$EMPTY" "$EMPTY/App/LiveDataFloor.swift")" "2"
check "a register that is not there refuses" \
    "$(status_on "$GOOD" "$WORK/no-such-register.swift")" "2"
check "a scan root that is not there refuses" \
    "$(status_on "$WORK/no-such-root" "$GOOD/App/LiveDataFloor.swift")" "2"

# The real sources, once (L246).
check "Ovation's own resolvers are all registered, scanned at the real default root" \
    "$("./$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "0"

harness_end
