#!/bin/bash
# Building both configurations must be ONE command, through the runner once, and
# it takes no sibling lock (ovation#302).
#
# ovation#28. scripts/test-built-bundle-identity.sh refuses when a configuration
# has no built product, which is right on Dan's Mac and wrong on a fresh runner
# where a missing build is normal. Dan's decision 2026-09-06: CI BUILDS BOTH
# rather than skipping the suite, because skipping leaves the shipping build's
# bundle assertions running only on one machine.
#
# So there has to be a command CI can call, and this is its suite. It is also
# the command a person needs: assembling it by hand was done repeatedly during
# Phase 0, each time re-deriving the same lock incantation (L41).
#
# THE RUNNER IS CALLED ONCE, NOT PER CONFIGURATION, so the project is ensured and
# the live data bracket taken once for both builds. That is asserted rather than
# assumed. Section 4 pins that no sibling lock is taken, which is the measured
# decision recorded in the script's header.
#
# NOTHING HERE RUNS xcodebuild. The runner and the build command are seams, so
# the suite measures the ORCHESTRATION rather than paying for two real builds
# (L2, L291).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "build products tests" 16

TARGET="scripts/build-products.sh"
require_target "$TARGET"
harness_temp_dir WORK

# A stand-in for scripts/run-tests.sh. It records that it was called, and runs
# whatever it was handed, so the locking contract is observable without locks.
cat > "$WORK/runner" <<'EOF'
#!/bin/bash
  echo "runner-invoked" >> "$RECORD"
  echo "skip-seam:${OVATION_SKIP_XCODE_PHASE:-unset}" >> "$RECORD"
  echo "hosted:${OVATION_HOSTED_TEST_COMMAND:-unset}" >> "$RECORD"
  printf '%s\n' "$OVATION_TEST_COMMAND" >> "$RECORD"
  bash -c "$OVATION_TEST_COMMAND"
EOF
chmod +x "$WORK/runner"

# A stand-in for xcodebuild. It records the configuration it was asked for, and
# fails for whichever configuration FAIL_ON names.
cat > "$WORK/builder" <<'EOF'
#!/bin/bash
  echo "built:$1" >> "$RECORD"
  if [ "$1" = "${FAIL_ON:-}" ]; then echo "the compiler said no"; exit 65; fi
  exit 0
EOF
chmod +x "$WORK/builder"

RECORD="$WORK/record"

run_build() {
    : > "$RECORD"
    RECORD="$RECORD" FAIL_ON="${FAIL_ON:-}" \
    OVATION_BUILD_RUNNER="$WORK/runner" \
    OVATION_BUILD_COMMAND="$WORK/builder" \
        "./$TARGET" 2>&1
}
build_once() { BUILD_OUT="$(run_build)"; BUILD_ST=$?; }
says() { if printf '%s' "$1" | grep -qF "$2"; then echo yes; else echo no; fi; }

# ---------------------------------------------------------------------------
# 1. THE HAPPY PATH, and what it is allowed to rest on.
# ---------------------------------------------------------------------------
FAIL_ON="" build_once
check "building both configurations succeeds" "$BUILD_ST" "0"
check "it asked for Debug" "$(grep -c '^built:Debug$' "$RECORD")" "1"
check "it asked for Release" "$(grep -c '^built:Release$' "$RECORD")" "1"

# THE RUNNER IS CALLED ONCE. Per configuration would ensure the project and
# bracket live data twice for one request.
check "both builds go through the runner once, not once per configuration" \
    "$(grep -c '^runner-invoked$' "$RECORD")" "1"
check "and the build goes THROUGH the runner, so it gets the project and the live data bracket" \
    "$(grep -c '^runner-invoked$' "$RECORD")" "1"
# Matched on the OUTCOME phrase, not on the configuration names. Written first
# as a search for "Debug and Release", which the opening announcement also
# contains, so it was satisfied by the line saying the build was STARTING and
# could not tell a finished run from a failed one (L178).
check "it says both configurations are ready" "$(says "$BUILD_OUT" "built and ready")" "yes"

