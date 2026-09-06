#!/bin/bash
# The judgement the built bundle suite makes, exercised WITHOUT a build.
#
# ovation#25. scripts/test-built-bundle-identity.sh took the configuration as
# $1 and defaulted to Debug, and scripts/run-tests.sh finds its suites by glob
# and can only invoke each one ONE way. So the RELEASE assertions never ran in
# the suite and never ran in the pre push gate, while a green run printed
# "built bundle identity tests" and read as coverage of the shipping build
# (L413, L400, L98).
#
# The five judgements now live in scripts/lib/bundle-identity-checks.sh so that
# ONE implementation answers for both configurations, rather than a second copy
# being written for Release (L370). This suite feeds that function fabricated
# signature and entitlement text and asserts what it concludes.
#
# WHY THIS SUITE EXISTS BESIDE THE REAL ONE. The real suite can only assert what
# this machine's two bundles happen to be, and both are currently correct, so it
# can never demonstrate the function REFUSING anything. A guard that has only
# been seen to pass has not been seen to work (L1). Here the failure cases are
# staged directly and cost nothing, and the one that matters most is ovation#9's
# actual defect: a Release bundle carrying com.apple.security.get-task-allow,
# which declares hardened runtime while switching off its central protection.
#
# THE FIXTURES ARE MEASURED, NOT INVENTED (L48). Every line below was taken from
# `codesign -d --verbose=2` and `codesign -d --entitlements - --xml | plutil -p`
# run against this repository's own Debug and Release bundles on 2026-09-06.
# Paths are replaced; nothing else is.
#
# The real suite still feeds REAL codesign output through this same function on
# every run, so the interface is exercised for real rather than only against
# text written here (L52).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "bundle identity judgement tests" 16

TARGET="scripts/lib/bundle-identity-checks.sh"
require_target "$TARGET"
. "./$TARGET"

# ---------------------------------------------------------------------------
# Fixtures, shaped from the real output.
# ---------------------------------------------------------------------------
signature() {
    # signature <identifier> <authority, empty for none> <CodeDirectory flags>
    local id="$1" authority="$2" flags="$3"
    printf 'Executable=/staged/Ovation.app/Contents/MacOS/Ovation\n'
    printf 'Identifier=%s\n' "$id"
    printf 'Format=app bundle with Mach-O universal (x86_64 arm64)\n'
    printf 'CodeDirectory v=20500 size=502 flags=%s hashes=5+7 location=embedded\n' "$flags"
    printf 'Signature size=1702\n'
    if [ -n "$authority" ]; then printf 'Authority=%s\n' "$authority"; fi
    printf 'Signed Time=Sep 6, 2026 at 10:53:52 AM\n'
    printf 'Info.plist entries=20\n'
    printf 'TeamIdentifier=not set\n'
    # This line is why the hardened runtime assertion may not simply look for
    # the word. It is present on a bundle that carries NO runtime flag at all.
    printf 'Runtime Version=26.5.0\n'
    printf 'Sealed Resources version=2 rules=13 files=0\n'
    printf 'Internal requirements count=1 size=100\n'
}

adhoc_signature() {
    # What the bundles looked like before ovation#9: no Authority, and codesign
    # reports the signature itself as adhoc.
    local id="$1"
    printf 'Executable=/staged/Ovation.app/Contents/MacOS/Ovation\n'
    printf 'Identifier=%s\n' "$id"
    printf 'Format=app bundle with Mach-O universal (x86_64 arm64)\n'
    printf 'CodeDirectory v=20500 size=502 flags=0x10000(runtime) hashes=5+7 location=embedded\n'
    printf 'Signature=adhoc\n'
    printf 'Info.plist entries=20\n'
    printf 'TeamIdentifier=not set\n'
    printf 'Sealed Resources version=2 rules=13 files=0\n'
    printf 'Internal requirements count=1 size=100\n'
}

GOOD_FLAGS='0x10000(runtime)'
NO_FLAGS='0x0(none)'
DEBUGGABLE='{
  "com.apple.security.get-task-allow" => true
}'
NOT_DEBUGGABLE='{
}'

REL_SIG="$(signature com.danwright.ovation 'Ovation Local Signing' "$GOOD_FLAGS")"
DBG_SIG="$(signature com.danwright.ovation.debug 'Ovation Local Signing' "$GOOD_FLAGS")"

# Runs the judgement in a subshell so its verdicts are COUNTED rather than
# inherited: this suite has to observe the function failing without failing
# itself. Prints "<assertions run> <passed> <failed>".
outcome() {
    (
        PASS=0; FAIL=0; _HARNESS_RAN=0
        bundle_identity_checks "$1" "$2" "$3" >/dev/null 2>&1
        printf '%s %s %s' "$_HARNESS_RAN" "$PASS" "$FAIL"
    )
}

# ---------------------------------------------------------------------------
# 1. The healthy pair. Both configurations as this machine actually builds them.
# ---------------------------------------------------------------------------
check "a correct Release bundle passes every judgement" \
    "$(outcome Release "$REL_SIG" "$NOT_DEBUGGABLE")" "5 5 0"
check "a correct Debug bundle passes every judgement" \
    "$(outcome Debug "$DBG_SIG" "$DEBUGGABLE")" "5 5 0"

