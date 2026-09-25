#!/bin/bash
# The suite for scripts/regenerate-xcode-project.sh.
#
# ovation#202. `Ovation.xcodeproj` is generated from project.yml and gitignored,
# and `lib/ensure-xcode-project.sh` deliberately never regenerates one that
# exists, because rewriting it on every build rewrites the file underneath an
# open Xcode. But ADDING A SOURCE FILE REQUIRES a regeneration, so the moment a
# new Swift file appears somebody deletes the project and remakes it, and nothing
# checked whether a build was reading it at that moment.
#
# IT HAPPENED. On 2026-09-10 `rm -rf Ovation.xcodeproj && xcodegen generate` ran
# while `run-tests.sh` was in its Xcode phase. It survived, and survival is the
# evidence of luck rather than of safety.
#
# IT REFUSES RATHER THAN WAITS, and that is the decision rather than an
# implementation detail: regenerating is a deliberate act somebody is doing at a
# keyboard, and waiting silently behind a ten minute suite is worse than being
# told to try again.
#
# NOTHING HERE RUNS THE REAL XCODEGEN or touches the real project. The generator
# and the lock are both seams, and the fixture generator writes a marker so a
# case can tell a run that generated from one that did not (L2).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "xcode project regeneration tests" 50

TARGET="scripts/regenerate-xcode-project.sh"
require_target "$TARGET"
harness_temp_dir WORK

# A generator that records that it ran, and answers however the case wants.
# A generator that records that it ran and answers however the case wants. It
# writes a project ONLY when it succeeds, which is what a real generator does and
# what the restore case below depends on.
stub_generator() {
    if [ "$1" = "0" ]; then
        printf '#!/bin/bash\necho "GENERATED" > "%s/generated.txt"\nmkdir -p "%s"\nexit 0\n' \
            "$WORK" "$WORK/tree/Ovation.xcodeproj" > "$WORK/xcodegen"
    else
        printf '#!/bin/bash\necho "GENERATED" > "%s/generated.txt"\nexit %s\n' \
            "$WORK" "$1" > "$WORK/xcodegen"
    fi
    chmod +x "$WORK/xcodegen"
}

fresh_tree() {
    rm -rf "$WORK/tree" "$WORK/generated.txt" "$WORK/lock"
    mkdir -p "$WORK/tree"
    printf 'name: Ovation\n' > "$WORK/tree/project.yml"
}

run_it() {
    OVATION_REPO_ROOT="$WORK/tree" \
    OVATION_XCODE_PROJECT="$WORK/tree/Ovation.xcodeproj" \
    OVATION_XCODEGEN="$WORK/xcodegen" \
    OVATION_DIR_LOCK="$WORK/lock" \
        "./$TARGET" 2>&1
}
status_of() { run_it >/dev/null 2>&1; printf '%s' "$?"; }

# 1. THE ORDINARY CASE: nothing holds the lock, so it regenerates and says so.
fresh_tree; stub_generator 0
OUT="$(run_it)"; RC=$?
check "a free lock lets it regenerate" "$RC" "0"
check "and the generator really ran" "$([ -f "$WORK/generated.txt" ] && echo yes || echo no)" "yes"
case "$OUT" in
    *Ovation.xcodeproj*) check "and it names what it rewrote" "yes" "yes" ;;
    *) check "and it names what it rewrote" "$OUT" "should name the project" ;;
esac

# 2. AND IT GIVES THE LOCK BACK. A regeneration that kept it would block every
#    build on the machine until somebody found the directory by hand, which is
#    the failure mkdir locks are known for (L409).
check "and the lock is released afterwards" \
    "$([ -d "$WORK/lock" ] && echo held || echo free)" "free"

# 3. THE WHOLE POINT: a held lock is a refusal, not a wait.
fresh_tree; stub_generator 0
mkdir -p "$WORK/lock"
printf 'Downbeat:4321\n' > "$WORK/lock/owner"
OUT="$(run_it)"; RC=$?
check "a held lock refuses" "$RC" "1"
case "$OUT" in
    *4321*) check "and it names who is holding it" "yes" "yes" ;;
    *) check "and it names who is holding it" "$OUT" "should name the holder" ;;
