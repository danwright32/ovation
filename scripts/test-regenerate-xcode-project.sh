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
harness_begin "xcode project regeneration tests" 23

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

harness_end
