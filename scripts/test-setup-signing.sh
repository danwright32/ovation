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
harness_begin "setup-signing tests" 10

TARGET="scripts/setup-signing.sh"
require_target "$TARGET"

WORK="$(mktemp -d)"
if [ -z "${WORK:-}" ] || [ ! -d "$WORK" ]; then
    echo "REFUSED: could not create a temp directory, so nothing was checked"
    exit 1
fi
harness_on_exit 'rm -rf "$WORK"'

# A stub standing in for /usr/bin/security. It records what it was asked to do,
# so the test can assert the script did NOT reach the creating steps when the
# identity was already there.
make_security() {
    cat > "$WORK/security" <<STUB
#!/bin/bash
echo "\$@" >> "$WORK/security-calls"
case "\$1" in
  find-identity) cat "$WORK/identities" ;;
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
reset_calls
printf '     0 valid identities found\n' > "$WORK/identities"
OUT3="$(run_target)"; ST3=$?
check "an absent identity reaches the trust step" \
    "$(calls_matching "$WORK/security-calls" "add-trusted-cert")" "1"

# 4. AND THE PART THAT MATTERS. After trying to create it, the identity is still
#    not there. That must be an ERROR, not a cheerful finish: a setup script that
#    reports success while the thing it set up does not exist is worse than one
#    that fails, because the next step trusts it (L98, L12).
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

harness_end