esac
check "and it did NOT generate" \
    "$([ -f "$WORK/generated.txt" ] && echo yes || echo no)" "no"
# The lock it did not take is still the holder's afterwards, or a refusal would
# have destroyed the very thing it was respecting.
check "and the holder still has it" \
    "$(head -1 "$WORK/lock/owner")" "Downbeat:4321"

# 4. A LOCK HELD BY A RUN THAT LEFT NO OWNER FILE is still held. Reporting it
#    free would make the one answer that matters look like the safe one (L98).
fresh_tree; stub_generator 0
mkdir -p "$WORK/lock"
OUT="$(run_it)"; RC=$?
check "a lock with no owner file is still a refusal" "$RC" "1"
case "$OUT" in
    *"no owner file"*) check "and it says the holder is unnamed rather than absent" "yes" "yes" ;;
    *) check "and it says the holder is unnamed rather than absent" "$OUT" "should say so" ;;
esac

# 5. A GENERATOR THAT FAILED IS NOT A REGENERATION, and the lock still comes back.
fresh_tree; stub_generator 3
OUT="$(run_it)"; RC=$?
check "a generator that failed is refused" "$RC" "2"
check "and the lock is still released, so a failure does not block the machine" \
    "$([ -d "$WORK/lock" ] && echo held || echo free)" "free"

# 5b. AND THE OLD PROJECT SURVIVES A FAILED GENERATION. This is the half that
#     matters: deleting the project and then finding the generator cannot make a
#     new one leaves the tree with NO project at all, which is destroying good
#     state before its replacement is verified to exist (L5). The old one is
#     moved aside and put back.
fresh_tree; stub_generator 3
mkdir -p "$WORK/tree/Ovation.xcodeproj"
printf 'the project that was already here\n' > "$WORK/tree/Ovation.xcodeproj/marker.txt"
OUT="$(run_it)"; RC=$?
check "a failed generation is still refused" "$RC" "2"
check "and the project that was there is STILL there" \
    "$(cat "$WORK/tree/Ovation.xcodeproj/marker.txt" 2>/dev/null)" "the project that was already here"
case "$OUT" in
    *"put back"*|*"still there"*) check "and it says the old one was kept" "yes" "yes" ;;
    *) check "and it says the old one was kept" "$OUT" "should say the old project was kept" ;;
esac

# 5c. A SUCCESSFUL RUN LEAVES NOTHING ASIDE. A copy kept beside the project would
#     be a second Ovation.xcodeproj in the tree for every later build to find.
fresh_tree; stub_generator 0
mkdir -p "$WORK/tree/Ovation.xcodeproj"
printf 'old\n' > "$WORK/tree/Ovation.xcodeproj/marker.txt"
run_it >/dev/null
check "a successful run leaves no copy of the old project behind" \
    "$(find "$WORK/tree" -maxdepth 1 -name 'Ovation.xcodeproj*' | wc -l | tr -d ' ')" "1"

# 5e. THE COMMITTED PACKAGE RESOLUTION SURVIVES A REGENERATION (ovation#421). It
#     is a tracked file inside the project, and the old project is moved aside
#     and dropped, so without carrying it over every regeneration would delete a
#     committed file and leave the next build to resolve every package afresh,
#     which is the floating that committing it exists to end. The stub generator
#     writes an empty project, as xcodegen writes one with no resolution in it.
RESOLVED_IN="project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
fresh_tree; stub_generator 0
mkdir -p "$WORK/tree/Ovation.xcodeproj/$(dirname "$RESOLVED_IN")"
printf '{ "pins" : [ "the committed resolution" ] }\n' > "$WORK/tree/Ovation.xcodeproj/$RESOLVED_IN"
OUT="$(run_it)"; RC=$?
check "a regeneration over a project holding the committed resolution succeeds" "$RC" "0"
check "and the new project carries the committed resolution, byte for byte" \
    "$(cat "$WORK/tree/Ovation.xcodeproj/$RESOLVED_IN" 2>/dev/null)" '{ "pins" : [ "the committed resolution" ] }'
check "and nothing of the old project is left beside it" \
    "$(find "$WORK/tree" -maxdepth 1 -name 'Ovation.xcodeproj*' | wc -l | tr -d ' ')" "1"

