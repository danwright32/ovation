#!/bin/bash
# The suite for scripts/lib/xcode-phase-inputs.sh: which paths the Xcode phase of
# a test run can read, worked out from the tree rather than from a list.
#
# ovation#358. The push gate skips the Xcode phase (the project, both builds and
# the Swift suites) only when nothing in the push can reach it. Since ovation#154
# that meant any change under scripts/ paid the whole phase, because the build
# command lives there and a hand kept list of the scripts that cannot reach a
# build was a registry nobody could keep honest (L27, L96). Every one of the seven
# changes shipped on 2026-09-15 touched only scripts and design files, and each
# push paid about twenty five minutes for a question none of them could affect.
#
# THE ANSWER IS DERIVED, from two things the tree already holds (L41):
#
#   scripts   the runner, and every script whose CODE runs xcodebuild or
#             xcodegen, are the roots; whatever their code names by file name is
#             read too, and so on down. Comments do not count: every script here
#             names a dozen others in its comments, and counting those made 146
#             of 148 files reachable, which is a derivation that saves nothing.
#   Swift     a path a Swift file names as a string literal is read, because the
#             tests open repository files through #filePath. Three of them read
#             files under docs/design/, which the gate called unreadable by any
#             Xcode build or test since ovation#22 (L88).
#
# A NAME FOUND BY TEXT CAN BE MISSED when a script builds a path at run time. So
# the last cases run the real runner's Xcode phase with every tool faked, trace
# every script it actually touches, and require each one to be something the
# derivation already said the phase reads. That trace is a second source, not the
# derivation read back (L70), and it is proved able to catch a miss first (L1).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "xcode phase inputs tests" 36

LIB="scripts/lib/xcode-phase-inputs.sh"
require_target "$LIB"
require_target "scripts/run-tests.sh"
harness_temp_dir WORK
REPO_ROOT="$PWD"

# shellcheck source=lib/xcode-phase-inputs.sh
. "$LIB"

# The verdict for one path, as a word, so a failure prints what was decided.
verdict() {
    if xcode_phase_reads "$1"; then echo "read"; else echo "not read"; fi
}

# ---------------------------------------------------------------------------
# A FIXTURE TREE, where every relationship is one this suite chose, so each rule
# is exercised on its own (L159).
F="$WORK/fixture"
mkdir -p "$F/scripts/lib" "$F/Ovation" "$F/docs/design" "$F/docs/rules" "$F/.github/workflows"
cat > "$F/scripts/run-tests.sh" <<'EOF'
#!/bin/bash
# see scripts/commented.sh, which is named only in this comment
. "$REPO_ROOT/scripts/lib/pin.sh"
floor="$(cat "$REPO_ROOT/scripts/floor.txt")"
. "$REPO_ROOT/scripts/lib/removed.sh"
EOF
printf '#!/bin/bash\npython3 "$(dirname "$0")/../deep.py"\n' > "$F/scripts/lib/pin.sh"
printf 'print("deep")\n' > "$F/scripts/deep.py"
printf '12\n' > "$F/scripts/floor.txt"
printf '#!/bin/bash\n. "$(dirname "$0")/lib/helper.sh"\nxcodebuild -scheme Ovation build\n' > "$F/scripts/build.sh"
printf '#!/bin/bash\necho helper\n' > "$F/scripts/lib/helper.sh"
printf '#!/bin/bash\necho commented\n' > "$F/scripts/commented.sh"
printf '#!/bin/bash\necho design\n' > "$F/scripts/check-design-thing.sh"
printf '#!/bin/bash\nOVATION_XCODEBUILD=stub xcodebuild -version\nbash scripts/lonely.sh\n' > "$F/scripts/test-fake.sh"
printf '#!/bin/bash\necho lonely\n' > "$F/scripts/lonely.sh"
printf '#!/bin/bash\n# this once ran xcodebuild, and now only says so\necho tool\n' > "$F/scripts/tool.sh"
cat > "$F/Ovation/Reader.swift" <<'EOF'
import Foundation
enum Reader {
    // "docs/commented.json" is named only in this comment
    static let expected = "docs/design/read.json"
    static func rule(_ name: String) -> String { "docs/rules/\(name).json" }
}
EOF
# A CHECKOUT NESTED INSIDE THIS ONE is somebody else's tree: the primary checkout
# holds worktrees under .claude/, and a recursive search collects their sources as
# if they were this tree's own (L234).
mkdir -p "$F/.claude/worktrees/other/OvationTests"
printf 'let u = "docs/nested.json"\n' > "$F/.claude/worktrees/other/OvationTests/Nested.swift"
printf '{}\n' > "$F/docs/design/read.json"
printf '# other\n' > "$F/docs/other.md"
printf 'name: ci\n' > "$F/.github/workflows/ci.yml"

