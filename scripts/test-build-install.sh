#!/bin/bash
# The installer must record what it installed, record it only after the bundle
# verifiably landed, and never let an absent fact read as a reassuring one.
#
# ovation#10. The record is the only thing that can tell Ovation it has fallen
# behind: the app cannot run git and cannot know which checkout produced the
# bundle in /Applications. Downbeat's copy of this exists because an install sat
# six hours behind main with nothing noticing.
#
# Every case here runs against stub builds and throwaway directories. Nothing
# touches /Applications and nothing runs a real xcodebuild (L2).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "build-install tests" 25

TARGET="scripts/build-install.sh"
require_target "$TARGET"
harness_temp_dir WORK

# A stub bundle standing in for a built Ovation.app.
make_built_app() {
    local d="$1/Ovation.app/Contents/MacOS"
    mkdir -p "$d"
    printf '#!/bin/bash\nsleep 30\n' > "$d/Ovation"
    chmod +x "$d/Ovation"
    printf 'built\n' > "$1/Ovation.app/Contents/Info.plist"
}

# A throwaway git repo standing in for Ovation's checkout.
make_repo() {
    local r="$1"; mkdir -p "$r"
    ( cd "$r" && git init -q -b main && git config user.email t@t && git config user.name t \
      && echo one > f.txt && git add f.txt && git commit -qm one ) >/dev/null 2>&1
}

BUILT="$WORK/built"; make_built_app "$BUILT"
REPO="$WORK/repo"; make_repo "$REPO"
DEST="$WORK/Applications/Ovation.app"
DATA="$WORK/data"
mkdir -p "$WORK/Applications" "$DATA"

run_install() {
    OVATION_BUILT_APP="${1:-$BUILT/Ovation.app}" \
    OVATION_INSTALL_DEST="$DEST" \
    OVATION_REPO_ROOT="$REPO" \
    OVATION_DATA_DIR="$DATA" \
    OVATION_SKIP_BUILD=1 \
    OVATION_CODESIGN=true \
    OVATION_XATTR=true \
        "./$TARGET" 2>&1
}
record() { cat "$DATA/installed-build.json" 2>/dev/null; }
field() { printf '%s' "$(record)" | sed -n "s/.*\"$1\":\"\\([^\"]*\\)\".*/\\1/p"; }
has_key() { printf '%s' "$(record)" | grep -c "\"$1\":" || true; }

# 1. A successful install lands the bundle AND writes the record.
OUT1="$(run_install)"; ST1=$?
check "a successful install exits 0" "$ST1" "0"
check "and the bundle actually landed" "$([ -d "$DEST" ] && echo yes || echo no)" "yes"
check "and a record was written" "$([ -f "$DATA/installed-build.json" ] && echo yes || echo no)" "yes"

# 2. The record carries the UNION of what the two siblings write. Neither sibling
#    writes this set: Overture omits dirtyFiles, Downbeat omits provenance.
check "the record names the commit" "$(field commit)" "$(git -C "$REPO" rev-parse HEAD)"
check "and the commit date" "$([ -n "$(field commitDate)" ] && echo present || echo missing)" "present"
check "and the repo path, without which nothing can find the code" \
    "$(field repoPath)" "$REPO"
check "and the provenance, the line of work it came from" "$(field provenance)" "main"
check "and the dirty file count, as a number" "$(has_key dirtyFiles)" "1"
check "and a version, so a later shape change is readable" "$(has_key version)" "1"

# 3. A CLEAN tree records ZERO, and that zero is real, not a default.
check "a clean checkout records zero dirty files" \
    "$(printf '%s' "$(record)" | sed -n 's/.*"dirtyFiles":\([0-9]*\).*/\1/p')" "0"

# 4. A DIRTY tree records the real count. The record naming a commit while saying
#    nothing about uncommitted work is how a build from work in progress looks
#    identical to one from that commit.
echo changed > "$REPO/f.txt"; echo untracked > "$REPO/g.txt"
run_install >/dev/null 2>&1
check "a dirty checkout records the real count, not zero" \
    "$(printf '%s' "$(record)" | sed -n 's/.*"dirtyFiles":\([0-9]*\).*/\1/p')" "2"
( cd "$REPO" && git checkout -q -- f.txt && rm -f g.txt )