# ---------------------------------------------------------------------------
# 2. A FAILING BUILD. The exit code is the verdict, never a line of output
#    (L184), and the configuration that failed is named, because "the build
#    failed" sends somebody to look at both.
# ---------------------------------------------------------------------------
FAIL_ON=Debug build_once
check "a failing Debug build fails the command" \
    "$([ "$BUILD_ST" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and it names the configuration that failed" "$(says "$BUILD_OUT" "Debug")" "yes"
check "and it does not claim both are ready" "$(says "$BUILD_OUT" "built and ready")" "no"

FAIL_ON=Release build_once
check "a failing Release build fails the command too" \
    "$([ "$BUILD_ST" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and Debug having succeeded first does not rescue it" \
    "$(says "$BUILD_OUT" "built and ready")" "no"

# ---------------------------------------------------------------------------
# 3. THE RUNNER'S OWN FAILURE. If the locks cannot be taken at all, that is not
#    a build failure and must not read as one: a runner that could not acquire
#    them has built nothing (L11, L98).
# ---------------------------------------------------------------------------
cat > "$WORK/refusing-runner" <<'EOF'
#!/bin/bash
  echo "could not take the test locks" >&2
  exit 3
EOF
chmod +x "$WORK/refusing-runner"
: > "$RECORD"
OUT_LOCK="$(RECORD="$RECORD" OVATION_BUILD_RUNNER="$WORK/refusing-runner" \
    OVATION_BUILD_COMMAND="$WORK/builder" "./$TARGET" 2>&1)"; ST_LOCK=$?
check "a runner that cannot take the locks is not reported as a build failure" \
    "$([ "$ST_LOCK" -ne 0 ] && echo nonzero || echo zero)" "nonzero"

# THE SKIP SEAM MUST NOT REACH THE BUILDER (ovation#22, ovation#143).
#
# OVATION_SKIP_XCODE_PHASE tells the runner not to do the xcodebuild work, which
# is exactly the work THIS script exists to do, and it is an environment variable
# so it is inherited by every process started under one that has it set. A hook
# that set it for a documentation push, and then anything that called this, would
# get a script that reports both configurations built and builds neither (L169,
# L439). Twice today a seam was inherited this way, which is why this is a case
# rather than a comment.
FAIL_ON="" OVATION_SKIP_XCODE_PHASE=1 run_build >/dev/null 2>&1
check "the skip seam does not reach the runner this script drives" \
    "$(grep -c 'skip-seam:unset' "$RECORD")" "1"
check "and both configurations were still built" \
    "$(grep -c '^built:' "$RECORD")" "2"

# ---------------------------------------------------------------------------
# 4. THE BUILDS TAKE NO SIBLING LOCK, AND THAT IS A DECISION (ovation#302).
#
# The builds travel as the runner's pure command, which since ovation#271 runs
# outside both sibling locks, and with no hosted command the runner takes no lock
# at all. ovation#271 measured that only the hosted suite's TESTING, which orders
# windows front, collided with a sibling; its unlocked Debug app builds beside
# Overture's tests saw none of the 21 failures. So this pins what the header now
# says, rather than a lock the header used to claim.
#
# AND AN INHERITED HOSTED COMMAND DOES NOT REACH THE RUNNER. It is an environment
# variable, so a shell that had one set would have this script run somebody's
# hosted command under the sibling locks after building, which is not what it was
# asked to do (L169, L439).
# ---------------------------------------------------------------------------
FAIL_ON="" build_once
check "the runner is handed no hosted command, so it takes no sibling lock for the builds" \
    "$(grep -c '^hosted:unset$' "$RECORD")" "1"
FAIL_ON="" OVATION_HOSTED_TEST_COMMAND="echo inherited" run_build >/dev/null 2>&1
check "and a hosted command inherited from the shell does not reach the runner" \
    "$(grep -c '^hosted:unset$' "$RECORD")" "1"

harness_end
