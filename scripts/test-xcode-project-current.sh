#!/bin/bash
# The suite for scripts/check-xcode-project-current.sh.
#
# ovation#206. project.yml lists DIRECTORIES and the generated Ovation.xcodeproj
# lists FILES, so a new Swift file is invisible to every build until somebody
# regenerates the project by hand, and nothing noticed. It bit on 2026-09-10
# while building ovation#162: YearEndExportCommand.swift was written, the build
# failed with `cannot find 'YearEndExportCommand' in scope` from a file that
# plainly referenced it, and the cause was the project rather than the code. That
# error names the wrong subject, so the diagnosis started in the wrong place.
#
# Every case builds its own tree: a project.yml, source directories and a
# project.pbxproj written in the shape xcodegen writes, so nothing here reads the
# real project or runs xcodegen (L2).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "xcode project currency tests" 17

TARGET="scripts/check-xcode-project-current.sh"
require_target "$TARGET"
harness_temp_dir WORK

TREE="$WORK/tree"

# A tree whose project.yml names two source directories, the way the real one
# names Ovation, OvationTests and OvationHostedTests, with an excludes list the
# reader must not mistake for a source.
fresh_tree() {
    [ -n "$WORK" ] || exit 1
    rm -rf "$TREE"
    mkdir -p "$TREE/App/Domain" "$TREE/AppTests" "$TREE/scripts"
    cat > "$TREE/project.yml" <<'YML'
name: Ovation
targets:
  Ovation:
    sources:
      - path: App
  OvationTests:
    sources:
      - path: AppTests
      - path: App
        excludes:
          - "Domain/Main.swift"
YML
}
on_disk() { mkdir -p "$(dirname "$TREE/$1")"; printf 'struct X {}\n' > "$TREE/$1"; }
# The project, listing exactly the file names given, one PBXFileReference line
# each in xcodegen's own format, with the non Swift references a real one has.
project_lists() {
    local name id=0
    mkdir -p "$TREE/Ovation.xcodeproj"
    {
        printf '// !$*UTF8*$!\n{\n\tobjects = {\n'
        printf '/* Begin PBXFileReference section */\n'
        printf '\t\t0000000000000000000000AA /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist; path = Info.plist; sourceTree = "<group>"; };\n'
        printf '\t\t0000000000000000000000AB /* Ovation.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Ovation.app; sourceTree = BUILT_PRODUCTS_DIR; };\n'
        for name in "$@"; do
            id=$((id+1))
            case "$name" in
                *" "*) printf '\t\t%024d /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "%s"; sourceTree = "<group>"; };\n' "$id" "$name" "$name" ;;
                *) printf '\t\t%024d /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = %s; sourceTree = "<group>"; };\n' "$id" "$name" "$name" ;;
            esac
        done
        printf '/* End PBXFileReference section */\n\t};\n}\n'
    } > "$TREE/Ovation.xcodeproj/project.pbxproj"
}
run_it() {
    OVATION_REPO_ROOT="$TREE" OVATION_XCODE_PROJECT="$TREE/Ovation.xcodeproj" \
        "./$TARGET" 2>&1
}
status_of() { run_it >/dev/null 2>&1; printf '%s' "$?"; }
mentions() { if printf '%s' "$1" | grep -qF -- "$2"; then echo yes; else echo no; fi; }

# 1. A project listing every Swift file on disk is current, and says how many.
fresh_tree
on_disk App/Domain/Main.swift; on_disk AppTests/MainTests.swift
project_lists Main.swift MainTests.swift
OUT="$(run_it)"; RC=$?
check "a project listing every Swift file on disk is current" "$RC" "0"
check "and it says how many it compared, so a pass is not a silence" \
    "$(mentions "$OUT" "2 Swift files")" "yes"