# ---------------------------------------------------------------------------
# 2. SEEN TO FAIL: ovation#9's actual defect.
#
# When the stable signing identity landed, Xcode began adding
# com.apple.security.get-task-allow to BOTH configurations, because a self
# signed identity with no provisioning profile reads as a development setup.
# Any process can then attach a debugger and read the app's memory. Ovation will
# hold Gmail refresh tokens with send and modify rights, and seven years of tax
# records. ENABLE_HARDENED_RUNTIME was YES throughout and both bundles carried
# the runtime flag, so every other reading said the app was protected (L188).
# ---------------------------------------------------------------------------
check "a Release bundle a debugger can attach to is REFUSED" \
    "$(outcome Release "$REL_SIG" "$DEBUGGABLE")" "5 4 1"

# And the inverse, which is a real defect too: without it Xcode cannot attach
# and debugging the app is silently broken.
check "a Debug bundle a debugger CANNOT attach to is refused" \
    "$(outcome Debug "$DBG_SIG" "$NOT_DEBUGGABLE")" "5 4 1"

# ---------------------------------------------------------------------------
# 3. The identity. This is the whole of plan 1.1's isolation: macOS keys the
#    data directory, the TCC grants and the Gmail login to this string.
# ---------------------------------------------------------------------------
check "a Release bundle wearing the Debug identifier is refused" \
    "$(outcome Release "$DBG_SIG" "$NOT_DEBUGGABLE")" "5 4 1"
check "a Debug bundle wearing the Release identifier is refused" \
    "$(outcome Debug "$REL_SIG" "$DEBUGGABLE")" "5 4 1"

# ---------------------------------------------------------------------------
# 4. Ad hoc signing, the world before ovation#9. It mints a NEW code identity on
#    every install, and macOS keys folder permission grants to that identity, so
#    the backup folder grant PRD 5.29 depends on is re-asked after every rebuild.
#    Two judgements fail together: no stable authority, and an adhoc signature.
# ---------------------------------------------------------------------------
check "an ad hoc signed Release bundle is refused" \
    "$(outcome Release "$(adhoc_signature com.danwright.ovation)" "$NOT_DEBUGGABLE")" "5 3 2"
check "an ad hoc signed Debug bundle is refused" \
    "$(outcome Debug "$(adhoc_signature com.danwright.ovation.debug)" "$DEBUGGABLE")" "5 3 2"

# A bundle signed by SOMETHING ELSE is not Ovation's stable identity either,
# even though it is not ad hoc.
check "a bundle signed by another authority is refused" \
    "$(outcome Release "$(signature com.danwright.ovation 'Apple Development: someone' "$GOOD_FLAGS")" \
        "$NOT_DEBUGGABLE")" "5 4 1"

# ---------------------------------------------------------------------------
# 5. Hardened runtime, judged on the FLAGS and not on the word.
#
# `codesign` prints a `Runtime Version=` line on a bundle that carries no
# runtime flag whatsoever, so a check that merely looks for the word passes a
# completely unhardened bundle. That is a silent false green, which is worse
# than the false red it looks like (L188).
# ---------------------------------------------------------------------------
check "a Release bundle with no hardened runtime is refused" \
    "$(outcome Release "$(signature com.danwright.ovation 'Ovation Local Signing' "$NO_FLAGS")" \
        "$NOT_DEBUGGABLE")" "5 4 1"
check "a Debug bundle with no hardened runtime is refused" \
    "$(outcome Debug "$(signature com.danwright.ovation.debug 'Ovation Local Signing' "$NO_FLAGS")" \
        "$DEBUGGABLE")" "5 4 1"

# ---------------------------------------------------------------------------
# 6. Empty input is a REFUSAL, not a pass. A caller whose codesign call failed
#    hands this function nothing, and nothing must never satisfy five security
#    judgements (L215, L98).
# ---------------------------------------------------------------------------
check "empty signature text fails rather than passing" \
    "$(outcome Release "" "$NOT_DEBUGGABLE" | awk '{print ($3 > 0) ? "refused" : "accepted"}')" "refused"

# ---------------------------------------------------------------------------
# 7. THE COUNT IS PART OF THE CONTRACT. The real suite declares its total to the
#    harness, and a declaration that does not match what this function runs per
#    configuration is how the Release half goes missing again without anything
#    noticing (L288).
# ---------------------------------------------------------------------------
check "the function reports how many judgements it makes" "$(bundle_identity_checks_count)" "5"
check "and Release runs exactly that many" \
    "$(outcome Release "$REL_SIG" "$NOT_DEBUGGABLE" | cut -d' ' -f1)" "5"
check "and Debug runs exactly that many" \
    "$(outcome Debug "$DBG_SIG" "$DEBUGGABLE" | cut -d' ' -f1)" "5"

# ---------------------------------------------------------------------------
# 8. An unknown configuration is refused rather than silently judged as Debug.
#    Defaulting to Debug is precisely the defect this issue is about, so the
#    function must not carry one anywhere (L320).
# ---------------------------------------------------------------------------
check "an unknown configuration is refused, never treated as Debug" \
    "$(outcome Staging "$REL_SIG" "$NOT_DEBUGGABLE" | awk '{print ($3 > 0) ? "refused" : "accepted"}')" "refused"

harness_end
