#!/bin/bash
# The package resolution a build uses must be the one the repository commits
# (ovation#421).
#
# `.gitignore` used to exclude `Ovation.xcodeproj/` wholesale, and SwiftPM writes
# its lock file inside it, so no resolved revision for any package existed in
# version control. An exact `version:` pin resolves a TAG, and a tag is a movable
# ref: without a committed revision, a re-cut tag moves the build with no diff
# anywhere (L25, L496). The file is now committed at the path SwiftPM writes it
# to, and scripts/check-package-resolution.sh refuses when what is on disk, which
# is what the last build resolved, is not what HEAD commits (L422).
#
# SEEN TO FAIL (L1), as the issue asks: a resolution that moves a package's
# revision is asserted to appear as a change to a TRACKED file, and the check is
# asserted to refuse it naming the package. Both remedies the refusal prints are
# then RUN, and the check is asserted to pass after each (L406).
#
# Everything runs in a throwaway repository carrying the real .gitignore, except
# the last section, which asks the real tree whether it commits a resolution and
# whether that resolution agrees with the versions project.yml pins.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "package resolution tests" 31

TARGET="scripts/check-package-resolution.sh"
require_target "$TARGET"
harness_temp_dir WORK

RESOLVED="Ovation.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

# resolution <viewinspector version> <viewinspector revision> [extra pin json]
resolution() {
    cat <<EOF
{
  "originHash" : "e2258ed096008c391de60429bc13ce46a66d538cbef889426f369b68c25e1576",
  "pins" : [
    {
      "identity" : "backstage",
      "kind" : "remoteSourceControl",
      "location" : "https://github.com/danwright32/backstage",
      "state" : {
        "revision" : "515c80694088b2fc8a4ea006eb9ff071320eeb47",
        "version" : "0.3.0"
      }
    },
    {
      "identity" : "viewinspector",
      "kind" : "remoteSourceControl",
      "location" : "https://github.com/nalexn/ViewInspector",
      "state" : {
        "revision" : "$2",
        "version" : "$1"
      }
    }${3:-}
  ],
  "version" : 3
}
EOF
}
COMMITTED_REV="e9a06346499a3a889165647e3f23f8a7b2609a1c"
MOVED_REV="0000000000000000000000000000000000000abc"

REPO="$WORK/repo"
git_in() { git -C "$REPO" -c user.name=Test -c user.email=test@example.invalid "$@"; }
fresh_repo() {
    rm -rf "$REPO"
    mkdir -p "$REPO/$(dirname "$RESOLVED")"
    git init -q -b main "$REPO"
    cp .gitignore "$REPO/.gitignore"
    resolution 0.10.3 "$COMMITTED_REV" > "$REPO/$RESOLVED"
    git_in add .gitignore "$RESOLVED"
    git_in commit -q -m "commit the resolution"
}
run_check() { OVATION_REPO_ROOT="$REPO" "./$TARGET" 2>&1; }
says() { if grep -qF -- "$2" <<< "$1"; then echo yes; else echo no; fi; }

# 1. THE ORDINARY CASE: what the build left is what HEAD commits.
fresh_repo
OUT="$(run_check)"; ST=$?
check "the committed resolution, unchanged on disk, passes" "$ST" "0"
check "and it says which file it compared" "$(says "$OUT" "$RESOLVED")" "yes"

# 2. THE CASE THE ISSUE EXISTS FOR: a resolution that moves a revision. It shows
#    as a change to a tracked file, and the check refuses naming the package and
#    both revisions, so a reader can see what moved without opening the file.
resolution 0.10.3 "$MOVED_REV" > "$REPO/$RESOLVED"
check "a moved revision is a change to a TRACKED file, not only one on disk" \
    "$(git_in status --porcelain -- "$RESOLVED")" " M $RESOLVED"
OUT="$(run_check)"; ST=$?
check "and the check refuses it" "$ST" "1"
check "naming the package that moved" "$(says "$OUT" "viewinspector")" "yes"
check "and the revision it was committed at" "$(says "$OUT" "e9a0634")" "yes"
check "and the revision the build resolved instead" "$(says "$OUT" "0000000")" "yes"
check "and not the package that did not move" "$(says "$OUT" "backstage")" "no"

