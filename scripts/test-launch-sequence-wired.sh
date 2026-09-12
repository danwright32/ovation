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

# 5, ovation#162. THE EXPORT CONTROL IS WIRED, or it is a dead menu item. The
# command runs an export over the store this sequence opened, and the only way it
# can have that store is `onOpened`: opening a second container would be a second
# writer over one file, which is what case 4 above exists to prevent. Nothing
# else can assert this, for the same reason nothing else can assert the sequence
# is run at all, because @main is the one file no test in the suite compiles.
cat > "${WORK}/never-takes-the-store.swift" <<'SWIFT'
@main
struct OvationApp: App {
    init() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        let verdict = SecondInstance.check(executablePath: "x", runningPIDs: { _ in [] })
        if verdict.mayRun, let storeURL = StoreLocation.liveStoreURL() {
            StoreLaunchSequence(storeURL: storeURL, problems: store).run(now: Date())
        }
    }
}
SWIFT
check "an entry point that never takes the opened store is refused" 5 \
    "$(run_on "${WORK}/never-takes-the-store.swift")"

# And one that does, so the rule above is not bought by refusing everything (L1).
#
# RETARGETED IN ovation#246, NOT WEAKENED. This fixture ran the sequence inside
# init, which the guard now refuses: the launch runs from a task once the window
# exists. The claim it makes, that taking the opened store passes, is unchanged,
# so the fixture moves to the shape the entry point actually has (L430).
cat > "${WORK}/takes-the-store.swift" <<'SWIFT'
@main
struct OvationApp: App {
    @State private var hasLaunched = false
    init() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        let verdict = SecondInstance.check(executablePath: "x", runningPIDs: { _ in [] })
        _ = verdict.mayRun
    }
    var body: some Scene {
        Window("x", id: "x") {
            RootView()
                .task {
                    guard !hasLaunched else { return }
                    hasLaunched = true
                    if let storeURL = StoreLocation.liveStoreURL() {
                        var sequence = StoreLaunchSequence(storeURL: storeURL, problems: store)
                        sequence.onOpened = { opened.container = $0 }
                        sequence.takeBackup = { now in
                            _ = await BlockingWork.run { true }
                            return .taken(storeURL)
                        }
                        await sequence.run(now: Date())
                    }
                }
        }
    }
}
SWIFT
check "and one that takes it passes" 0 \
    "$(run_on "${WORK}/takes-the-store.swift")"

# ---------------------------------------------------------------------------
# IT RUNS FROM A TASK, AND ONCE (ovation#246). The sequence used to run inside
# init, before any window existed, so a slow backup and an app that would not
# start looked identical and there was nowhere to say which. Both halves live in
# the one file no test can compile, which is why they are checked here.
# ---------------------------------------------------------------------------
cat > "${WORK}/runs-in-init.swift" <<'SWIFT'
@main
struct OvationApp: App {
    init() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        let verdict = SecondInstance.check(executablePath: "x", runningPIDs: { _ in [] })
        if verdict.mayRun, let storeURL = StoreLocation.liveStoreURL() {
            var sequence = StoreLaunchSequence(storeURL: storeURL, problems: store)
            sequence.onOpened = { opened.container = $0 }
            sequence.run(now: Date())
        }
    }
}
SWIFT
check "an entry point that runs the launch in init, with no window, is refused" 6 \
    "$(run_on "${WORK}/runs-in-init.swift")"

cat > "${WORK}/task-with-no-guard.swift" <<'SWIFT'
@main
struct OvationApp: App {
    init() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        let verdict = SecondInstance.check(executablePath: "x", runningPIDs: { _ in [] })
        _ = verdict.mayRun
    }
    var body: some Scene {
        Window("x", id: "x") {
            RootView()
                .task {
                    if let storeURL = StoreLocation.liveStoreURL() {
                        var sequence = StoreLaunchSequence(storeURL: storeURL, problems: store)
                        sequence.onOpened = { opened.container = $0 }
                        await sequence.run(now: Date())
                    }
                }
        }
    }
}
SWIFT
check "a launch that can run twice is refused, because that is two writers" 6 \
    "$(run_on "${WORK}/task-with-no-guard.swift")"

cat > "${WORK}/task-guarded.swift" <<'SWIFT'
@main
struct OvationApp: App {
    @State private var hasLaunched = false
    init() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        let verdict = SecondInstance.check(executablePath: "x", runningPIDs: { _ in [] })
        _ = verdict.mayRun
    }
    var body: some Scene {
        Window("x", id: "x") {
            RootView()
                .task {
                    guard !hasLaunched else { return }
                    hasLaunched = true
                    if let storeURL = StoreLocation.liveStoreURL() {
                        var sequence = StoreLaunchSequence(storeURL: storeURL, problems: store)
                        sequence.onOpened = { opened.container = $0 }
                        sequence.takeBackup = { now in
                            _ = await BlockingWork.run { true }
                            return .taken(storeURL)
                        }
                        await sequence.run(now: Date())
                    }
                }
        }
    }
}
SWIFT
# And the control, so the two refusals above are not bought by refusing
# everything (L159).
cat > "${WORK}/heavy-on-the-main-actor.swift" <<'SWIFT'
@main
struct OvationApp: App {
    @State private var hasLaunched = false
    init() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        let verdict = SecondInstance.check(executablePath: "x", runningPIDs: { _ in [] })
        _ = verdict.mayRun
    }
    var body: some Scene {
        Window("x", id: "x") {
            RootView()
                .task {
                    guard !hasLaunched else { return }
                    hasLaunched = true
                    if let storeURL = StoreLocation.liveStoreURL() {
                        var sequence = StoreLaunchSequence(storeURL: storeURL, problems: store)
                        sequence.onOpened = { opened.container = $0 }
                        await sequence.run(now: Date())
                    }
                }
        }
    }
}
SWIFT
check "a launch whose heavy work stays on the main actor is refused" 6 \
    "$(run_on "${WORK}/heavy-on-the-main-actor.swift")"

check "a guarded launch that sends the heavy work away passes" 0 \
    "$(run_on "${WORK}/task-guarded.swift")"

echo "launch sequence wiring tests: ${PASSED} passed, ${FAILED} failed"
[[ "${FAILED}" -eq 0 ]]
