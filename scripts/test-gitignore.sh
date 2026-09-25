#!/bin/bash
# What the repository's own .gitignore hides, asserted against the real file.
#
# ovation#429. `.claude/worktrees/` is where a worktree in this repository
# naturally goes, and nothing ignored it, so one placed there was several hundred
# untracked files INSIDE the checkout. A `git add .` from a session in the primary
# checkout would then stage a whole second copy of the repository, and the identity
# guard deliberately does not look inside a directory named `worktrees`, so its
# contents must never be staged.
#
# ONLY THE WORKTREES FOLDER, never all of `.claude/`. Project settings live there
# too and may be committed on purpose, so the control below asserts one stays
# visible: an entry of `.claude/` would pass the first case and hide it (L104).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "gitignore tests" 8

harness_temp_dir WORK

# A THROWAWAY REPOSITORY carrying the real .gitignore, so the question is asked of
# the file as committed and never of whatever this checkout happens to hold.
REPO="$WORK/repo"
mkdir -p "$REPO/.claude/worktrees/somebranch" "$REPO/.claude"
( cd "$REPO" && git init -q -b main ) >/dev/null 2>&1
cp .gitignore "$REPO/.gitignore"
printf 'x\n' > "$REPO/.claude/worktrees/somebranch/README.md"
printf '{}\n' > "$REPO/.claude/settings.json"

ignored() { if ( cd "$REPO" && git check-ignore -q "$1" ); then echo yes; else echo no; fi; }

check "a worktree placed under .claude/worktrees is ignored" \
    "$(ignored .claude/worktrees/somebranch/README.md)" "yes"
check "and so git status in the checkout does not report it" \
    "$( cd "$REPO" && git status --porcelain --untracked-files=all | grep -c 'worktrees' )" "0"
check "the project settings beside it stay visible, so only the worktrees are hidden" \
    "$(ignored .claude/settings.json)" "no"

# THE PACKAGE RESOLUTION IS COMMITTED, AND NOTHING ELSE OF THE PROJECT (ovation#421).
# SwiftPM writes the revision every package resolved to inside the generated
# project, and ignoring that directory wholesale kept the one file in it that is
# not generated from project.yml out of version control, so a moved tag moved
# the build with no diff anywhere (L25, L496). The generated files around it stay
# ignored, because committing those is the two descriptions of one project that
# the ignore exists to prevent (L41). Asked of each depth, because git cannot
# re-include a file under a directory it has excluded.
RESOLVED="Ovation.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
mkdir -p "$REPO/$(dirname "$RESOLVED")" "$REPO/Ovation.xcodeproj/xcshareddata/xcschemes" \
    "$REPO/Ovation.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/configuration"
printf '{}\n' > "$REPO/$RESOLVED"
printf 'x\n' > "$REPO/Ovation.xcodeproj/project.pbxproj"
printf 'x\n' > "$REPO/Ovation.xcodeproj/project.xcworkspace/contents.xcworkspacedata"
printf 'x\n' > "$REPO/Ovation.xcodeproj/xcshareddata/xcschemes/Ovation.xcscheme"
printf 'x\n' > "$REPO/Ovation.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/configuration/x"
check "the package resolution inside the generated project is not ignored" \
    "$(ignored "$RESOLVED")" "no"
check "and git add takes it without being forced" \
    "$( cd "$REPO" && git add -- "$RESOLVED" >/dev/null 2>&1 && git ls-files -- "$RESOLVED" | grep -c . )" "1"
check "the generated project file is still ignored" \
    "$(ignored Ovation.xcodeproj/project.pbxproj)" "yes"
check "and so are the generated workspace and schemes beside it" \
    "$(ignored Ovation.xcodeproj/project.xcworkspace/contents.xcworkspacedata):$(ignored Ovation.xcodeproj/xcshareddata/xcschemes/Ovation.xcscheme)" "yes:yes"
check "and so is anything else SwiftPM writes next to the resolution" \
    "$(ignored Ovation.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/configuration/x)" "yes"

harness_end
