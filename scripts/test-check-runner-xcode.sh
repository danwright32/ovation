#!/bin/bash
# Whether the watcher can tell the four things apart that the Xcode pin can be.
#
# ovation#320. Xcode updated itself on Dan's Mac to 27.0, the pinned 26.6 is no
# longer installed here, and the image CI builds on does not offer 27.0 at all:
# measured 2026-09-16, macos-26 carries 26.0.1 up to 26.6 and nothing newer, and
# the only image with an Xcode 27 is a public preview whose Xcode is a BETA build
# against the release build this Mac has. So the two cannot be brought together
# by any change in this repository, and the decision taken was to wait with the
# mismatch named rather than to pretend otherwise.
#
# THE WAITING NEEDS AN OWNER. A note that says "wait" and nothing that says "it is
# over" is a suppression with no expiry (L523): nothing would ever re-measure it,
# and the premise it rests on, that the image has no newer Xcode, is exactly the
# kind that expires (L316).
#
# IT IS NOT WRITTEN TO LOOK FOR XCODE 27. A watcher keyed on the version that
# happens to be wanted today is a one-shot that goes quiet for ever after it
# fires. The question it asks is "does CI's image offer an Xcode newer than the
# pin", which is the same question when 26.7 appears, and the answer to that one
# is a pin bump nobody is currently told to make.
#
# AND IT WATCHES THE OTHER DIRECTION TOO. Runner images keep only the newest patch
# of each version, so the day the image replaces 26.6 the CI build REFUSES, by
# scripts/select-xcode.sh, with no warning first. That is a louder finding than a
# newer Xcode being available and it has its own outcome here.
#
# Every case drives the script against staged manifests and a stub fetch, because
# a suite that could only pass by reaching GitHub would be asserting about what
# Microsoft shipped this week rather than about this script (L2, L291).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "runner Xcode watch tests" 30

TARGET="scripts/check-runner-xcode.sh"
require_target "$TARGET"
harness_temp_dir WORK

MANIFESTS="$WORK/manifests"
mkdir -p "$MANIFESTS"
ASKED="$WORK/asked"

# THE STUB FETCH serves whatever has been staged under $MANIFESTS by the name the
# script asks for, and records every name it was asked, so a case can assert
# WHICH manifest was looked for rather than only what came back (L237).
cat > "$WORK/fetch" <<SH
#!/bin/bash
printf '%s\n' "\$1" >> "$ASKED"
[ -f "$MANIFESTS/\$1" ] || exit 1
cat "$MANIFESTS/\$1"
SH
chmod +x "$WORK/fetch"

# A MANIFEST IS THE SHAPE GITHUB PUBLISHES, table and all, not a list of versions.
# A fixture reduced to what the parser finds easy is a fixture that stops
# resembling the thing it stands for (L48).
#
# THE SECTION AFTER THE XCODE TABLE IS DELIBERATELY HARDER THAN THE REAL ONE, and
# that is declared rather than quietly true. Today's manifest follows the Xcode
# table with Installed SDKs, whose first column reads "macOS 26.0" and matches no
# version, so a parser that ran on past the heading would read exactly the same
# Xcodes and no fixture copied from the real file could tell the two apart:
# measured 2026-09-16 against the published macos-26 manifest, both readings gave
# 26.0.1 through 26.6. A guard nothing can make fail is not a guard (L1), so the
# fixture carries a later table whose first cell IS a bare version. It stands for
# a manifest whose shape has changed, which is the only thing that check is for.
manifest_offering() {
    # manifest_offering <file> <version>...
    local file="$MANIFESTS/$1" v first=1
    shift
    {
        echo "# macOS"
        echo "## Installed Software"
        echo "### Xcode"
        echo "| Version        | Build  | Path                           | Symlinks   |"
        echo "| -------------- | ------ | ------------------------------ | ---------- |"
        for v in "$@"; do
            if [ "$first" = 1 ]; then
                echo "| $v (default) | 17F113 | /Applications/Xcode_$v.app | /Applications/Xcode.app |"
                first=0
            else
                echo "| $v           | 17F42  | /Applications/Xcode_$v.app |            |"
            fi
        done
        echo ""
        echo "#### Installed SDKs"
        echo "| SDK        | SDK Name   | Xcode Version |"
        echo "| ---------- | ---------- | ------------- |"
        echo "| macOS 26.0 | macosx26.0 | 26.0.1        |"
        echo ""
        echo "### Rust Tools"
        echo "| Version | Path |"
        echo "| ------- | ---- |"
        echo "| 99.9    | /usr |"
    } > "$file"
}