# 5d. AN EMPTY PATH IS REFUSED BEFORE ANY DELETE. This script deletes things, and
#     a recursive delete built from an empty variable is not the place to trust
#     that a caller set its seam (L5).
#
#     THE SEAMS HONOUR AN EMPTY VALUE RATHER THAN SUBSTITUTING THE DEFAULT, which
#     is what makes this reachable at all. Written with `:-` an empty
#     OVATION_XCODE_PROJECT silently became the REAL project path, so a caller who
#     deliberately pointed this at nothing would have had it point at everything,
#     and the guard could never fire (L29).
fresh_tree; stub_generator 0
OUT="$(OVATION_REPO_ROOT="$WORK/tree" OVATION_XCODE_PROJECT="" \
       OVATION_XCODEGEN="$WORK/xcodegen" OVATION_DIR_LOCK="$WORK/lock" \
       "./$TARGET" 2>&1)"
check "an empty project path is refused" "$?" "3"
check "and nothing was generated" \
    "$([ -f "$WORK/generated.txt" ] && echo yes || echo no)" "no"

fresh_tree; stub_generator 0
OUT="$(OVATION_REPO_ROOT="$WORK/tree" OVATION_XCODE_PROJECT="$WORK/tree/Ovation.xcodeproj" \
       OVATION_XCODEGEN="$WORK/xcodegen" OVATION_DIR_LOCK="" \
       "./$TARGET" 2>&1)"
check "an empty lock path is refused too" "$?" "3"

# 6. NOTHING TO GENERATE FROM is its own outcome.
fresh_tree; stub_generator 0; rm -f "$WORK/tree/project.yml"
OUT="$(run_it)"; RC=$?
check "a tree with no project.yml cannot be regenerated" "$RC" "3"
case "$OUT" in
    *project.yml*) check "and it names the file that is missing" "yes" "yes" ;;
    *) check "and it names the file that is missing" "$OUT" "should name project.yml" ;;
esac

# 7. NO GENERATOR AT ALL, said by name with the remedy, because a refusal whose
#    message does not say what to do leaves the reader facing the same command
#    (L148).
fresh_tree
rm -f "$WORK/xcodegen"
OUT="$(run_it)"; RC=$?
check "a missing xcodegen is refused" "$RC" "2"
case "$OUT" in
    *"brew install xcodegen"*) check "and the refusal carries the remedy" "yes" "yes" ;;
    *) check "and the refusal carries the remedy" "$OUT" "should say how to install it" ;;
esac

# ---------------------------------------------------------------------------
# 8. A PURE SUITE BUILDING FROM THE PROJECT IS SEEN, AND NAMED (ovation#299).
#
# Since ovation#271 the runner builds the pure suite OUTSIDE the directory build
# lock, so that lock no longer says whether anything is reading the project, and
# a regeneration could move the project aside under a pure build. The failure
# that produces reads as a broken build or a missing file, not as a race. The
# pure suite must still not wait behind a sibling, so it does not take that lock;
# it registers itself against the project, and the regeneration asks.
#
# THE REAL RUNNER IS HELD AT ITS BUILD STEP, through an injected pure command
# that waits on a file this suite removes, so the overlap is staged on
# conditions rather than on timing (L290). Its sibling lock is held by a
# stand in for Downbeat the whole time, to show the pure suite still does not
# wait for one.
# ---------------------------------------------------------------------------
[ -n "$WORK" ] || exit 1
PROJECT_LIB="$PWD/scripts/lib/ensure-xcode-project.sh"
TREE_PROJECT="$WORK/tree/Ovation.xcodeproj"
# The paths come from the helper itself, never a copy of its derivation (L70).
# A helper that is missing answers nothing, and an empty answer here would put
# the fixtures at the root of the disk, so it is replaced by a path in WORK.
readers_of() {
    local got
    got="$(bash -c '. "$1"; xcode_project_readers "$2"' _ "$PROJECT_LIB" "$1" 2>/dev/null)"
    printf '%s' "${got:-$WORK/no-readers-helper}"
}
create_lock_of() {
    local got
    got="$(bash -c '. "$1"; xcode_project_create_lock "$2"' _ "$PROJECT_LIB" "$1" 2>/dev/null)"
    printf '%s' "${got:-$WORK/no-create-lock-helper}"
}
wait_for_path() {
    local n=0
    until [ -e "$1" ]; do n=$((n+1)); [ "$n" -gt 400 ] && return 1; sleep 0.05; done
}
wait_for_text() {
    local n=0
    until grep -q "$2" "$1" 2>/dev/null; do n=$((n+1)); [ "$n" -gt 400 ] && return 1; sleep 0.05; done
}

