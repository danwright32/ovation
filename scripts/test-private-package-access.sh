#!/bin/bash
# The suite for scripts/configure-private-package-access.sh.
#
# ovation#424, ovation#427. The thing worth testing is the REFUSAL and the
# silence: that a missing credential is named as a missing credential rather than
# surfacing later as a missing module, and that the token never appears in
# anything this prints.
#
# EVERY CASE RUNS AGAINST A THROWAWAY HOME, so `git config --global` writes into
# a temporary directory and no case can touch the real machine's git config (L2).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"

TARGET="scripts/configure-private-package-access.sh"

harness_begin "private package access tests" 16
require_target "$TARGET"
harness_temp_dir WORK

# A token shaped like a real one, so a leak would be visible if one happened.
FAKE_TOKEN="ghp_NOTAREALTOKEN000000000000000000000000"

run_in() {
    # $1 = a label for the throwaway HOME, the rest is the environment.
    local home="$WORK/$1"; shift
    mkdir -p "$home"
    env HOME="$home" "$@" bash "$TARGET" 2>&1
}
status_in() {
    local home="$WORK/$1"; shift
    mkdir -p "$home"
    env HOME="$home" "$@" bash "$TARGET" >/dev/null 2>&1
    printf '%s' "$?"
}

# ---------------------------------------------------------------------------
# A developer machine is never touched.
# ---------------------------------------------------------------------------
check "outside CI it does nothing and exits 0" \
    "$(status_in local CI= OVATION_ALLOW_LOCAL_GIT_AUTH= BACKSTAGE_READ_TOKEN="$FAKE_TOKEN")" "0"
check "and says so rather than being silent" \
    "$(run_in local2 CI= OVATION_ALLOW_LOCAL_GIT_AUTH= BACKSTAGE_READ_TOKEN="$FAKE_TOKEN" | grep -c '^SKIPPED')" "1"
check "and writes NOTHING into that machine's git config" \
    "$(run_in local3 CI= OVATION_ALLOW_LOCAL_GIT_AUTH= BACKSTAGE_READ_TOKEN="$FAKE_TOKEN" >/dev/null; \
       [ -f "$WORK/local3/.gitconfig" ] && printf 'wrote' || printf 'nothing')" "nothing"
check "and it names the override rather than leaving it to be found" \
    "$(run_in local4 CI= OVATION_ALLOW_LOCAL_GIT_AUTH= BACKSTAGE_READ_TOKEN="$FAKE_TOKEN" | grep -c 'OVATION_ALLOW_LOCAL_GIT_AUTH=1')" "1"

# ---------------------------------------------------------------------------
# THE REFUSAL THIS EXISTS FOR: a missing credential, named as one.
# ---------------------------------------------------------------------------
check "in CI with no token it refuses" "$(status_in ci CI=1 BACKSTAGE_READ_TOKEN=)" "1"
check "and names the SECRET rather than the module" \
    "$(run_in ci2 CI=1 BACKSTAGE_READ_TOKEN= | grep -c 'BACKSTAGE_READ_TOKEN is not set')" "1"
check "and says the repository is private, which is WHY a credential is needed" \
    "$(run_in ci3 CI=1 BACKSTAGE_READ_TOKEN= | grep -c 'PRIVATE')" "1"
check "and says explicitly that this is not a missing module" \
    "$(run_in ci4 CI=1 BACKSTAGE_READ_TOKEN= | grep -c 'not a missing module')" "1"
check "and carries the remedy, not just the diagnosis" \
    "$(run_in ci5 CI=1 BACKSTAGE_READ_TOKEN= | grep -c 'contents:read')" "1"
check "and the refusal goes to stderr, where a failing step's reader looks" \
    "$(env HOME="$WORK/ci6" CI=1 BACKSTAGE_READ_TOKEN= bash "$TARGET" 2>/dev/null | grep -c 'REFUSED')" "0"

# ---------------------------------------------------------------------------
# The configuring path, and the silence about the value.
# ---------------------------------------------------------------------------
mkdir -p "$WORK/good"
GOOD="$(run_in good CI=1 BACKSTAGE_READ_TOKEN="$FAKE_TOKEN")"
check "in CI with a token it succeeds" \
    "$(status_in good2 CI=1 BACKSTAGE_READ_TOKEN="$FAKE_TOKEN")" "0"
check "and the token appears NOWHERE in what it printed" \
    "$(printf '%s' "$GOOD" | grep -c "$FAKE_TOKEN")" "0"
check "and it says the token was not printed, so the silence is deliberate" \
    "$(printf '%s' "$GOOD" | grep -c 'never printed')" "1"
check "and github.com fetches are rewritten to an authenticated form" \
    "$(grep -c 'insteadOf' "$WORK/good/.gitconfig" 2>/dev/null)" "1"
check "and the rewrite carries the token, which is the point of it" \
    "$(grep -c "$FAKE_TOKEN" "$WORK/good/.gitconfig" 2>/dev/null)" "1"

# The local override, which is the one way a person asks for their machine to be
# configured. It must WORK, or the escape hatch is decorative (L109).
check "the local override genuinely configures, rather than only being named" \
    "$(run_in override CI= OVATION_ALLOW_LOCAL_GIT_AUTH=1 BACKSTAGE_READ_TOKEN="$FAKE_TOKEN" >/dev/null; \
       grep -c 'insteadOf' "$WORK/override/.gitconfig" 2>/dev/null)" "1"

harness_end
