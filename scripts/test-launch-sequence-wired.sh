#!/usr/bin/env bash
# Tests for check-launch-sequence-wired.sh (ovation#88).
#
# EVERY OUTCOME ITS OWN CONTRACT ENUMERATES IS PRODUCED HERE, not merely passed
# over (L151). The guard declares four exit codes and there is a case for each,
# including the two that are easy to leave untested: the entry point that is not
# there, and the one that builds the sequence and never runs it.
#
# A guard is only real once it has been seen to fail (L1), so the first thing
# each case does is construct the defect.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="${REPO_ROOT}/scripts/check-launch-sequence-wired.sh"

PASSED=0
FAILED=0
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
    echo "  FAIL: ${name}: expected exit ${expected}, got ${actual}"
  fi
}

run_on() {
  OVATION_ENTRY_POINT="$1" python3 "${GUARD}" >/dev/null 2>&1
  echo $?
}

# 0: the real entry point, which is the positive control. Without it every case
# below could pass while the guard was broken in a way that refuses everything.
check "the real entry point passes" 0 "$(run_on "${REPO_ROOT}/Ovation/App/OvationApp.swift")"

# 1: an entry point that never builds the sequence. This is the state the app
# was actually in, so the fixture is the defect rather than an invention.
cat > "${WORK}/unwired.swift" <<'SWIFT'
@main
struct OvationApp: App {
    init() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        store.load()
    }
}
SWIFT
check "an entry point that never builds it is refused" 1 "$(run_on "${WORK}/unwired.swift")"

# 3: built and never run. The parts present and the protection absent, which is
# the shape that reads most like working code.
cat > "${WORK}/built-not-run.swift" <<'SWIFT'
@main
struct OvationApp: App {
    init() {
        let sequence = StoreLaunchSequence(storeURL: url, problems: store)
        _ = sequence
    }
}
SWIFT
check "built and never run is its own refusal" 3 "$(run_on "${WORK}/built-not-run.swift")"

# 2: no file at all. Nothing scanned is not a pass (L98).
check "a missing entry point is refused, not passed" 2 "$(run_on "${WORK}/absent.swift")"

# 2: a file that is no longer the entry point. The guard has lost its subject
# and says so rather than reporting the tree clean.
cat > "${WORK}/no-main.swift" <<'SWIFT'
struct SomeOtherType {
    func run() {}
}
SWIFT
check "a file with no @main is refused as the wrong subject" 2 "$(run_on "${WORK}/no-main.swift")"

# A MENTION IS NOT A CALL. A file that only talks about the sequence in a
# comment must not satisfy the guard, or the first person to remove the wiring
# and explain why in a comment passes it (L103).
cat > "${WORK}/comment-only.swift" <<'SWIFT'
@main
struct OvationApp: App {
    init() {
        // We used to build a StoreLaunchSequence( here and call .run(now: Date())
        // but it was removed. See ovation#88.
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
    }
}
SWIFT
check "a sequence mentioned only in a comment does not satisfy it" 1 "$(run_on "${WORK}/comment-only.swift")"

# 4: ovation#84. An entry point that runs the sequence perfectly and never asks
# whether another copy of Ovation is already running. Two copies over one store
# are two writers of the same invoices, and every serialized writer Ovation has
# serializes within ONE process, so nothing inside them can see the other.
cat > "${WORK}/no-second-copy-check.swift" <<'SWIFT'
@main
struct OvationApp: App {
    init() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        if let storeURL = StoreLocation.liveStoreURL() {
            StoreLaunchSequence(storeURL: storeURL, problems: store).run(now: Date())
        }
    }
}
SWIFT
check "an entry point that never asks about a second copy is refused" 4 \
    "$(run_on "${WORK}/no-second-copy-check.swift")"

# 4, the other half and the more likely one: it ASKS and runs anyway. Standing
# aside after checkpointing, backing up and opening is standing aside after doing
# the dangerous part.
cat > "${WORK}/asks-and-ignores.swift" <<'SWIFT'
@main
struct OvationApp: App {
    init() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        let verdict = SecondInstance.check(executablePath: "x", runningPIDs: { _ in [] })
        _ = verdict
        if let storeURL = StoreLocation.liveStoreURL() {
            StoreLaunchSequence(storeURL: storeURL, problems: store).run(now: Date())
        }
    }
}
SWIFT
check "an entry point that asks and never reads the answer is refused too" 4 \
    "$(run_on "${WORK}/asks-and-ignores.swift")"

echo "launch sequence wiring tests: ${PASSED} passed, ${FAILED} failed"
[[ "${FAILED}" -eq 0 ]]
