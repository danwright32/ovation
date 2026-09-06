#!/usr/bin/env bash
# Ported-From: danwright32/downbeat Downbeat/setup-signing.sh @ 38549d8362428bc4a8a4839a66c5d457dde87b93
#
# One time setup: create a stable, self signed code signing identity for local
# Ovation builds. RUN THIS ONCE. It asks for your login password in a system
# prompt, which is why it is a script you run rather than something
# build-install.sh does for you.
#
# WHY OVATION NEEDS IT, which is NOT the reason the source has one.
#
# Downbeat's copy is framed as an experiment about notifications (downbeat#306).
# Ovation's reason is folder permission grants. build-install.sh otherwise ad hoc
# signs the app, which mints a NEW code identity on every install, and macOS keys
# folder grants to that identity, so an ad hoc build re prompts for access
# already granted after every single rebuild.
#
# PRD 5.29 has Ovation writing dated backups to "a folder Dan chooses", and plan
# 1.8 is where it first asks. A backup feature that asks permission again after
# every rebuild is one he stops trusting, and the backups are the only copy of a
# seven year tax record. So this lands BEFORE 1.8, not after it.
#
# It also reopens a question Ovation may answer differently from Overture, which
# is recorded in ovation#9 rather than inherited: Overture stores Gmail tokens in
# a 0600 file rather than the Keychain, and its own comment gives the reason as
# ad hoc signing making Keychain ACLs churn, calling Keychain hardening "a
# tracked follow up for a stably signed build". Ovation is stably signed from
# here, so that reason may not apply to it.
#
# DIFFERENCES FROM THE SOURCE, per docs/PORT-DISCIPLINE.md:
#   IDENTITY            "Ovation Local Signing", matching the convention three
#                       siblings already follow, each distinct so the signer of a
#                       given app is identifiable.
#   passphrase          "ovation". Throwaway, used only to move the key through a
#                       PKCS#12 file into the keychain seconds later.
#   -days 3650          KEPT, and re-checked rather than inherited: Ovation is a
#                       SEVEN year tax record, and ten years outlives it.
#   seams               ADDED. The source has none and is therefore untestable.
#                       OVATION_SECURITY_BIN and OVATION_OPENSSL_BIN let
#                       scripts/test-setup-signing.sh exercise every branch
#                       without touching the real keychain (L2).
#   header              The source's notification narrative is NOT carried, since
#                       it is a different app's reason and would read here as
#                       Ovation's.
#
# Usage: scripts/setup-signing.sh
set -euo pipefail

IDENTITY="Ovation Local Signing"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
SECURITY="${OVATION_SECURITY_BIN:-/usr/bin/security}"
OPENSSL="${OVATION_OPENSSL_BIN:-openssl}"

# CARRIED FROM THE SOURCE AS A BEHAVIOURAL FIX, not as a value (downbeat#369,
# L183). The listing is CAPTURED and matched with a glob rather than piped into
# `grep -q`, which exits on the first match and leaves `security` writing into a
# closed pipe. Under `pipefail` that reports failure ON A MATCH, so an identity
# that EXISTS would read as absent and this script would try to create a second
# one every time. A table of constants would not have carried this across.
identity_exists() {
  local identities
  identities="$("$SECURITY" find-identity -v -p codesigning 2>/dev/null)"
  case "$identities" in
    *"$IDENTITY"*) return 0 ;;
    *) return 1 ;;
  esac
}

if identity_exists; then
  echo "==> Identity '$IDENTITY' already exists. Nothing to do."
  # Somebody re-running this is usually somebody whose builds are prompting.
  # "Nothing to do" and nothing else leaves them facing the same dialog with no
  # way to learn why (L109).
  echo "    If builds are stopping at a keychain dialog, that dialog is asking to"
  echo "    use this key. Answer 'Always Allow', NOT 'Allow': Allow grants it once"
  echo "    and it returns on every subsequent build."
  exit 0
fi

echo "==> Creating self signed code signing certificate: $IDENTITY"
TMP="$(mktemp -d)"
if [ -z "${TMP:-}" ] || [ ! -d "$TMP" ]; then
  echo "Error: could not create a temp directory. Nothing was changed." >&2
  exit 1
fi
trap 'rm -rf "$TMP"' EXIT

# Config file form, which works with the system LibreSSL, which lacks -addext.
cat > "$TMP/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