PURE_HOLD="$WORK/pure-hold"
PURE_STARTED="$WORK/pure-started"
SIBLING_DIR_LOCK="$WORK/sibling-dir.lock"
# Sets PURE_PID. Every runner seam this could inherit from the shell that ran the
# suite is cleared or set, because an inherited skip or hosted command would
# answer for it (L169, L439). The bounded loop is the deadline on the hold, so a
# case that fails cannot leave this waiting for ever (L110).
start_held_pure_suite() {
    : > "$PURE_HOLD"; rm -f "$PURE_STARTED"
    env -u OVATION_SKIP_XCODE_PHASE -u OVATION_HOSTED_TEST_COMMAND -u OVATION_TEST_FLOOR \
        -u OVATION_SHELL_SUITE_DIR -u OVATION_SHELL_SUITE_FLOOR -u OVATION_LOCK_WAIT_LOG \
        OVATION_XCODEBUILD="$WORK/no-xcodebuild-given" \
        OVATION_XCODE_VERSION_FILE="$WORK/no-xcode-pin-given" \
        OVATION_DEFAULTS_DOMAINS_COMMAND="printf 'com.apple.finder\n'" \
        OVATION_DIR_LOCK="$SIBLING_DIR_LOCK" OVATION_FILE_LOCK="$WORK/sibling-file.lock" \
        OVATION_FLOCK_BIN=/usr/bin/true \
        OVATION_PROJECT_CREATE_POLL=0.05 \
        OVATION_UNLOCKED_COMMAND=true \
        OVATION_TEST_COMMAND="touch '$PURE_STARTED'; n=0; while [ -e '$PURE_HOLD' ] && [ \$n -lt 600 ]; do n=\$((n+1)); sleep 0.05; done" \
        OVATION_XCODE_PROJECT="$TREE_PROJECT" OVATION_XCODEGEN="$WORK/xcodegen" \
        ./scripts/run-tests.sh > "$WORK/pure.out" 2>&1 &
    PURE_PID=$!
}

# 8a. Refused while the pure suite builds, by name, touching nothing.
fresh_tree; stub_generator 0
mkdir -p "$TREE_PROJECT"
printf 'being built from\n' > "$TREE_PROJECT/marker.txt"
rm -rf "$SIBLING_DIR_LOCK"; mkdir -p "$SIBLING_DIR_LOCK"
printf 'Downbeat:4321\n' > "$SIBLING_DIR_LOCK/owner"
start_held_pure_suite
wait_for_path "$PURE_STARTED"
check "the pure suite reached its build step while a sibling held the build lock" \
    "$([ -e "$PURE_STARTED" ] && echo building || echo never-started)" "building"
OUT="$(run_it)"; RC=$?
check "a regeneration while a pure suite is building from the project is refused" "$RC" "1"
case "$OUT" in
    *"pure suite:$PURE_PID"*) check "and the refusal names the pure suite by its pid" "yes" "yes" ;;
    *) check "and the refusal names the pure suite by its pid" "$OUT" "should name pure suite:$PURE_PID" ;;
esac
check "and the project it is building from was not touched" \
    "$(cat "$TREE_PROJECT/marker.txt" 2>/dev/null)" "being built from"
check "and the generator did not run" \
    "$([ -f "$WORK/generated.txt" ] && echo yes || echo no)" "no"
check "and the refusal left neither of its locks behind" \
    "$({ [ -e "$WORK/lock" ] || [ -e "$(create_lock_of "$TREE_PROJECT")" ]; } && echo held || echo free)" "free"
rm -f "$PURE_HOLD"; wait "$PURE_PID"; PURE_ST=$?
rm -rf "$SIBLING_DIR_LOCK"
check "the pure suite then finishes green" "$PURE_ST" "0"
check "and once it has, a regeneration goes ahead" "$(status_of)" "0"

