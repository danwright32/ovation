#!/bin/bash
# The judgements Ovation makes about a BUILT, SIGNED bundle. One implementation,
# answering for every configuration.
#
# ovation#25. These lived inside scripts/test-built-bundle-identity.sh, which
# took the configuration as $1 and defaulted to Debug. scripts/run-tests.sh
# finds its suites by glob and can only invoke each one ONE way, so the Release
# half never ran in the suite or in the pre push gate, while a green run printed
# "built bundle identity tests" and read as coverage of the shipping build
# (L413, L400).
#
# The obvious repair was a second suite file for Release. That is a second copy
# of five security judgements, and sharing the DATA while copying the LOGIC is
# not consolidation (L370). So the logic moved here and both configurations run
# through it.
#
# WHAT THIS ASSERTS AND WHY IT READS THE BUNDLE. A value your configuration SETS
# is only in force if nothing downstream recomputes it. Xcode derives several of
# these from other inputs and overwrites what project.yml asked for, silently,
# and the setting goes on reading as protection while protecting nothing (L188).
# So every judgement below reads the signed bundle on disk, never a build
# setting.
#
# Usage, from a suite that has already sourced the test harness:
#
#     . "$(dirname "$0")/lib/bundle-identity-checks.sh"
#     bundle_identity_checks Release "$signature_text" "$entitlements_text"
#
# It runs exactly `bundle_identity_checks_count` assertions through the
# harness's own `check`, so a caller declares its total as
# (number of configurations) times that count and the harness refuses a short
# run (L288).

# How many assertions one call makes. A caller derives its declared total from
# this rather than writing the number twice, because two numbers that must agree
# drift and the one that drifts is the declaration nobody re-reads (L70).
bundle_identity_checks_count() { printf '6'; }

bundle_identity_checks() {
    local config="$1" sig="$2" ents="$3"
    local expected_id i

    # An unknown configuration is REFUSED, not quietly judged as Debug.
    # Defaulting to Debug is the exact defect this issue exists to remove, so
    # nothing here carries one (L320). It still runs the declared number of
    # assertions, so a caller's count stays honest while every one of them says
    # what went wrong (L11).
    case "$config" in
        Release) expected_id="com.danwright.ovation" ;;
        Debug)   expected_id="com.danwright.ovation.debug" ;;
        *)
            for i in 1 2 3 4 5; do
                check "configuration '$config' is not one this suite can judge" \
                    "unknown configuration" "Debug or Release"
            done
            return 1
            ;;
    esac

    # 1. THE IDENTITY. This string is the entire isolation mechanism behind plan
    #    1.1: macOS keys the data directory, the TCC grants and the Gmail login
    #    to it. Read off the SIGNED bundle, because that is the one the system
    #    will use.
    check "the signed bundle carries the $config identity" \
        "$(printf '%s' "$sig" | awk -F= '/^Identifier=/ { print $2 }')" \
        "$expected_id"

    # 2. AND 3. THE SIGNING IDENTITY, as ovation#9 left it.
    #
    # Ad hoc signing mints a NEW code identity on every install, and macOS keys
    # folder permission grants to that identity. PRD 5.29 has Ovation writing
    # backups to a folder Dan chooses, and plan 1.8 is where it first asks. A
    # backup feature that re-asks after every rebuild is one he stops trusting,
    # and those backups are the only copy of a seven year tax record.
    check "the $config bundle is signed with Ovation's own stable identity" \
        "$(printf '%s' "$sig" | grep -c 'Authority=Ovation Local Signing')" "1"
    check "and the $config bundle is NOT ad hoc signed" \
        "$(printf '%s' "$sig" | grep -c 'Signature=adhoc')" "0"

    # 4. HARDENED RUNTIME, JUDGED ON THE CodeDirectory FLAGS.
    #
    # Not on the word "runtime" anywhere in the output. `codesign` prints a
    # `Runtime Version=` line on a bundle carrying no runtime flag at all, so a
    # check that looks for the word passes a completely unhardened bundle. That
    # is a silent false green, and a false green is the failure direction that
    # nobody ever investigates (L188).
    check "hardened runtime is in force on the $config bundle" \
        "$(printf '%s' "$sig" \
            | awk '/^CodeDirectory /{ for (i=1;i<=NF;i++) if ($i ~ /^flags=/) { print $i; exit } }' \
            | grep -c 'runtime')" "1"

    # 5. AND THE ENTITLEMENT THAT DECIDES WHETHER ANY OF THAT MEANS ANYTHING.
    #
    # `com.apple.security.get-task-allow` lets any process attach a debugger and
    # read the app's memory. With it present, hardened runtime is declared and
    # its main protection is switched off, so reading the flag alone says the
    # app is protected when it is not.
    #
    # Debug NEEDS it, or Xcode cannot attach and debugging is broken.
    # Release MUST NOT HAVE IT. Ovation will hold Gmail refresh tokens carrying
    # send and modify rights on Dan's mailbox, and seven years of tax records.
    #
    # Found 2026-09-06, the moment the stable identity landed: Xcode was adding
    # it to BOTH, because a self signed identity with no provisioning profile is
    # treated as a development signing setup.
    if [ "$config" = "Release" ]; then
        check "the shipping build does NOT let a debugger attach" \
            "$(printf '%s' "$ents" | grep -c 'get-task-allow')" "0"
    else
        check "the debug build DOES let a debugger attach, or Xcode cannot debug it" \
            "$(printf '%s' "$ents" | grep -c 'get-task-allow')" "1"
    fi

    # 6. LIBRARY VALIDATION, WHICH IS THE OTHER HALF OF WHAT HARDENED RUNTIME IS
    #    FOR, and it is asserted in BOTH directions rather than one.
    #
    # `com.apple.security.cs.disable-library-validation` stops macOS checking
    # that code loaded into the process is signed by the same identity. Debug
    # carries it deliberately (ovation#59, signed off by Dan on 2026-09-06):
    # without it the hosted test bundle cannot load at all, because Ovation's
    # signing identity has no Team ID and macOS treats two unset teams as
    # different. That build already carries get-task-allow above, so it is not a
    # security boundary.
    #
    # RELEASE MUST NEVER GAIN IT. The shipping build holds Gmail refresh tokens
    # and seven years of tax records, and an exemption added for a test bundle is
    # exactly the kind that spreads by being copied into the wrong file.
    #
    # And DEBUG IS ASSERTED TO STILL HAVE IT, because removing it does not break
    # anything visibly: it makes the hosted suite fail to load with a dyld
    # message about Team IDs, which reads as a build problem rather than as a
    # setting somebody changed.
    if [ "$config" = "Release" ]; then
        check "the shipping build still validates the code it loads" \
            "$(printf '%s' "$ents" | grep -c 'disable-library-validation')" "0"
    else
        check "the debug build allows the hosted test bundle to load" \
            "$(printf '%s' "$ents" | grep -c 'disable-library-validation')" "1"
    fi
}