workflow_on() {
    # workflow_on <file> <runs-on label>...
    local file="$WORK/$1" label
    shift
    {
        echo "name: CI"
        echo "on: [push]"
        echo "jobs:"
        local n=0
        for label in "$@"; do
            n=$((n+1))
            echo "  mac${n}:"
            echo "    runs-on: ${label}"
            echo "    steps:"
            echo "      - run: bash scripts/select-xcode.sh"
        done
        echo "  linux:"
        echo "    runs-on: ubuntu-latest"
        echo "    steps:"
        echo "      - run: bash scripts/run-tests.sh"
    } > "$file"
    printf '%s' "$file"
}

PIN="$WORK/pin"
printf '26.6\n' > "$PIN"
WF_ONE="$(workflow_on ci-one.yml macos-26)"

run_watch() {
    rm -f "$ASKED"
    OVATION_XCODE_VERSION_FILE="${PIN_OVERRIDE:-$PIN}" \
    OVATION_CI_WORKFLOW="${WORKFLOW_OVERRIDE:-$WF_ONE}" \
    OVATION_RUNNER_MANIFEST_COMMAND="${FETCH_OVERRIDE:-$WORK/fetch}" \
        "./$TARGET" 2>&1
}
says() { if grep -qF -- "$2" <<< "$1"; then echo yes; else echo no; fi; }
asked_for() { if grep -qxF -- "$1" "$ASKED" 2>/dev/null; then echo yes; else echo no; fi; }

# ---------------------------------------------------------------------------
# 1. THE PIN IS THE NEWEST THE IMAGE HAS. The healthy day, and it is quiet in the
#    sense that matters: it reports nothing to the tracker. It still SAYS what it
#    measured, because a check whose success prints nothing is one nobody can
#    tell from a check that did not run (L98).
# ---------------------------------------------------------------------------
manifest_offering macos-26-arm64-Readme.md 26.6 26.5 26.4.1
OUT_OK="$(run_watch)"; ST_OK=$?
check "a pin that is the newest the image offers is the healthy outcome" "$ST_OK" "0"
check "and it names the version it compared against" "$(says "$OUT_OK" "26.6")" "yes"
check "and it names the image it read, not just the version" \
    "$(says "$OUT_OK" "macos-26")" "yes"

# ---------------------------------------------------------------------------
# 2. THE IMAGE HAS SOMETHING NEWER. This is the finding ovation#320 is waiting
#    for, and it must name the newer version so the reader knows what arrived.
# ---------------------------------------------------------------------------
manifest_offering macos-26-arm64-Readme.md 27.0 26.6 26.5
OUT_NEW="$(run_watch)"; ST_NEW=$?
check "an image offering a newer Xcode is its own outcome" "$ST_NEW" "3"
check "and it names the newer version that arrived" "$(says "$OUT_NEW" "27.0")" "yes"
check "and it names the version pinned now, so the change is a comparison" \
    "$(says "$OUT_NEW" "26.6")" "yes"

