#!/bin/bash
# Building both configurations must be ONE command, and it must take the sibling
# locks exactly once.
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
# THE LOCKS ARE TAKEN ONCE, NOT PER CONFIGURATION. Two acquisitions means
# releasing between them, so a sibling can take them in the gap and the second
# build waits again, doubling a wait this exists to pay only once. That is
# asserted rather than assumed.
#
# NOTHING HERE RUNS xcodebuild. The runner and the build command are seams, so
# the suite measures the ORCHESTRATION rather than paying for two real builds
# (L2, L291).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "build products tests" 14

TARGET="scripts/build-products.sh"
require_target "$TARGET"
harness_temp_dir WORK

# A stand-in for scripts/run-tests.sh. It records that it was called, and runs
# whatever it was handed, so the locking contract is observable without locks.
cat > "$WORK/runner" <<'EOF'
#!/bin/bash
  echo "runner-invoked" >> "$RECORD"
  echo "skip-seam:${OVATION_SKIP_XCODE_PHASE:-unset}" >> "$RECORD"
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

# THE LOCK IS TAKEN ONCE. Per configuration would release between builds, and a
# sibling taking them in that gap makes the second build wait all over again.
check "the sibling locks are taken exactly once, not once per configuration" \
    "$(grep -c '^runner-invoked$' "$RECORD")" "1"
check "and the build goes THROUGH the runner, so the locks are taken at all" \
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

harness_end
