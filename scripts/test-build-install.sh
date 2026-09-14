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
harness_begin "build-install tests" 40

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

# A STAND IN FOR lsregister, and EVERY install below goes through it (ovation#264).
#
# The real one edits the Launch Services database the whole Mac opens apps by, so
# a case that reached it would unregister Dan's own build copies (L2). This one
# answers `-dump` from a fixture, remembers every `-u` so a later dump no longer
# lists that bundle, and logs every call so a case can assert what was asked.
#
# STUB_KEEP_REGISTERED=1 makes it ignore `-u`, the shape of an unregister that
# did not take. STUB_DUMP_FAILS=1 makes `-dump` answer nothing and exit 1.
LSREGISTER="$WORK/lsregister"
LS_FIXTURE="$WORK/ls-dump.txt"
LS_CALLS="$WORK/ls-calls.log"
LS_GONE="$WORK/ls-unregistered.txt"
cat > "$LSREGISTER" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$LS_CALLS"
case "$1" in
    -dump)
        [ -n "${STUB_DUMP_FAILS:-}" ] && exit 1
        python3 - "$LS_FIXTURE" "$LS_GONE" <<'PY'
import re, sys
gone = set()
try:
    gone = set(open(sys.argv[2], encoding="utf-8").read().splitlines())
except OSError:
    pass
for record in re.split(r"(?m)^-{10,}\n", open(sys.argv[1], encoding="utf-8").read()):
    path = re.search(r"(?m)^path: +(.*) \(0x[0-9a-f]+\)$", record)
    if path and path.group(1) in gone:
        continue
    print("-" * 80)
    print(record, end="")
PY
        ;;
    -u)
        [ -n "${STUB_KEEP_REGISTERED:-}" ] || printf '%s\n' "$2" >> "$LS_GONE"
        ;;
esac
exit 0
STUB
chmod +x "$LSREGISTER"

# One bundle record, in the shape `lsregister -dump` printed for the installed app
# on 2026-09-13, with the path and identifier replaced and nothing else (L48).
ls_record() {
    printf -- '--------------------------------------------------------------------------------\n'
    printf 'bundle id:                  Ovation (0x17b8)\n'
    printf 'container:                  / (0x4)\n'
    printf 'mount state:                mounted\n'
    printf 'path:                       %s (0x27b0)\n' "$1"
    printf 'directory:                  %s\n' "$(dirname "$1")"
    printf 'name:                       Ovation\n'
    printf 'identifier:                 %s\n' "$2"
    printf 'codeInfoID:                 %s\n' "$2"
    printf 'executable:                 Contents/MacOS/Ovation\n'
    printf '\n'
}

DERIVED="$WORK/Library/Developer/Xcode/DerivedData/Ovation-abc/Build/Products"
OLD_COPY="$WORK/Old Builds/Ovation.app"
write_ls_fixture() {
    {
        ls_record "$DEST" com.danwright.ovation
        ls_record "$DERIVED/Release/Ovation.app" com.danwright.ovation
        ls_record "$DERIVED/Debug/Ovation.app" com.danwright.ovation.debug
        # A path with a space in it, which a word split would cut in two.
        ls_record "$OLD_COPY" com.danwright.ovation
        # Not Ovation, whatever the path or the name say.
        ls_record "$WORK/Applications/Overture.app" com.danwright.overture
        ls_record "$WORK/Elsewhere/Ovation.app" com.example.ovation
        # An identifier that merely STARTS like Ovation's is somebody else's.
        ls_record "$WORK/Elsewhere/OvationHelper.app" com.danwright.ovationhelper
    } > "$LS_FIXTURE"
    : > "$LS_CALLS"
    rm -f "$LS_GONE"
}
write_ls_fixture