# 8b. A REGISTRATION LEFT BY A RUN THAT DIED does not refuse for ever. A pure
#     suite killed with -9 runs no trap, and a pid that is no longer running is
#     not building anything (L409, L600).
fresh_tree; stub_generator 0
READERS="$(readers_of "$TREE_PROJECT")"
bash -c 'exit 0' & DEAD_PID=$!; wait "$DEAD_PID"
mkdir -p "$READERS"; printf 'tree pure suite:%s\n' "$DEAD_PID" > "$READERS/$DEAD_PID"
check "a registration left by a pure suite that died does not refuse" "$(status_of)" "0"
check "and it is cleared rather than left for the next one" \
    "$([ -e "$READERS/$DEAD_PID" ] && echo left || echo cleared)" "cleared"

# 8c. SCOPED TO THE PROJECT. A pure suite in another tree reads another project,
#     so it must not refuse this one (L369). This suite's own pid is the live one.
fresh_tree; stub_generator 0
OTHER_READERS="$(readers_of "$WORK/other/Ovation.xcodeproj")"
mkdir -p "$OTHER_READERS"; printf 'other pure suite:%s\n' "$$" > "$OTHER_READERS/$$"
check "a pure suite reading a different tree's project does not refuse this one" "$(status_of)" "0"
rm -rf "$OTHER_READERS"

# 8d. AND THE OTHER DIRECTION. A regeneration holds the project's create lock
#     while it rewrites, so a pure suite starting then waits for its result, the
#     way it already waits for a create (ovation#207), instead of building from a
#     project that has been moved aside.
fresh_tree
printf '#!/bin/bash\ntouch "%s"\nn=0; while [ -e "%s" ] && [ $n -lt 600 ]; do n=$((n+1)); sleep 0.05; done\nmkdir -p "%s"\n' \
    "$WORK/gen-started" "$WORK/gen-hold" "$TREE_PROJECT" > "$WORK/xcodegen"
chmod +x "$WORK/xcodegen"
mkdir -p "$TREE_PROJECT"
: > "$WORK/gen-hold"; rm -f "$WORK/gen-started"
run_it > "$WORK/regen.out" 2>&1 & REGEN_PID=$!
wait_for_path "$WORK/gen-started"
REGEN_OWNER="$(head -1 "$(create_lock_of "$TREE_PROJECT")/owner" 2>/dev/null)"
check "a regeneration holds the project's create lock while it rewrites" \
    "${REGEN_OWNER%%:*}" "tree regenerate"
start_held_pure_suite
wait_for_text "$WORK/pure.out" "waiting for it"
# BOTH HALVES, because either alone passes for the wrong reason: a pure suite that
# found the project moved aside and started generating one of its own is also
# not building yet, and it is stuck in the held generator rather than waiting.
check "a pure suite starting during a regeneration waits for it rather than building" \
    "$([ -e "$PURE_STARTED" ] && echo built-anyway || echo not-built):$(grep -c 'waiting for it rather than generating over it' "$WORK/pure.out")" "not-built:1"
rm -f "$WORK/gen-hold"; wait "$REGEN_PID"
wait_for_path "$PURE_STARTED"
rm -f "$PURE_HOLD"; wait "$PURE_PID"; PURE_ST=$?
check "and builds once the regeneration is done" \
    "$([ -e "$PURE_STARTED" ] && echo "built:$PURE_ST" || echo "never:$PURE_ST")" "built:0"

# ---------------------------------------------------------------------------
# 9. A REGENERATION TOLD TO STOP, STOPS (ovation#302).
#
# The trap was one line for EXIT, INT and TERM, and a trap on INT or TERM that
# only cleans up RETURNS to the script (L473). A regeneration told to stop put
# the old project back, let go of both locks, and carried on: into xcodegen with
# no lock if it was told before the generator started, or, told during it, on to
# "OK: regenerated" and exit 0 over a project the trap had just replaced with the
# old one. ovation#274 fixed the same shape in run-tests.sh.
#
# TERM, and not INT, is what this sends: bash 5 can absorb an INT sent to one pid
# when the command in front of it exits normally, which run-tests.sh records. The
# signal goes to the regeneration's own pid, read from the owner line it wrote, so
# nothing else is signalled. Bash runs the trap when the generator returns, which
# is why the hold is released after the signal.
# ---------------------------------------------------------------------------
fresh_tree
printf '#!/bin/bash\ntouch "%s"\nn=0; while [ -e "%s" ] && [ $n -lt 600 ]; do n=$((n+1)); sleep 0.05; done\nmkdir -p "%s"\n' \
    "$WORK/gen-started" "$WORK/gen-hold" "$TREE_PROJECT" > "$WORK/xcodegen"