# ---------------------------------------------------------------------------
# 3. THE IMAGE NO LONGER HAS THE PINNED XCODE. Louder, and separate: this is not
#    an opportunity, it is scripts/select-xcode.sh about to refuse and CI about
#    to go red. Distinct causes get distinct messages (L11), and this one takes
#    precedence over "something newer", which is also true here.
# ---------------------------------------------------------------------------
manifest_offering macos-26-arm64-Readme.md 26.8 26.7
OUT_GONE="$(run_watch)"; ST_GONE=$?
check "an image that has dropped the pinned Xcode is a different outcome" "$ST_GONE" "4"
check "and it says the CI build is what breaks, not that an upgrade is available" \
    "$(says "$OUT_GONE" "refuse")" "yes"
check "and it lists what the image does have, so the next pin is a choice" \
    "$(says "$OUT_GONE" "26.8")" "yes"

# 3b. DROPPED, WITH NOTHING NEWER EITHER. The same outcome: what matters is that
#     the pinned version is gone, not where the survivors sit relative to it.
manifest_offering macos-26-arm64-Readme.md 26.5 26.4.1
OUT_GONE_OLD="$(run_watch)"; ST_GONE_OLD=$?
check "a dropped pin is reported even when nothing newer replaced it" "$ST_GONE_OLD" "4"

# ---------------------------------------------------------------------------
# 4. VERSIONS COMPARE AS NUMBERS, NEVER AS TEXT. 26.10 is newer than 26.9, and a
#    string comparison puts it earlier. This is the whole watcher: get it wrong
#    and it reports the healthy day for ever while a newer Xcode sits there.
# ---------------------------------------------------------------------------
printf '26.9\n' > "$WORK/pin-26-9"
PIN_OVERRIDE="$WORK/pin-26-9"
manifest_offering macos-26-arm64-Readme.md 26.10 26.9
OUT_NUM="$(run_watch)"; ST_NUM=$?
check "26.10 is read as newer than 26.9, not older" "$ST_NUM" "3"
check "and the newer one is named as the one that arrived" "$(says "$OUT_NUM" "26.10")" "yes"

# AND THE OTHER DIRECTION, so the case above is not satisfied by a comparison
# that simply always answers "newer" (L159).
manifest_offering macos-26-arm64-Readme.md 26.9 26.8
OUT_NUM2="$(run_watch)"
check "and a pin that is still the newest is not reported as behind" "$?" "0"
# ON THE CLAIM, NOT ON A WORD IN IT (L347). The healthy outcome lists everything
# the image offers, 26.8 included, and asserting that the older version is absent
# would be asserting the inventory is missing rather than that nothing arrived.
check "and it does not claim something newer arrived" \
    "$(says "$OUT_NUM2" "newer than the pinned")" "no"
unset PIN_OVERRIDE

# ---------------------------------------------------------------------------
# 5. THE LABEL IS READ FROM THE WORKFLOW, never written here a second time. The
#    runner name lives in .github/workflows/ci.yml, and a copy of it in this
#    script is a list maintained by hand beside its source (L41).
# ---------------------------------------------------------------------------
WORKFLOW_OVERRIDE="$(workflow_on ci-other.yml macos-99)"
manifest_offering macos-99-arm64-Readme.md 26.6
run_watch >/dev/null
check "the manifest asked for is the one the workflow's runner names" \
    "$(asked_for "macos-99-arm64-Readme.md")" "yes"
unset WORKFLOW_OVERRIDE

# ---------------------------------------------------------------------------
# 6. TWO DIFFERENT MAC RUNNERS IS A REFUSAL, never whichever came first. "The
#    image CI builds on" is not a question with one answer then, and answering it
#    anyway would report about one job while the other drifted (L521).
# ---------------------------------------------------------------------------
WORKFLOW_OVERRIDE="$(workflow_on ci-two.yml macos-26 macos-15)"
OUT_TWO="$(run_watch)"; ST_TWO=$?
check "a workflow naming two different Mac runners is refused" "$ST_TWO" "1"
check "and the refusal names both, so the reader can see the drift" \
    "$(says "$OUT_TWO" "macos-15")" "yes"
unset WORKFLOW_OVERRIDE