xcode_phase_inputs_load "$F"; LOAD_STATUS=$?
check "the fixture tree loads" "$LOAD_STATUS" "0"

check "the runner is read, because the Xcode phase lives in it" \
    "$(verdict scripts/run-tests.sh)" "read"
check "a library the runner's code sources is read" \
    "$(verdict scripts/lib/pin.sh)" "read"
check "and what that library runs is read too, one step further down" \
    "$(verdict scripts/deep.py)" "read"
check "a file that is not a script, named by the runner's code, is read" \
    "$(verdict scripts/floor.txt)" "read"
check "a script whose code runs xcodebuild is read" \
    "$(verdict scripts/build.sh)" "read"
check "and a library that script names is read" \
    "$(verdict scripts/lib/helper.sh)" "read"
# A DELETION IS A CHANGE TOO. The runner still names a file the push removed, so
# the phase is about to fail on it, and the path is judged by being named rather
# than by being on disk.
check "a file the runner names that is no longer on disk is still read" \
    "$(verdict scripts/lib/removed.sh)" "read"

check "a script named only in a comment is not read" \
    "$(verdict scripts/commented.sh)" "not read"
check "a script nothing in the phase names is not read" \
    "$(verdict scripts/check-design-thing.sh)" "not read"
# THE SHELL SUITES RUN ON EVERY PUSH WHATEVER THE GATE DECIDES, so a suite that
# stubs xcodebuild is not part of the phase, and neither is what only it names.
check "a shell suite whose code calls xcodebuild is not a root" \
    "$(verdict scripts/test-fake.sh)" "not read"
check "and a script only that suite names is not read" \
    "$(verdict scripts/lonely.sh)" "not read"
check "a script that mentions xcodebuild only in a comment is not a root" \
    "$(verdict scripts/tool.sh)" "not read"

check "a docs file a Swift file names is read" \
    "$(verdict docs/design/read.json)" "read"
check "and the reason given says a Swift file names it" \
    "$(xcode_phase_reads docs/design/read.json; printf '%s' "$XPI_WHY" | grep -c 'Swift')" "1"
check "a docs file under a path a Swift file builds with interpolation is read" \
    "$(verdict docs/rules/anything.json)" "read"
check "a docs file named only in a Swift comment is not read" \
    "$(verdict docs/commented.json)" "not read"
check "a docs file nothing names is not read" \
    "$(verdict docs/other.md)" "not read"
check "a docs file named only by a Swift file in a nested checkout is not read" \
    "$(verdict docs/nested.json)" "not read"
check "a workflow file is not read" \
    "$(verdict .github/workflows/ci.yml)" "not read"

# FAIL CLOSED OUTSIDE THE TWO DERIVED AREAS. Anything that is neither a script
# nor on the short list of files no build can open is read by default, whether
# or not anything here can see a reference to it.
check "a Swift file is read" "$(verdict Ovation/Thing.swift)" "read"
check "project.yml is read" "$(verdict project.yml)" "read"
check "a file in a folder nobody has classified is read" "$(verdict integration/new.json)" "read"

# A TREE WITH NO RUNNER CANNOT BE JUDGED, and saying nothing is read would be
# the gate skipping on a question it never answered (L98, L173).
mkdir -p "$WORK/empty/scripts"
LOAD_EMPTY="$(xcode_phase_inputs_load "$WORK/empty"; echo "status=$? $XPI_ERROR")"
check "a tree with no runner refuses to load" \
    "$(printf '%s' "$LOAD_EMPTY" | grep -c '^status=[1-9]')" "1"
check "and the refusal names the runner it could not find" \
    "$(printf '%s' "$LOAD_EMPTY" | grep -c 'run-tests.sh')" "1"

# ---------------------------------------------------------------------------
# THE REAL TREE, with the answers ovation#154 and ovation#358 are about. These
# are measured claims about this repository, so a change that moves one of them
# has to say why here.
xcode_phase_inputs_load "$REPO_ROOT"; REAL_STATUS=$?
check "this repository loads" "$REAL_STATUS" "0"
check "the build command is read (ovation#154)" \
    "$(verdict scripts/lib/build-one-configuration.sh)" "read"
