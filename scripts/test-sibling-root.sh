#!/bin/bash
# The suite for scripts/lib/repo-git.sh, and for every script that finds the
# sibling checkouts through it.
#
# ovation#314. The plan claims check took the parent of the checkout it ran in as
# the folder holding Downbeat and Overture. From a worktree under
# `.claude/worktrees/` that parent is the worktrees folder, so the siblings were
# never found, the check answered CANNOT MEASURE, and the push gate lets that
# through by design. Nearly every push is made from a worktree, so the gate had
# quietly stopped checking the plan at all (L668, L98). Two other scripts found
# the siblings a third and fourth way, from a folder name typed under the home
# directory, which is right only until something moves (L153).
#
# So there is ONE way, in the library, and this suite holds it from both ends:
# the library answers correctly from a primary checkout, from a worktree, and
# under an inherited GIT_DIR naming another repository, and each consumer is run
# FROM A WORKTREE COPY of itself, which is the layout that was broken. The scan
# at the end fails on the next hand rolled copy (L613).
#
# NOTHING REAL IS READ. Every consumer run sets HOME to a throwaway folder and
# clears the sibling seams, so a default that still pointed under the real home
# directory resolves to an empty folder rather than to Dan's checkouts (L2).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "sibling root tests" 14

LIB="scripts/lib/repo-git.sh"
for target in scripts/check-plan-claims.sh scripts/check-ported-artifacts.sh \
              scripts/check-sibling-installs.sh scripts/lib/json-field.sh; do
    require_target "$target"
done
harness_temp_dir WORK

# An estate laid out as Dan's is: a primary checkout, a worktree inside it, and
# (later, per case) the siblings beside the primary checkout. Resolved with -P,
# because git reports real paths and the temp folder sits behind a symlink.
ESTATE="$(mkdir -p "$WORK/estate" && cd -P "$WORK/estate" && pwd)"
MAIN="$ESTATE/Ovation"
WT="$MAIN/.claude/worktrees/wt"
(
    git init -q -b main "$MAIN"
    git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one
    git -C "$MAIN" worktree add -q -b wt "$WT"
) >/dev/null 2>&1
# A repository that has nothing to do with the estate, for an inherited GIT_DIR
# to name.
STRANGER="$WORK/elsewhere/Stranger"
git init -q -b main "$STRANGER" >/dev/null 2>&1
PLAIN="$WORK/plain"
mkdir -p "$PLAIN" "$WORK/home"

root_from() { bash -c '. "$1" && sibling_root "$2"' _ "$LIB" "$1" 2>/dev/null; }
refusal_from() { bash -c '. "$1" && sibling_root "$2"' _ "$LIB" "$1" 2>"$WORK/err"; }
toplevel_via_clean_git() {
    bash -c '. "$1" && clean_git -C "$2" rev-parse --show-toplevel' _ "$LIB" "$1" 2>/dev/null
}

# 1. THE LIBRARY.
check "the library exists" "$([ -f "$LIB" ] && echo yes)" "yes"
check "from the primary checkout, the siblings live beside it" "$(root_from "$MAIN")" "$ESTATE"
check "from a worktree, they live beside the primary checkout rather than beside the worktree" \
    "$(root_from "$WT")" "$ESTATE"
# Git exports GIT_DIR to its hooks, and an inherited one beats `git -C`, so a
# lookup that did not clear it would answer about whatever it names.
check "and still when an inherited GIT_DIR names another repository, as inside a hook" \
    "$(GIT_DIR="$STRANGER/.git" root_from "$WT")" "$ESTATE"
out="$(refusal_from "$PLAIN")"
check "outside any repository it refuses rather than guessing a folder" "$?:$out" "1:"
check "and says why" "$(grep -c 'is not inside a git repository' "$WORK/err")" "1"
check "clean_git answers about the repository it is pointed at, not an inherited GIT_DIR" \
    "$(GIT_DIR="$STRANGER/.git" toplevel_via_clean_git "$WT")" "$WT"

# 2. EACH CONSUMER, RUN FROM A WORKTREE COPY OF ITSELF. The library is copied only
# if it exists, so before it did these fail on the defect rather than on a copy.
mkdir -p "$WT/scripts/lib"
cp scripts/check-plan-claims.sh scripts/check-ported-artifacts.sh \
   scripts/check-sibling-installs.sh "$WT/scripts/"
