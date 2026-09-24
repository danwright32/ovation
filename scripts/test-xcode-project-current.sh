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
harness_begin "xcode project currency tests" 36

TARGET="scripts/check-xcode-project-current.sh"
require_target "$TARGET"
harness_temp_dir WORK

TREE="$WORK/tree"

# A tree whose project.yml names two source directories, the way the real one
# names Ovation, OvationTests and OvationHostedTests, with an excludes list the
# reader must not mistake for a source.
# The packages block project.yml declares, and the package references the
# generated project holds, are set per case and default to none, so every case
# written before ovation#419 keeps the tree it was written against.
YML_PACKAGES=""
PROJECT_PACKAGE_URLS=()

fresh_tree() {
    [ -n "$WORK" ] || exit 1
    rm -rf "$TREE"
    YML_PACKAGES=""
    PROJECT_PACKAGE_URLS=()
    PROJECT_TARGET_PACKAGES=()
    YML_TARGET_PACKAGE=""
    mkdir -p "$TREE/App/Domain" "$TREE/AppTests" "$TREE/scripts"
    write_yml
}

# Written on its own so a case can declare packages and rewrite the yml without
# rebuilding the tree and losing the files already on disk.
write_yml() {
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
    if [ -n "$YML_PACKAGES" ]; then printf '%s\n' "$YML_PACKAGES" >> "$TREE/project.yml"; fi
    if [ -n "$YML_TARGET_PACKAGE" ]; then
        local target="${YML_TARGET_PACKAGE%% *}" product="${YML_TARGET_PACKAGE#* }"
        python3 - "$TREE/project.yml" "$target" "$product" <<'INSERT'
import sys
path, target, product = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path).read().split("\n")
out = []
for line in lines:
    out.append(line)
    if line.strip() == target + ":":
        out.append("    dependencies:")
        out.append("      - sdk: libsqlite3.tbd")
        out.append("      - package: " + product)
open(path, "w").write("\n".join(out))
INSERT
    fi
    return 0
}

# project.yml's own shape: a package name, then an indented url. The comment
# line is there because the real block carries several and a reader that does
# not skip them reads a comment as a package.
# project.yml's other half: a target naming a package it depends on. Written as
# the real file writes it, under `dependencies:` beside an sdk entry, because a
# reader that cannot tell `- package:` from `- sdk:` reads both as packages.
YML_TARGET_PACKAGE=""
yml_target_depends_on_package() {
    YML_TARGET_PACKAGE="$1 $2"
    write_yml
}