# 3. THE FIRST REMEDY IT PRINTS, RUN: committing the move makes it the resolution.
check "it prints the remedy that commits a move made on purpose" \
    "$(says "$OUT" "git add -- $RESOLVED")" "yes"
git_in add -- "$RESOLVED" && git_in commit -q -m "move it on purpose"
check "and after running that remedy the check passes" "$(run_check >/dev/null; echo $?)" "0"

# 4. THE SECOND REMEDY, RUN: putting the committed resolution back.
resolution 0.10.3 "$COMMITTED_REV" > "$REPO/$RESOLVED"
OUT="$(run_check)"; ST=$?
check "moving it again is refused again" "$ST" "1"
check "and it prints the remedy that puts the committed one back" \
    "$(says "$OUT" "git checkout HEAD -- $RESOLVED")" "yes"
git_in checkout HEAD -- "$RESOLVED"
check "and after running that remedy the check passes" "$(run_check >/dev/null; echo $?)" "0"

# 5. A VERSION THAT MOVED is named with both versions.
fresh_repo
resolution 0.10.4 "$MOVED_REV" > "$REPO/$RESOLVED"
OUT="$(run_check)"; ST=$?
check "a moved version is refused" "$ST" "1"
check "and both versions are named" "$(says "$OUT" "0.10.3")$(says "$OUT" "0.10.4")" "yesyes"

# 6. A PACKAGE THE BUILD ADDED is named, rather than folded into a count.
fresh_repo
resolution 0.10.3 "$COMMITTED_REV" ',
    {
      "identity" : "somethingnew",
      "kind" : "remoteSourceControl",
      "location" : "https://example.invalid/somethingnew",
      "state" : { "revision" : "1111111111111111111111111111111111111111", "version" : "1.0.0" }
    }' > "$REPO/$RESOLVED"
OUT="$(run_check)"; ST=$?
check "a package the build resolved and the commit lacks is refused" "$ST" "1"
check "and it is named" "$(says "$OUT" "somethingnew")" "yes"

# 7. A DIFFERENCE IN NOTHING BUT LAYOUT is still a difference, because the file on
#    disk is a tracked file and it no longer matches HEAD. It says no pin moved,
#    so nobody goes looking for a moved package that is not there (L11).
fresh_repo
printf '\n' >> "$REPO/$RESOLVED"
OUT="$(run_check)"; ST=$?
check "a resolution that differs only in layout is refused" "$ST" "1"
check "and it says that no package moved" "$(says "$OUT" "no package moved")" "yes"

# 8. A RESOLUTION DELETED FROM DISK is not a pass: the next build would resolve
#    afresh, which is the floating this exists to end.
fresh_repo
rm -f "$REPO/$RESOLVED"
OUT="$(run_check)"; ST=$?
check "a committed resolution missing from disk is refused" "$ST" "1"
git_in checkout HEAD -- "$RESOLVED"
check "and the restore remedy it names brings it back to a pass" \
    "$(says "$OUT" "git checkout HEAD -- $RESOLVED"):$(run_check >/dev/null; echo $?)" "yes:0"

# 9. A TREE THAT COMMITS NO RESOLUTION is the state ovation#421 was filed on, and
#    is refused by name rather than compared against nothing (L98).
rm -rf "$REPO"; mkdir -p "$REPO/$(dirname "$RESOLVED")"; git init -q -b main "$REPO"
printf 'x\n' > "$REPO/README"; git_in add README; git_in commit -q -m "no resolution"
resolution 0.10.3 "$COMMITTED_REV" > "$REPO/$RESOLVED"
OUT="$(run_check)"; ST=$?
check "a tree whose HEAD commits no resolution is refused" "$ST" "1"
check "and it says none is committed" "$(says "$OUT" "commits no package resolution")" "yes"

# 10. NOT A REPOSITORY is CANNOT MEASURE, its own code, never a pass (L11, L260).
rm -rf "$REPO"; mkdir -p "$REPO"
check "a directory that is not a git work tree cannot be measured" "$(run_check >/dev/null; echo $?)" "2"