chmod +x "$WORK/xcodegen"
mkdir -p "$TREE_PROJECT"
printf 'the project before\n' > "$TREE_PROJECT/marker.txt"
: > "$WORK/gen-hold"; rm -f "$WORK/gen-started" "$WORK/stopped.status"
( run_it > "$WORK/stopped.out" 2>&1; echo "$?" > "$WORK/stopped.status" ) &
STOP_WRAPPER=$!
wait_for_path "$WORK/gen-started"
STOP_OWNER="$(head -1 "$WORK/lock/owner" 2>/dev/null)"
STOP_PID="${STOP_OWNER##*:}"
case "$STOP_PID" in ''|*[!0-9]*) STOP_PID="" ;; esac
[ -n "$STOP_PID" ] && kill -TERM "$STOP_PID" 2>/dev/null
rm -f "$WORK/gen-hold"
wait "$STOP_WRAPPER"
check "a regeneration stopped with TERM exits 143, not with a verdict" \
    "$(cat "$WORK/stopped.status" 2>/dev/null)" "143"
check "and it does not report having regenerated" \
    "$(grep -c 'OK: regenerated' "$WORK/stopped.out")" "0"
check "and the project that was there is put back" \
    "$(cat "$TREE_PROJECT/marker.txt" 2>/dev/null)" "the project before"
check "and it left neither of its locks behind" \
    "$({ [ -e "$WORK/lock" ] || [ -e "$(create_lock_of "$TREE_PROJECT")" ]; } && echo held || echo free)" "free"

# ---------------------------------------------------------------------------
# 10. IT TAKES ITS TURN IN THE ARRIVAL QUEUE (downbeat#524).
#
# Waiters on the build lock are served in the order they arrived, through a
# queue beside it, "<lock>.queue". A FREE lock with a live earlier waiter queued
# is that waiter's, so this refuses rather than taking it, the same way it refuses
# a held one. The queue here is beside $WORK/lock, never the real one.
# ---------------------------------------------------------------------------
QUEUE="$WORK/lock.queue"
sleep 60 & EARLIER=$!; disown "$EARLIER" 2>/dev/null
harness_on_exit "kill $EARLIER 2>/dev/null"
fresh_tree; stub_generator 0; rm -rf "$QUEUE"; mkdir -p "$QUEUE"
printf '%s %s\n' "$EARLIER" "$(ps -o lstart= -p "$EARLIER" | sed 's/^ *//; s/ *$//')" \
    > "$QUEUE/00000000001.000000.$EARLIER"
OUT="$(run_it)"; RC=$?
check "a free lock with a live earlier waiter queued is refused" "$RC" "1"
case "$OUT" in
    *"1 earlier run"*) check "and it says an earlier run is queued for it" "yes" "yes" ;;
    *) check "and it says an earlier run is queued for it" "$OUT" "should say 1 earlier run" ;;
esac
check "and it did NOT generate, or take the lock" \
    "$([ -f "$WORK/generated.txt" ] && echo generated || echo no):$([ -e "$WORK/lock" ] && echo held || echo free)" "no:free"
check "and it left the queue, and the earlier waiter's ticket stands" \
    "$(ls "$QUEUE" | tr '\n' ' ')" "00000000001.000000.$EARLIER "

# A waiter that died queued does not hold the turn, or one crash would refuse
# every regeneration until somebody emptied the queue by hand.
kill "$EARLIER" 2>/dev/null; wait "$EARLIER" 2>/dev/null
fresh_tree; stub_generator 0
check "a dead earlier waiter does not stop it regenerating" "$(status_of)" "0"
check "and the queue is empty afterwards, its ticket and the dead one both gone" \
    "$(ls "$QUEUE" | wc -l | tr -d ' ')" "0"

harness_end