yml_declares_package() {
    YML_PACKAGES="packages:
  # why this dependency is worth it
  $1:
    url: $2
    from: \"0.10.0\""
    write_yml
}
on_disk() { mkdir -p "$(dirname "$TREE/$1")"; printf 'struct X {}\n' > "$TREE/$1"; }
# Each "Target=Product,Product" pair a case wants the generated project to hold,
# which is what a PBXNativeTarget's packageProductDependencies list records. A
# target with no packages is named with nothing after the equals.
PROJECT_TARGET_PACKAGES=()

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
        printf '/* End PBXFileReference section */\n'
        if [ ${#PROJECT_PACKAGE_URLS[@]} -gt 0 ]; then
            printf '/* Begin XCRemoteSwiftPackageReference section */\n'
            for name in "${PROJECT_PACKAGE_URLS[@]}"; do
                id=$((id+1))
                printf '\t\t%024d /* XCRemoteSwiftPackageReference */ = {\n' "$id"
                printf '\t\t\tisa = XCRemoteSwiftPackageReference;\n'
                printf '\t\t\trepositoryURL = "%s";\n' "$name"
                printf '\t\t\trequirement = {\n\t\t\t\tkind = upToNextMajorVersion;\n\t\t\t\tminimumVersion = 0.10.0;\n\t\t\t};\n\t\t};\n'
            done
            printf '/* End XCRemoteSwiftPackageReference section */\n'
        fi
        if [ ${#PROJECT_TARGET_PACKAGES[@]} -gt 0 ]; then
            printf '/* Begin PBXNativeTarget section */\n'
            for name in "${PROJECT_TARGET_PACKAGES[@]}"; do
                id=$((id+1))
                printf '\t\t%024d /* %s */ = {\n' "$id" "${name%%=*}"
                printf '\t\t\tisa = PBXNativeTarget;\n'
                printf '\t\t\tname = %s;\n' "${name%%=*}"
                printf '\t\t\tpackageProductDependencies = (\n'
                local products="${name#*=}"
                if [ "$products" != "$name" ] && [ -n "$products" ]; then
                    local product
                    for product in ${products//,/ }; do
                        id=$((id+1))
                        printf '\t\t\t\t%024d /* %s */,\n' "$id" "$product"
                    done
                fi
                printf '\t\t\t);\n\t\t};\n'
            done
            printf '/* End PBXNativeTarget section */\n'
        fi
        printf '\t};\n}\n'
    } > "$TREE/Ovation.xcodeproj/project.pbxproj"
}
# A package reference carrying no repositoryURL, appended to a generated project.
# Written here rather than inline so the case reads as what it asserts.
urlless_package_reference() {
    local file="$1"
    python3 -c 'import sys
path = sys.argv[1]
text = open(path).read()
closing = "\t};\n}\n"
assert text.endswith(closing), "fixture shape changed"
text = text[: -len(closing)] + """/* Begin XCRemoteSwiftPackageReference section */
\t\t000000000000000000000099 /* XCRemoteSwiftPackageReference */ = {
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trequirement = {
\t\t\t\tkind = upToNextMajorVersion;
\t\t\t};
\t\t};
/* End XCRemoteSwiftPackageReference section */
""" + closing
open(path, "w").write(text)' "$file"
}

run_it() {
    OVATION_REPO_ROOT="$TREE" OVATION_XCODE_PROJECT="$TREE/Ovation.xcodeproj" \
        "./$TARGET" 2>&1
}
status_of() { run_it >/dev/null 2>&1; printf '%s' "$?"; }
mentions() { if grep -qF -- "$2" <<< "$1"; then echo yes; else echo no; fi; }

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

# ovation#419. EVERYTHING ABOVE COMPARES FILE SETS, and a project.yml change that
# is not a file set change reaches no machine that already holds a generated
# project, because `lib/ensure-xcode-project.sh` only ever CREATES one. Adding a
# `packages:` entry is exactly that shape, and it is the shape ovation#424 has.

# 12. A package project.yml declares that the generated project does not hold.
fresh_tree
on_disk App/Domain/Main.swift; on_disk AppTests/MainTests.swift
yml_declares_package ViewInspector https://github.com/nalexn/ViewInspector
project_lists Main.swift MainTests.swift
OUT="$(run_it)"; RC=$?
check "a package project.yml declares that the project does not hold is refused" "$RC" "1"
check "and it names the package, so the subject is right the first time" \
    "$(mentions "$OUT" "https://github.com/nalexn/ViewInspector")" "yes"

# 13. The other direction: a package removed from project.yml and still built.
fresh_tree
on_disk App/Domain/Main.swift; on_disk AppTests/MainTests.swift
PROJECT_PACKAGE_URLS=(https://github.com/nalexn/ViewInspector)
project_lists Main.swift MainTests.swift
OUT="$(run_it)"; RC=$?
check "a package the project still holds that project.yml no longer declares is refused" "$RC" "1"
check "and it names that one too" \
    "$(mentions "$OUT" "https://github.com/nalexn/ViewInspector")" "yes"

# 14. Declared and held: current, which is the state the real tree is in today.
fresh_tree
on_disk App/Domain/Main.swift; on_disk AppTests/MainTests.swift
yml_declares_package ViewInspector https://github.com/nalexn/ViewInspector
PROJECT_PACKAGE_URLS=(https://github.com/nalexn/ViewInspector)
project_lists Main.swift MainTests.swift
check "a package declared and held is current" "$(status_of)" "0"

# 15. A TRAILING .git IS THE SAME REPOSITORY. Each side keeps the spelling it was
#     given, so two spellings of one URL must not read as two packages.
fresh_tree
on_disk App/Domain/Main.swift; on_disk AppTests/MainTests.swift
yml_declares_package ViewInspector https://github.com/nalexn/ViewInspector
PROJECT_PACKAGE_URLS=(https://github.com/nalexn/ViewInspector.git)
project_lists Main.swift MainTests.swift
check "the same repository spelled with and without .git is one package" "$(status_of)" "0"

# 16. NEITHER SIDE HAS ANY. A tree with no packages at all is current, and that is
#     the tree every check written before ovation#419 stands on.
fresh_tree
on_disk App/Domain/Main.swift; on_disk AppTests/MainTests.swift
project_lists Main.swift MainTests.swift
check "a tree that declares no packages and holds none is current" "$(status_of)" "0"

# 17. A READER THAT READ NOTHING IS NOT A VERDICT (L98), for packages too. A
#     project holding a package section this cannot get a URL out of is a file it
#     cannot read, never a project that is missing a package.
fresh_tree
on_disk App/Domain/Main.swift; on_disk AppTests/MainTests.swift
yml_declares_package ViewInspector https://github.com/nalexn/ViewInspector
project_lists Main.swift MainTests.swift
urlless_package_reference "$TREE/Ovation.xcodeproj/project.pbxproj"
OUT="$(run_it)"; RC=$?
check "a package reference with no repository URL in it is its own refusal" "$RC" "3"
check "and it says the project could not be read, not that a package is missing" \
    "$(mentions "$OUT" "could not be read")" "yes"

# 18. WHICH TARGET HOLDS THE PACKAGE. The package is declared and held, so every
#     check above passes, and the target that has to link it does not.
fresh_tree
on_disk App/Domain/Main.swift; on_disk AppTests/MainTests.swift
yml_declares_package ViewInspector https://github.com/nalexn/ViewInspector
yml_target_depends_on_package OvationTests ViewInspector
PROJECT_PACKAGE_URLS=(https://github.com/nalexn/ViewInspector)
PROJECT_TARGET_PACKAGES=("Ovation=" "OvationTests=")
project_lists Main.swift MainTests.swift
OUT="$(run_it)"; RC=$?
check "a target that project.yml says depends on a package, and does not, is refused" "$RC" "1"
check "and it names the target, not just the package" "$(mentions "$OUT" "OvationTests")" "yes"

# 19. The same tree with the membership actually in the project.
fresh_tree
on_disk App/Domain/Main.swift; on_disk AppTests/MainTests.swift
yml_declares_package ViewInspector https://github.com/nalexn/ViewInspector
yml_target_depends_on_package OvationTests ViewInspector
PROJECT_PACKAGE_URLS=(https://github.com/nalexn/ViewInspector)
PROJECT_TARGET_PACKAGES=("Ovation=" "OvationTests=ViewInspector")
project_lists Main.swift MainTests.swift
check "a target holding the package it declares is current" "$(status_of)" "0"

# 20. The other direction: linked by the project, declared by nobody.
fresh_tree
on_disk App/Domain/Main.swift; on_disk AppTests/MainTests.swift
yml_declares_package ViewInspector https://github.com/nalexn/ViewInspector
PROJECT_PACKAGE_URLS=(https://github.com/nalexn/ViewInspector)
PROJECT_TARGET_PACKAGES=("Ovation=ViewInspector" "OvationTests=")
project_lists Main.swift MainTests.swift
OUT="$(run_it)"; RC=$?
check "a target linking a package project.yml does not give it is refused" "$RC" "1"
check "and it names that target too" "$(mentions "$OUT" "Ovation")" "yes"

# 21. FAIL CLOSED (L98). project.yml gives a target a package and the project
#     holds no native target at all: nothing to compare membership against, which
#     is not the same as membership being right.
fresh_tree
on_disk App/Domain/Main.swift; on_disk AppTests/MainTests.swift
yml_declares_package ViewInspector https://github.com/nalexn/ViewInspector
yml_target_depends_on_package OvationTests ViewInspector
PROJECT_PACKAGE_URLS=(https://github.com/nalexn/ViewInspector)
project_lists Main.swift MainTests.swift
OUT="$(run_it)"; RC=$?
check "a project with no target in it cannot answer which target holds a package" "$RC" "3"
check "and it says so rather than passing" "$(mentions "$OUT" "could not be read")" "yes"

# 22. AN sdk DEPENDENCY IS NOT A PACKAGE. Every target in the real file carries
#     `- sdk: libsqlite3.tbd`, and a reader that counts it as a package demands a
#     package nobody declared, on every target, for ever.
fresh_tree
on_disk App/Domain/Main.swift; on_disk AppTests/MainTests.swift
PROJECT_TARGET_PACKAGES=("Ovation=" "OvationTests=")
project_lists Main.swift MainTests.swift
YML_TARGET_PACKAGE=""
python3 - "$TREE/project.yml" <<'SDKONLY'
import sys
path = sys.argv[1]
lines = open(path).read().split("\n")
out = []
for line in lines:
    out.append(line)
    if line.strip() == "Ovation:":
        out.append("    dependencies:")
        out.append("      - sdk: libsqlite3.tbd")
open(path, "w").write("\n".join(out))
SDKONLY
check "an sdk dependency is not read as a package" "$(status_of)" "0"

# 23. THE ORDER OF THE TWO VERDICTS, pinned because it is a decision (ovation#419).
#     A tree stale in its FILES whose project also cannot answer the membership
#     question has two true things to say and one remedy. It says the files,
#     because that one names what to look at. Without this case the reader can be
#     reordered and only test-run-tests.sh, three suites away, would notice.
fresh_tree
on_disk App/Domain/Main.swift; on_disk App/Domain/Unlisted.swift
yml_declares_package ViewInspector https://github.com/nalexn/ViewInspector
yml_target_depends_on_package OvationTests ViewInspector
PROJECT_PACKAGE_URLS=(https://github.com/nalexn/ViewInspector)
project_lists Main.swift
OUT="$(run_it)"; RC=$?
check "a tree stale in its files reports the files, not the unreadable membership" "$RC" "1"
check "and it names the file rather than the package" \
    "$(mentions "$OUT" "App/Domain/Unlisted.swift")" "yes"

harness_end
