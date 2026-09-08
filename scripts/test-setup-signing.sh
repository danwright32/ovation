#!/bin/bash
# The signing setup must be idempotent, must detect an existing identity without
# being defeated by its own pipeline, and must refuse rather than claim success
# when the identity did not actually get created.
#
# ovation#9. It cannot be run for real by anything automated: `security
# add-trusted-cert` raises a system password prompt, so the real run is Dan's.
# That is exactly why the parts that CAN be checked are checked here, rather than
# the whole thing being taken on trust because one manual run appeared to work.
#
# The seams below are a DELIBERATE DIFFERENCE from the port source, which has
# none and is therefore untestable. The port discipline says re-check rather than
# copy (docs/PORT-DISCIPLINE.md), and a script nothing can exercise is the kind of
# thing a clone inherits silently.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "setup-signing tests" 27

TARGET="scripts/setup-signing.sh"
require_target "$TARGET"

# Created, guarded against a failed mktemp, and removed by the harness on every
# exit path. The suite never writes an rm of its own (ovation#19).
harness_temp_dir WORK

# A stub standing in for /usr/bin/security. It records what it was asked to do,
# so the test can assert the script did NOT reach the creating steps when the
# identity was already there.
make_security() {
    cat > "$WORK/security" <<STUB
#!/bin/bash
echo "\$@" >> "$WORK/security-calls"
case "\$1" in
  find-identity) cat "$WORK/identities" ;;
  import) [ -f "$WORK/import-does-nothing" ] || printf '  1) ABC "Ovation Local Signing"\n     1 valid identities found\n' > "$WORK/identities"; exit 0 ;;
  set-key-partition-list) [ -f "$WORK/partition-fails" ] && exit 1; exit 0 ;;
  *) exit 0 ;;
esac
STUB
    chmod +x "$WORK/security"
}
make_openssl() {
    cat > "$WORK/openssl" <<STUB
#!/bin/bash
echo "\$@" >> "$WORK/openssl-calls"
# Produce whatever output file was asked for, so the script can carry on.
prev=""
for a in "\$@"; do
  case "\$prev" in -keyout|-out) : > "\$a" ;; esac
  prev="\$a"
done
exit 0
STUB
    chmod +x "$WORK/openssl"
}
make_security; make_openssl
reset_calls() { rm -f "$WORK/security-calls" "$WORK/openssl-calls"; }
run_target() {
    OVATION_SECURITY_BIN="$WORK/security" OVATION_OPENSSL_BIN="$WORK/openssl" \
        "./$TARGET" 2>&1
}

# 1. Already present: do nothing, say so, exit 0.
reset_calls
printf '  1) ABC "Ovation Local Signing"\n     1 valid identities found\n' > "$WORK/identities"
OUT1="$(run_target)"; ST1=$?
check "an existing identity is left alone and exits 0" "$ST1" "0"
check "and it says there is nothing to do" \
    "$(printf '%s' "$OUT1" | grep -c "already exists")" "1"
# `grep -c` PRINTS 0 and also EXITS non zero when it matches nothing, so an
# `|| echo 0` fallback appends a second zero and the comparison sees "0\n0".
# Count the file's own lines instead, which has one answer in every case.
calls_matching() {
    if [ -f "$1" ]; then grep -c "$2" "$1" || true; else echo 0; fi
}
check "and it did NOT reach the certificate creating steps" \
    "$(calls_matching "$WORK/security-calls" "add-trusted-cert")" "0"

# 2. THE REGRESSION THE SOURCE ALREADY CARRIES A FIX FOR (downbeat#369, L183).
#    Detection must not pipe into a short circuiting consumer. `grep -q` exits on
#    the first match, leaving `security` writing into a closed pipe, and under
#    pipefail that reports FAILURE on a match, so an identity that EXISTS reads as
#    absent. A long listing is what makes the race actually happen.
reset_calls
{ for i in $(seq 1 400); do printf '  %d) DEADBEEF%04d "Some Other Identity %d"\n' "$i" "$i" "$i"; done
  printf '  401) ABC "Ovation Local Signing"\n     401 valid identities found\n'; } > "$WORK/identities"