# 2. THE INCIDENT: a file written after the project was generated.
fresh_tree
on_disk App/Domain/Main.swift; on_disk App/Export/YearEndThing.swift
project_lists Main.swift
OUT="$(run_it)"; RC=$?
check "a Swift file the project does not list is refused" "$RC" "1"
check "and it names the file, where it is" \
    "$(mentions "$OUT" "App/Export/YearEndThing.swift")" "yes"
check "and it gives the command that fixes it" \
    "$(mentions "$OUT" "bash scripts/regenerate-xcode-project.sh")" "yes"

# 3. The other direction: a file deleted or renamed, still listed.
fresh_tree
on_disk App/Domain/Main.swift
project_lists Main.swift Gone.swift
OUT="$(run_it)"; RC=$?
check "a project listing a file that is no longer on disk is refused" "$RC" "1"
check "and it names the file the project still lists" "$(mentions "$OUT" "Gone.swift")" "yes"

# 4. A NAME IN TWO DIRECTORIES IS TWO FILES. The project lists files by name, so
#    the comparison counts names rather than asking only whether one appears.
fresh_tree
on_disk App/Domain/Shared.swift; on_disk AppTests/Shared.swift
project_lists Shared.swift
check "a second file of the same name that the project lists once is refused" "$(status_of)" "1"

# 5. NO PROJECT is nothing to compare, which is its own outcome: the next run
#    generates one from these very directories.
fresh_tree
on_disk App/Domain/Main.swift
check "a tree with no generated project cannot be measured" "$(status_of)" "2"

# 6. A project directory with no project.pbxproj in it is nothing to read either.
fresh_tree
on_disk App/Domain/Main.swift
mkdir -p "$TREE/Ovation.xcodeproj"
check "a project directory with no project file in it cannot be measured" "$(status_of)" "2"

# 7. A READER THAT READ NOTHING IS NOT A STALE PROJECT (L98). A project file in
#    which no Swift reference could be found says the reader or the file is
#    wrong, and calling that "stale" would send somebody to regenerate for ever.
fresh_tree
on_disk App/Domain/Main.swift
project_lists
OUT="$(run_it)"; RC=$?
check "a project file with no Swift references in it is its own refusal" "$RC" "3"
check "and it says nothing could be read, rather than that files are missing" \
    "$(mentions "$OUT" "no Swift file references")" "yes"

# 8. No project.yml means no source directories to walk.
fresh_tree
on_disk App/Domain/Main.swift
project_lists Main.swift
rm -f "$TREE/project.yml"
check "a tree with no project.yml is refused, not passed" "$(status_of)" "3"

# 9. A quoted path, which xcodegen writes for any name with a space or a dash.
fresh_tree
on_disk "App/Domain/Odd Name.swift"
project_lists "Odd Name.swift"
check "a quoted path in the project file is read" "$(status_of)" "0"

# 10. ONLY WHAT project.yml NAMES. A Swift file outside every source directory is
#     not part of any target, so its absence from the project is correct.
fresh_tree
on_disk App/Domain/Main.swift; on_disk scripts/tool.swift
project_lists Main.swift
check "a Swift file outside the source directories is not demanded" "$(status_of)" "0"

# 11. STARTED WITH bash, THE SAME CODES (ovation#257). This is Python behind a .sh
#     name, and `bash scripts/check-xcode-project-current.sh` is the obvious way
#     to run it by hand. A caller acts on the code, so the refusal and the could
#     not measure are both asserted rather than only a pass (L404).
fresh_tree
on_disk App/Domain/Main.swift; on_disk App/Domain/New.swift
project_lists Main.swift
check "started with bash, a stale project still exits 1" \
    "$(OVATION_REPO_ROOT="$TREE" OVATION_XCODE_PROJECT="$TREE/Ovation.xcodeproj" bash "$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "1"
rm -rf "$TREE/Ovation.xcodeproj"
check "and with no project it still exits 2" \
    "$(OVATION_REPO_ROOT="$TREE" OVATION_XCODE_PROJECT="$TREE/Ovation.xcodeproj" bash "$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "2"

harness_end