run_install() {
    OVATION_BUILT_APP="${1:-$BUILT/Ovation.app}" \
    OVATION_INSTALL_DEST="$DEST" \
    OVATION_REPO_ROOT="$REPO" \
    OVATION_DATA_DIR="$DATA" \
    OVATION_SKIP_BUILD=1 \
    OVATION_CODESIGN=true \
    OVATION_XATTR=true \
    OVATION_LSREGISTER="$LSREGISTER" \
    LS_FIXTURE="$LS_FIXTURE" LS_CALLS="$LS_CALLS" LS_GONE="$LS_GONE" \
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
OVATION_CODESIGN=true OVATION_XATTR=true OVATION_LSREGISTER="$LSREGISTER" \
LS_FIXTURE="$LS_FIXTURE" LS_CALLS="$LS_CALLS" LS_GONE="$LS_GONE" \
"./$TARGET" >/dev/null 2>&1
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

# ---------------------------------------------------------------------------
# 10. OPENING OVATION BY NAME MUST OPEN THE INSTALLED COPY (ovation#264).
#
# On 2026-09-13, straight after an install, Launch Services still held two build
# copies from Xcode's DerivedData, and opening Ovation by name started the DEBUG
# one, which keeps its own data folder and preferences. A backup folder chosen in
# it was invisible to the installed app, and once invoices exist, work entered in
# a build copy lands in a database the installed app never reads (L55, L83).
#
# So after installing, every Ovation bundle Launch Services knows about anywhere
# but the destination is unregistered, Release and Debug identities alike, and
# the database is READ BACK to prove it took rather than trusting the calls'
# exit codes (L184).
# ---------------------------------------------------------------------------
write_ls_fixture
OUT10="$(run_install)"; ST10=$?
unregistered() { grep -c "^-u $1\$" "$LS_CALLS" || true; }
check "an install whose other copies all unregister exits 0" "$ST10" "0"
check "the Release build copy in DerivedData is unregistered" \
    "$(unregistered "$DERIVED/Release/Ovation.app")" "1"
check "the Debug build copy is unregistered too, it is the one that opened" \
    "$(unregistered "$DERIVED/Debug/Ovation.app")" "1"
check "a copy whose path holds a space is unregistered whole" \
    "$(unregistered "$OLD_COPY")" "1"
check "the installed copy itself is NOT unregistered" "$(unregistered "$DEST")" "0"
check "and it is registered, so Launch Services has it to open" \
    "$(grep -c "^-f $DEST\$" "$LS_CALLS" || true)" "1"
check "an app that is not Ovation is left alone" \
    "$(grep -c "Overture.app\|com.example\|OvationHelper" "$LS_CALLS" || true)" "0"
check "and the install says how many other copies it removed" \
    "$(printf '%s' "$OUT10" | grep -c '3 other cop')" "1"

# 11. AN UNREGISTER THAT DID NOT TAKE is said, by path, and is not a clean exit.
#     The bundle is installed and recorded, so the words must not say otherwise
#     (L11), but opening by name can still start the wrong copy.
write_ls_fixture
OUT11="$(STUB_KEEP_REGISTERED=1 run_install)"; ST11=$?
check "a copy still registered after the install exits 3" "$ST11" "3"
check "and names the copy that is still registered" \
    "$(printf '%s' "$OUT11" | grep -c "$DERIVED/Debug/Ovation.app")" "1"
check "and says the install itself still happened" \
    "$(printf '%s' "$OUT11" | grep -c 'Installed and recorded')" "1"
check "and the bundle and record really are in place" \
    "$([ -d "$DEST" ] && [ -f "$DATA/installed-build.json" ] && echo yes || echo no)" "yes"

# 12. A DATABASE THAT CANNOT BE READ IS NOT ONE WITH NOTHING IN IT (L98, L215).
write_ls_fixture
OUT12="$(STUB_DUMP_FAILS=1 run_install)"; ST12=$?
check "an unreadable Launch Services database exits 3, not 0" "$ST12" "3"
check "and says it could not check, rather than that no copies were found" \
    "$(printf '%s' "$OUT12" | grep -c 'could not read Launch Services')" "1"
check "and unregisters nothing it could not see" \
    "$(grep -c '^-u ' "$LS_CALLS" || true)" "0"

harness_end