OUT2="$(run_target)"; ST2=$?
check "a match deep in a long listing is still found, not defeated by the pipeline" \
    "$ST2" "0"
check "and it reports the identity as existing" \
    "$(printf '%s' "$OUT2" | grep -c "already exists")" "1"

# 3. Absent: it must attempt creation, and must trust the certificate.
#
# The import is made to change nothing here, so the identity is still absent when
# the script reads back, which is what case 4 below asserts on.
reset_calls
printf '     0 valid identities found\n' > "$WORK/identities"
: > "$WORK/import-does-nothing"
OUT3="$(run_target)"; ST3=$?
rm -f "$WORK/import-does-nothing"
check "an absent identity reaches the trust step" \
    "$(calls_matching "$WORK/security-calls" "add-trusted-cert")" "1"

# 4. AND THE PART THAT MATTERS. After trying to create it, the identity is still
#    not there. That must be an ERROR, not a cheerful finish: a setup script that
#    reports success while the thing it set up does not exist is worse than one
#    that fails, because the next step trusts it (L98, L12).
#
#    The stub otherwise makes the import SUCCEED, because that is what the real
#    world does and the cases below depend on it. This one case turns that off,
#    which is what makes it a test of the failure rather than of the fixture.
check "creation that did not take is an error, not a success" \
    "$([ "$ST3" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and it says the identity was not created" \
    "$(printf '%s' "$OUT3" | grep -ci "was not created")" "1"
check "and it does NOT tell Dan to go and rebuild" \
    "$(printf '%s' "$OUT3" | grep -ci "rebuild")" "0"

# 5. Ovation's own identity name, not the one it was ported from. Three siblings
#    already use "<App> Local Signing" and each is distinct, so the signer of a
#    given app is identifiable.
check "it creates Ovation's own identity, not the port source's" \
    "$(grep -c 'Downbeat Local Signing' "$TARGET")" "0"

# ---------------------------------------------------------------------------
# THE KEYCHAIN PROMPT. ovation#24.
#
# `security import ... -T /usr/bin/codesign -A` exists precisely to pre-authorise
# codesign so a build never raises a dialog. IT DID NOT WORK. On 2026-09-06 Dan
# ran this script, it reported success, the identity was genuinely created, and
# the first build then blocked on a macOS keychain dialog for several minutes
# with nothing saying so: the build printed nothing unusual and simply did not
# finish, and the only evidence was SecurityAgent sitting beside a waiting
# codesign. A wait that cannot be told from a hang is the worse of the two
# (L110).
#
# Since macOS Sierra the real gate is the key's PARTITION LIST, which `-A` and
# `-T` do not set, so that is added here.
#
# WHAT THIS SUITE CANNOT PROVE, said plainly rather than implied by its passing
# (L400): whether the prompt is actually gone. That only reproduces on a machine
# that has never authorised this key, and this one now has. What is asserted is
# that the partition list is set, and that the script SAYS what may still happen,
# which is the half that holds whatever the first half turns out to do.
reset_calls
printf '  0 valid identities found\n' > "$WORK/identities"
rm -f "$WORK/partition-fails"
OUT_NEW="$(run_target)"

check "it sets the key partition list, which is the real gate since Sierra" \
    "$(calls_matching "$WORK/security-calls" "set-key-partition-list")" "1"
check "and the list names codesign" \
    "$(calls_matching "$WORK/security-calls" "codesign:")" "1"
check "and it does that AFTER importing the key, not before" \
    "$(awk '/import/{i=NR} /set-key-partition-list/{p=NR} END{print (i>0 && p>i) ? "after" : "not-after"}' "$WORK/security-calls")" "after"

check "it warns that the first build may still stop for a keychain dialog" \
    "$(printf '%s' "$OUT_NEW" | grep -ci "keychain dialog")" "1"
check "and it names Always Allow, because Allow grants it once and it comes back" \
    "$(printf '%s' "$OUT_NEW" | grep -c "Always Allow")" "1"