# BUT THE SAME LABEL TWICE IS NOT A DISAGREEMENT. Ovation's ci.yml really does
# carry two Mac jobs, and both name macos-26, which is the ordinary case.
WORKFLOW_OVERRIDE="$(workflow_on ci-same.yml macos-26 macos-26)"
manifest_offering macos-26-arm64-Readme.md 26.6
run_watch >/dev/null
check "two Mac jobs on the same runner are one answer, not a disagreement" "$?" "0"
unset WORKFLOW_OVERRIDE

# ---------------------------------------------------------------------------
# 7. THE ARM64 MANIFEST IS PREFERRED, because that is what the label provisions
#    now, and the plain one is a fallback rather than an alternative.
# ---------------------------------------------------------------------------
rm -f "$MANIFESTS/macos-26-arm64-Readme.md"
manifest_offering macos-26-Readme.md 26.6
OUT_FALLBACK="$(run_watch)"; ST_FALLBACK=$?
check "an image with no arm64 manifest falls back to the plain one" "$ST_FALLBACK" "0"
check "and the arm64 name was tried first" \
    "$(asked_for "macos-26-arm64-Readme.md")" "yes"

# ---------------------------------------------------------------------------
# 8. EVERY WAY OF NOT KNOWING IS CANNOT MEASURE, and each names its own cause.
#    None of them may exit 0: a watcher that reports the healthy day when it
#    could not look is the failure this whole design is guarding against (L98).
# ---------------------------------------------------------------------------
rm -f "$MANIFESTS/macos-26-Readme.md"
OUT_NOFETCH="$(run_watch)"; ST_NOFETCH=$?
check "a manifest that cannot be fetched cannot be measured" "$ST_NOFETCH" "2"
check "and it names the manifest it could not read" \
    "$(says "$OUT_NOFETCH" "macos-26")" "yes"

manifest_offering macos-26-arm64-Readme.md 26.6
PIN_OVERRIDE="$WORK/no-such-pin"
OUT_NOPIN="$(run_watch)"; ST_NOPIN=$?
check "a pin that cannot be read cannot be measured" "$ST_NOPIN" "2"
check "and it names the pin file, not the image" \
    "$(says "$OUT_NOPIN" "no-such-pin")" "yes"
unset PIN_OVERRIDE

WORKFLOW_OVERRIDE="$WORK/no-such-workflow.yml"
OUT_NOWF="$(run_watch)"; ST_NOWF=$?
check "a workflow that is not there cannot be measured" "$ST_NOWF" "2"
unset WORKFLOW_OVERRIDE

WORKFLOW_OVERRIDE="$(workflow_on ci-linux.yml)"
OUT_NOMAC="$(run_watch)"; ST_NOMAC=$?
check "a workflow with no Mac runner at all cannot be measured" "$ST_NOMAC" "2"
check "and it says that is what was missing" "$(says "$OUT_NOMAC" "runs-on")" "yes"
unset WORKFLOW_OVERRIDE

# A MANIFEST THAT ARRIVED AND HELD NO XCODE TABLE. This is the one that would
# otherwise pass as healthy: nothing newer was found, because nothing was found.
printf '# macOS\n## Installed Software\n### Rust\n- 1.9\n' > "$MANIFESTS/macos-26-arm64-Readme.md"
OUT_NOTABLE="$(run_watch)"; ST_NOTABLE=$?
check "a manifest carrying no Xcode table cannot be measured" "$ST_NOTABLE" "2"
check "and it does not report the pin as newest by default" \
    "$(says "$OUT_NOTABLE" "newest")" "no"

# ---------------------------------------------------------------------------
# 9. IT CHANGES NOTHING. Its name says it inspects, and a name that reads like an
#    inspection must not write (L206). The pin is the file it would be most
#    tempting to correct.
# ---------------------------------------------------------------------------
manifest_offering macos-26-arm64-Readme.md 27.0 26.6
BEFORE_PIN="$(cat "$PIN")"
run_watch >/dev/null
check "a run that found a newer Xcode did not edit the pin" "$(cat "$PIN")" "$BEFORE_PIN"

harness_end