check "the script that builds both products is read" \
    "$(verdict scripts/build-products.sh)" "read"
check "the pure suite's floor is read" \
    "$(verdict scripts/pure-test-floor.txt)" "read"
check "the invoice PDF's expected output under docs/design is read" \
    "$(verdict docs/design/invoice-pdf.expected.json)" "read"
check "a design suite shipped on 2026-09-15 is not read (ovation#358)" \
    "$(verdict scripts/test-design-record-open.sh)" "not read"
check "a design check the gate runs is not read" \
    "$(verdict scripts/check-design-dead-rules.sh)" "not read"

# ---------------------------------------------------------------------------
# WHAT THE PHASE ACTUALLY TOUCHES, TRACED, AGAINST WHAT WAS DERIVED.
#
# Every tool is faked the way scripts/test-run-tests.sh fakes it, so nothing is
# built and no real lock is taken (L2, L291), and the environment is emptied so
# no seam from the shell that launched this suite answers for the run (L439).
# xtrace is exported through SHELLOPTS, so every bash the runner starts traces
# too, and PS4 carries the file each traced line came from.
SUITE_FLOCK=""
for candidate in /opt/homebrew/bin/flock /usr/local/bin/flock /usr/bin/flock; do
    [ -x "$candidate" ] && { SUITE_FLOCK="$candidate"; break; }
done
[ -n "$SUITE_FLOCK" ] || harness_cannot_measure \
    "flock is not installed, and the runner refuses to run without it" \
    "install it with: brew install flock"

T="$WORK/trace"
mkdir -p "$T/standin.xcodeproj"
printf 'com.apple.finder\n' > "$T/domains"
env -i HOME="$T" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" \
    PS4='+@@XT@@${BASH_SOURCE[0]:-}@@ ' SHELLOPTS=xtrace \
    OVATION_XCODEBUILD="$T/no-xcodebuild" \
    OVATION_XCODE_VERSION_FILE="$T/no-pin" \
    OVATION_DEFAULTS_DOMAINS_COMMAND="cat '$T/domains'" \
    OVATION_DIR_LOCK="$T/dir.lock" OVATION_FILE_LOCK="$T/file.lock" \
    OVATION_LOCK_TIMEOUT=2 OVATION_LOCK_POLL_INTERVAL=0.05 \
    OVATION_FLOCK_BIN="$SUITE_FLOCK" \
    OVATION_TEST_COMMAND='echo "Test run with 900 tests in 1 suite passed"' \
    OVATION_HOSTED_TEST_COMMAND='echo "Test run with 5 tests in 1 suite passed"' \
    OVATION_UNLOCKED_COMMAND=true \
    OVATION_XCODE_PROJECT="$T/standin.xcodeproj" \
    bash "$REPO_ROOT/scripts/run-tests.sh" > "$T/run.txt" 2>&1
TRACE_STATUS=$?

# Every path under scripts/ the trace mentions that is a file in this tree, as a
# path relative to the repository.
traced_scripts() {
    grep '@@XT@@' "$1" | grep -oE 'scripts/[A-Za-z0-9_./-]+' | sort -u | while IFS= read -r p; do
        [ -f "$REPO_ROOT/$p" ] && printf '%s\n' "$p"
    done
}

# The traced paths the derivation says the phase does NOT read. Empty is agreement.
traced_but_not_read() {
    traced_scripts "$1" | while IFS= read -r p; do
        xcode_phase_reads "$p" || printf '%s\n' "$p"
    done
}

check "the traced runner ran to the end" "$TRACE_STATUS" "0"
# A POSITIVE CONTROL: a trace that captured nothing agrees with everything.
check "the trace saw the runner and the libraries it sources" \
    "$(traced_scripts "$T/run.txt" | grep -cE '^scripts/(run-tests\.sh|lib/dir-lock\.sh|lib/xcode-pin\.sh|lib/ensure-xcode-project\.sh)$')" "4"
# AND THE COMPARISON CAN FAIL: the same function, handed a trace line naming a
# script the derivation says is not read, has to report it.
cp "$T/run.txt" "$T/planted.txt"
printf '+@@XT@@%s/scripts/check-design-dead-rules.sh@@ echo planted\n' "$REPO_ROOT" >> "$T/planted.txt"
check "a traced script the derivation missed is reported" \
    "$(traced_but_not_read "$T/planted.txt")" "scripts/check-design-dead-rules.sh"
check "every script the Xcode phase touched is one the derivation says it reads" \
    "$(traced_but_not_read "$T/run.txt")" ""

harness_end