# 5. THE ONE THAT MATTERS MOST. A repository that CANNOT BE ASKED must omit the
#    field entirely, never write 0 and never write "main". Absent means NOT
#    RECORDED. Writing the reassuring value would have an old record vouch for
#    something nothing checked (L11, L98).
NOTREPO="$WORK/notarepo"; mkdir -p "$NOTREPO"
OVATION_BUILT_APP="$BUILT/Ovation.app" OVATION_INSTALL_DEST="$DEST" \
OVATION_REPO_ROOT="$NOTREPO" OVATION_DATA_DIR="$DATA" OVATION_SKIP_BUILD=1 \
OVATION_CODESIGN=true OVATION_XATTR=true "./$TARGET" >/dev/null 2>&1
check "an unaskable repository OMITS dirtyFiles rather than recording zero" \
    "$(has_key dirtyFiles)" "0"
check "and OMITS provenance rather than recording main" "$(has_key provenance)" "0"
check "and still records what it could, so the record is not lost entirely" \
    "$(has_key repoPath)" "1"

# 6. THE ORDERING. The record must never describe an install that did not happen
#    (L12). A build that is not there must leave the previous record untouched.
printf '{"version":1,"commit":"SENTINEL","commitDate":"x","repoPath":"y"}\n' > "$DATA/installed-build.json"
OUT6="$(run_install "$WORK/no-such-build/Ovation.app")"; ST6=$?
check "a missing build refuses" "$([ "$ST6" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
check "and it does NOT overwrite the previous record" "$(field commit)" "SENTINEL"
check "and it says what was missing" \
    "$(printf '%s' "$OUT6" | grep -c "no-such-build")" "1"

# 7. Running copies are identified by EXACT EXECUTABLE PATH, never by name.
#    Two builds of this app run at once as a matter of course, and asking macOS
#    to quit "Ovation" is what killed a live Overture on 2026-08-04 while an
#    installer was aimed at a different bundle.
PIDS_OUT="$(printf '111 /other/Ovation.app/Contents/MacOS/Ovation\n222 %s/Contents/MacOS/Ovation\n333 %s/Contents/MacOS/OvationHelper\n' "$DEST" "$DEST" \
    | OVATION_PIDS_ONLY="$DEST" bash -c '. ./scripts/build-install.sh --source-only 2>/dev/null; ovation_pids_from_table "$OVATION_PIDS_ONLY/Contents/MacOS/Ovation"')"
check "a different bundle with the same app name is NOT matched" \
    "$(printf '%s' "$PIDS_OUT" | grep -c '^111$')" "0"
check "the exact bundle IS matched" \
    "$(printf '%s' "$PIDS_OUT" | grep -c '^222$')" "1"
check "and a helper whose path merely starts the same is NOT matched" \
    "$(printf '%s' "$PIDS_OUT" | grep -c '^333$')" "0"

# 8. The record is JSON that a reader can actually decode.
run_install >/dev/null 2>&1
check "the record parses as JSON" \
    "$(python3 -c 'import json,sys;json.load(open(sys.argv[1]));print("ok")' "$DATA/installed-build.json" 2>/dev/null)" "ok"
check "and dirtyFiles is a NUMBER, not a string, so a reader cannot compare it to text" \
    "$(python3 -c 'import json,sys;print(type(json.load(open(sys.argv[1])).get("dirtyFiles")).__name__)' "$DATA/installed-build.json" 2>/dev/null)" "int"

# ---------------------------------------------------------------------------
# 9. THE RECORD MUST DESCRIBE THE REPOSITORY IT WAS HANDED, and `git -C <repo>`
# is not enough to guarantee that: an inherited GIT_DIR BEATS the -C, so every
# question is answered by whatever GIT_DIR names instead.
#
# This is the record that says which code an installed app came from, so getting
# it from the wrong repository is not a cosmetic fault: the app reports a branch
# it was not built from and a dirty count belonging to somewhere else, and both
# look entirely plausible.
#
# Git EXPORTS GIT_DIR to its hooks, and this suite runs inside the pre-push hook.
# Found on 2026-09-08: this suite passed run by hand and failed five assertions
# inside the gate, reporting the pushing worktree's own branch and its 188 dirty
# files against a throwaway fixture repo that had one file and was on main.
#
# The fixture points GIT_DIR at a DIFFERENT real repository, this one, so a
# regression cannot pass by the two happening to agree.
GITDIR_OUT="$(GIT_DIR="$PWD/.git" GIT_WORK_TREE="$PWD" run_install)"
check "an inherited GIT_DIR does not change which repository is recorded" \
    "$(field repoPath)" "$REPO"
check "and the provenance is still the fixture's line of work" \
    "$(field provenance)" "main"
check "and the dirty count is still the fixture's own" \
    "$(printf '%s' "$(record)" | sed -n 's/.*"dirtyFiles":\([0-9]*\).*/\1/p')" "0"

harness_end