# A partition list that could not be set is its own outcome. The identity still
# exists and is usable, so this must not fail the script, and it must not be
# silent either: the person will meet the dialog and needs to know why (L11).
reset_calls
: > "$WORK/partition-fails"
printf '  0 valid identities found\n' > "$WORK/identities"
OUT_PART="$(run_target)"; ST_PART=$?
rm -f "$WORK/partition-fails"
check "a partition list that could not be set does not fail the setup" "$ST_PART" "0"
check "but it says so, rather than leaving the dialog unexplained" \
    "$(printf '%s' "$OUT_PART" | grep -ci "partition")" "1"

# 3. THE ALREADY PRESENT PATH must reach the person who ran this BECAUSE builds
#    are prompting. Telling them "nothing to do" and stopping leaves them facing
#    the same dialog with no way to learn why (L109).
reset_calls
printf '  1) ABC "Ovation Local Signing"\n     1 valid identities found\n' > "$WORK/identities"
OUT_EXISTS="$(run_target)"
check "an existing identity still explains what to do if builds are prompting" \
    "$(printf '%s' "$OUT_EXISTS" | grep -ci "Always Allow")" "1"

# ---------------------------------------------------------------------------
# AN UNATTENDED KEYCHAIN, FOR A MACHINE WITH NOBODY AT IT (ovation#143).
#
# CI builds both configurations, decided by Dan on 2026-09-06, because otherwise
# the shipping build's bundle assertions run on exactly one machine and those are
# the assertions that caught a real security defect in ovation#9. A build needs
# this identity, and every interactive step here is interactive because it acts
# on Dan's LOGIN keychain: the partition list is what raises the password prompt.
#
# A throwaway keychain whose password this script invents has no such problem, so
# the two differ in exactly one place. The seams are the difference, and the
# DEFAULT is unchanged: with no keychain given it is the login keychain and no
# password is ever put on a command line, which is the property the comment
# beside that call exists to protect.
reset_calls
: > "$WORK/identities"
CI_KEYCHAIN="$WORK/ovation-ci.keychain-db"
run_target_ci() {
    OVATION_SECURITY_BIN="$WORK/security" OVATION_OPENSSL_BIN="$WORK/openssl" \
    OVATION_SIGNING_KEYCHAIN="$CI_KEYCHAIN" \
    OVATION_SIGNING_KEYCHAIN_PASSWORD="throwaway" \
        "./$TARGET" 2>&1
}
OUT20="$(run_target_ci)"; ST20=$?
check "an unattended run succeeds" "$ST20" "0"
check "and it creates the keychain it was given" \
    "$(calls_matching "$WORK/security-calls" "create-keychain")" "1"
check "and unlocks it, because a locked keychain cannot be imported into" \
    "$(calls_matching "$WORK/security-calls" "unlock-keychain")" "1"
# The list is READ before it is SET, so the assertion is on the setting call:
# counting every mention would pass on a run that only looked.
check "and puts it on the search list, or codesign will not find the identity" \
    "$(calls_matching "$WORK/security-calls" "list-keychains -d user -s")" "1"
check "and it imports into that keychain rather than the login one" \
    "$(calls_matching "$WORK/security-calls" "import.*ovation-ci")" "1"
check "and the partition list is set with the password it invented" \
    "$(calls_matching "$WORK/security-calls" "set-key-partition-list.*-k throwaway")" "1"
check "and the login keychain is never touched" \
    "$(calls_matching "$WORK/security-calls" "login.keychain")" "0"

# THE DEFAULT IS UNCHANGED, and this is the assertion that keeps it that way.
# `-k <password>` on Dan's login keychain would put it in the process table, the
# shell history and any transcript, which is why that call deliberately has no
# password and lets macOS ask him directly.
reset_calls
: > "$WORK/identities"
run_target >/dev/null 2>&1
check "with no keychain given, no keychain is created" \
    "$(calls_matching "$WORK/security-calls" "create-keychain")" "0"
check "and no password is ever put on the partition list command line" \
    "$(calls_matching "$WORK/security-calls" "set-key-partition-list.*-k ")" "0"

harness_end