cp scripts/lib/json-field.sh "$WT/scripts/lib/"
[ -f "$LIB" ] && cp "$LIB" "$WT/scripts/lib/"

printf 'nothing cited here\n' > "$WORK/plan.md"
plan_from_wt() {
    env -u OVATION_SIBLING_ROOT HOME="$WORK/home" OVATION_PLAN="$WORK/plan.md" \
        OVATION_SIBLING_INSTALL_CHECK="$WORK/none.sh" OVATION_BOOKING_EXPORT="$WORK/none.json" \
        OVATION_EXPORT_RECORDS="$WORK/none.md" OVATION_LIVE_EXPORT="$WORK/none.json" \
        python3 "$WT/scripts/check-plan-claims.sh" 2>&1
}
# The refusal is produced first, in this same estate, so the case after it cannot
# pass merely because the check never gets as far as looking (L159).
check "the plan check from a worktree with no siblings names the folder holding the primary checkout" \
    "$(plan_from_wt | grep -c "is not under ${ESTATE},")" "1"
mkdir -p "$ESTATE/Downbeat" "$ESTATE/Overture"
check "and with the siblings there it finds them, rather than reporting it could not measure" \
    "$(plan_from_wt | grep -cE 'is not under|Traceback')" "0"

mkdir -p "$WORK/tree"
printf '# %s: nobody/nothing a.sh @ %s\n' "Ported""-From" \
    0123456789abcdef0123456789abcdef01234567 > "$WORK/tree/ported.sh"
ported_from_wt() {
    env -u OVATION_SIBLING_SEARCH_ROOTS HOME="$WORK/home" OVATION_PORT_SCAN_ROOT="$WORK/tree" \
        bash "$WT/scripts/check-ported-artifacts.sh" 2>&1
}
check "the ported files check searches the folder holding the primary checkout, even from a worktree" \
    "$(ported_from_wt | grep -c "roots searched: ${ESTATE}\$")" "1"

printf '{"commit": "0123456789abcdef0123456789abcdef01234567", "provenance": "main"}\n' \
    > "$WORK/record.json"
installs_from_wt() {
    env -u OVATION_OVERTURE_REPO HOME="$WORK/home" OVATION_OVERTURE_BUILD_RECORD="$WORK/record.json" \
        OVATION_DOWNBEAT_EXPORT="$WORK/none.json" bash "$WT/scripts/check-sibling-installs.sh" 2>&1
}
check "the installs check, with no Overture checkout beside the primary one, says it is not there" \
    "$(installs_from_wt | grep -c "is not beside Ovation's primary checkout")" "1"
git init -q -b main "$ESTATE/Overture" >/dev/null 2>&1
check "and with one there it looks inside it, even from a worktree" \
    "$(installs_from_wt | grep -c 'is not in that checkout')" "1"

# 3. THE GUARD. Locating a sibling by a typed folder name or by the parent of the
# running checkout, or clearing git's inherited environment by hand, belongs in
# the library and nowhere else. Suites are exempt, because they name all three to
# build fixtures and to write this very scan.
scan() {
    grep -rnE 'Non-icloudDocuments|dirname\(REPO\)|env -u GIT_DIR' "$1" \
        --include='*.sh' --include='*.py' 2>/dev/null \
        | grep -vE '/lib/repo-git\.sh:|/test-[^/]*\.sh:'
}
check "no script outside the library locates a sibling or clears git's environment by hand" \
    "$(scan scripts | wc -l | tr -d ' ')" "0"
mkdir -p "$WORK/scan"
printf 'ROOT="$HOME/%s/Apps"\n' "Non-icloudDocuments" > "$WORK/scan/a.sh"
printf 'x = os.path.%s(REPO)\n' "dirname" > "$WORK/scan/b.py"
printf 'env -u %s git "$@"\n' "GIT_DIR" > "$WORK/scan/c.sh"
check "and the scan catches each of the three shapes" "$(scan "$WORK/scan" | wc -l | tr -d ' ')" "3"

harness_end