# 11. A PROJECT DIRECTORY HOLDING ONLY THE COMMITTED RESOLUTION IS NO PROJECT.
#     A fresh clone now has Ovation.xcodeproj/, because a tracked file sits inside
#     it. Every question "is there a project" must answer no for that directory,
#     or the create is skipped and xcodebuild meets a project with no project
#     file. Both places that ask are asked the same directory here, so they cannot
#     come to disagree.
ONLY="$WORK/only/Ovation.xcodeproj"
mkdir -p "$ONLY/project.xcworkspace/xcshareddata/swiftpm"
resolution 0.10.3 "$COMMITTED_REV" > "$ONLY/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
check "the project create helper takes a directory holding only the resolution as no project" \
    "$(bash -c '. scripts/lib/ensure-xcode-project.sh; type xcode_project_present >/dev/null 2>&1 || { echo no-predicate; exit; }; xcode_project_present "$1" && echo present || echo absent' _ "$ONLY")" "absent"
check "and the built product lookup says there is no project, which the gate knows a build fixes" \
    "$(bash -c '. scripts/lib/built-product.sh; built_product_absence Debug /Ovation.app "$1" >/dev/null; echo $?' _ "$ONLY")" "3"
# AND THE CREATE THEN MAKES ONE THERE, keeping the committed file. The stub
# generator writes into the directory it finds, as xcodegen does; that xcodegen
# leaves a Package.resolved it finds in place was measured by hand, 2026-09-25.
printf '#!/bin/bash\necho GENERATOR-RAN >> "%s/generated.log"\nprintf "x\\n" > "%s/project.pbxproj"\n' \
    "$WORK" "$ONLY" > "$WORK/xcodegen"
chmod +x "$WORK/xcodegen"
# Inside a function because the inner `$1` belongs to `bash -c`, and the runner's
# own suite reads unindented lines for suite level arguments.
create_into() {
    OVATION_PROJECT_CREATE_POLL=0.05 bash -c '. scripts/lib/ensure-xcode-project.sh; ensure_xcode_project "$1" "$2" "$3"' _ \
        "$WORK/only" "$ONLY" "$WORK/xcodegen" >/dev/null 2>&1
}
create_into
check "so a run meeting that directory generates the project into it" \
    "$(grep -c GENERATOR-RAN "$WORK/generated.log" 2>/dev/null)" "1"
check "and the committed resolution is still there afterwards, unchanged" \
    "$(grep -c "$COMMITTED_REV" "$ONLY/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" 2>/dev/null)" "1"
check "and both take it as a project once it has a project file" \
    "$(bash -c '. scripts/lib/ensure-xcode-project.sh; type xcode_project_present >/dev/null 2>&1 || { echo no-predicate; exit; }; xcode_project_present "$1" && echo present || echo absent' _ "$ONLY"):$(bash -c '. scripts/lib/built-product.sh; built_product_absence Debug /Ovation.app "$1" >/dev/null; echo $?' _ "$ONLY")" "present:4"

# 12. THE REAL TREE commits a resolution, and it agrees with project.yml: every
#     package project.yml pins exactly is resolved at that version, and nothing
#     else is resolved. Asked of the committed file, so it runs on the Linux job
#     too, where nothing builds.
check "this repository commits its package resolution" \
    "$(git ls-files -- "$RESOLVED" | grep -c .)" "1"
AGREE="$(python3 -B - "$RESOLVED" project.yml <<'EOF'
import json, re, sys
pins = {p["location"].rstrip("/").lower(): p["state"].get("version") for p in json.load(open(sys.argv[1]))["pins"]}
declared, url = {}, None
for line in open(sys.argv[2]):
    m = re.match(r"\s+url:\s*(\S+)", line)
    if m:
        url = m.group(1).rstrip("/").lower()
    m = re.match(r"\s+exactVersion:\s*\"?([^\"\s]+)\"?", line)
    if m and url:
        declared[url] = m.group(1)
        url = None
print("agree" if declared and declared == pins else "declared %s resolved %s" % (sorted(declared.items()), sorted(pins.items())))
EOF
)"
check "and it resolves exactly the packages and versions project.yml pins" "$AGREE" "agree"

harness_end