"$OPENSSL" req -new -x509 -days 3650 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -config "$TMP/openssl.cnf" >/dev/null 2>&1

# CARRIED FROM THE SOURCE AS A BEHAVIOURAL FIX. `-legacy` (OpenSSL 3) forces
# 3DES/RC2 plus a SHA1 MAC. Without it, OpenSSL 3 writes a SHA-256 MAC that
# Apple's `security import` cannot verify and wrongly reports as "MAC
# verification failed (wrong password?)", which sends you looking at the
# passphrase. The fallback is for LibreSSL and older OpenSSL, which reject
# `-legacy`.
"$OPENSSL" pkcs12 -export -legacy \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/identity.p12" -passout pass:ovation -name "$IDENTITY" >/dev/null 2>&1 \
|| "$OPENSSL" pkcs12 -export \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/identity.p12" -passout pass:ovation -name "$IDENTITY" >/dev/null 2>&1

"$SECURITY" import "$TMP/identity.p12" -k "$LOGIN_KEYCHAIN" -P ovation \
  -T /usr/bin/codesign -A >/dev/null

# THE PARTITION LIST, WHICH IS THE ACTUAL GATE. ovation#24.
#
# The `-T /usr/bin/codesign -A` above exists precisely to pre-authorise codesign
# so a build never raises a dialog. IT DID NOT WORK. Measured 2026-09-06: Dan ran
# this script, it reported success, the identity was genuinely created, and the
# first build then blocked on a macOS keychain dialog for several minutes with
# nothing saying so. The build printed nothing unusual and simply did not finish;
# the only evidence was SecurityAgent sitting beside a waiting codesign. A wait
# that cannot be told from a hang is the worse of the two (L110).
#
# Since macOS Sierra the access control that actually decides is the key's
# PARTITION LIST, which neither -A nor -T sets. This sets it.
#
# NO PASSWORD IS PASSED HERE, and that is deliberate rather than an oversight.
# `-k <password>` would put Dan's login keychain password on a command line,
# where it reaches the process table, the shell history and any transcript. Left
# off, `security` asks him for it directly, which is the only place it belongs.
echo "==> Authorising codesign to use the key (macOS will ask for your login password)"
if ! "$SECURITY" set-key-partition-list -S apple-tool-:,apple:,codesign: -s \
    "$LOGIN_KEYCHAIN" >/dev/null 2>&1; then
  # NOT a failure of the setup. The identity exists and is usable; what is
  # missing is the pre-authorisation, so builds will prompt. Saying nothing here
  # would leave that dialog unexplained, which is the whole defect this fixes
  # (L11).
  PARTITION_SET=no
  echo "    The partition list could not be set (a wrong password, or a keychain that"
  echo "    refused). The identity is still fine. Builds will raise the dialog below."
else
  PARTITION_SET=yes
fi

echo "==> Trusting the certificate for code signing (enter your login password if prompted)"
"$SECURITY" add-trusted-cert -r trustRoot -p codeSign -k "$LOGIN_KEYCHAIN" "$TMP/cert.pem"

# READ IT BACK. A command that ran is not an identity that exists, and a setup
# script reporting success while the thing it set up is absent is worse than one
# that fails, because everything after it trusts the report (L12, L98).
if identity_exists; then
  echo "==> Done. '$IDENTITY' is in your login keychain."
  echo "    Next: tell Claude, and project.yml is pointed at it. Until then Ovation"
  echo "    still ad hoc signs, so nothing is broken by waiting."
  echo
  # SAID WHATEVER THE PARTITION LIST DID. The old ending implied you were
  # finished, and the next build then stopped for minutes with no explanation.
  # This is the half that holds even if the half above turns out not to work on
  # some machine, which is why it is unconditional (L400).
  echo "    ONE MORE THING. Your first build may still stop at a keychain dialog"
  echo "    asking to use this key. That is normal and it is not an error."
  echo "    Answer 'Always Allow', NOT 'Allow': Allow grants it once and the dialog"
  echo "    comes back on every subsequent build."
  echo "    A build waiting on it looks exactly like a slow build, so if one seems"
  echo "    to hang, look for the dialog before looking at anything else."
else
  echo "Error: the identity was not created. Nothing above should be trusted." >&2
  echo "       Check the output for what security or openssl reported." >&2
  exit 1
fi
