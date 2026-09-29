#!/bin/bash
# Whether the backstage release watch can tell apart the four things the pin can be.
#
# ovation#576. project.yml pins backstage to one exact version, and an exact pin
# never looks for a newer one, so 0.4.0 and 0.5.0 were both published while this
# app went on building 0.3.0 and nothing said so. Moving the pin stays a person's
# decision, because a new version must arrive with this app's own suite run
# against it; noticing that one EXISTS is what scripts/check-backstage-release.sh
# does, daily, from .github/workflows/backstage-release.yml.
#
# Every case drives the script against a staged project.yml and a stub for the
# tag listing, because a suite that could only pass by reaching GitHub would be
# asserting about what backstage published this week rather than about this
# script (L2, L291). The one exception reads the REAL project.yml, and checks it
# against the version Package.resolved commits, which is a second source rather
# than the pin agreeing with itself (L70).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "backstage release watch tests" 33

TARGET="scripts/check-backstage-release.sh"
require_target "$TARGET"
harness_temp_dir WORK

# A SPEC IN THE SHAPE project.yml HAS, with ViewInspector's exact pin FIRST and
# deliberately different, so a reader that took the first exactVersion in the
# file would report the wrong package's version and be caught (L237).
spec_pinning() {
    # spec_pinning <file> <pin line for backstage>
    cat > "$WORK/$1" <<EOF
name: Ovation
packages:
  ViewInspector:
    url: https://github.com/nalexn/ViewInspector
    exactVersion: "9.9.9"
  # a comment inside the block, as the real one carries
  BackstageGoogle:
    url: https://github.com/danwright32/backstage
    $2
options:
  bundleIdPrefix: com.danwright
EOF
    printf '%s' "$WORK/$1"
}
SPEC="$(spec_pinning spec.yml 'exactVersion: "0.5.0"')"

# THE STUB LISTING prints what git ls-remote --tags prints, from a staged file,
# and fails the first N calls when told to, so a retry can be driven (ovation#380).
TAGS="$WORK/tags"
FAILS_LEFT="$WORK/fails-left"
CALLS="$WORK/calls"
cat > "$WORK/list" <<SH
#!/bin/bash
echo call >> "$CALLS"
left="\$(cat "$FAILS_LEFT" 2>/dev/null || echo 0)"
if [ "\$left" -gt 0 ]; then echo \$((left - 1)) > "$FAILS_LEFT"; exit 1; fi
[ -f "$TAGS" ] || exit 1
cat "$TAGS"
SH
chmod +x "$WORK/list"
tags_are() {
    : > "$TAGS"
    local t
    for t in "$@"; do printf '0123456789abcdef0123456789abcdef01234567\trefs/tags/%s\n' "$t" >> "$TAGS"; done
}

SLEPT="$WORK/slept"
# A QUOTED HEREDOC, so the stub's own argument is never written on a line of this
# suite: scripts/test-run-tests.sh refuses a suite reading a positional argument
# (L245), and a printf carrying one reads as exactly that.
cat > "$WORK/sleep" <<'SH'
#!/bin/bash
echo "$1" >> "$OVATION_TEST_SLEPT"
SH
chmod +x "$WORK/sleep"
export OVATION_TEST_SLEPT="$SLEPT"

run_watch() {
    rm -f "$SLEPT" "$CALLS"
    OVATION_PROJECT_SPEC="${SPEC_OVERRIDE:-$SPEC}" \
    OVATION_BACKSTAGE_TAGS_COMMAND="$WORK/list" \
    OVATION_BACKSTAGE_FETCH_SLEEP="$WORK/sleep" \
        "./$TARGET" 2>&1
}
says() { if grep -qF -- "$2" <<< "$1"; then echo yes; else echo no; fi; }
count_of() { grep -c . "$1" 2>/dev/null || echo 0; }

# 1. THE PIN IS THE NEWEST RELEASE. The healthy day still SAYS what it compared,
#    because a check whose success prints nothing cannot be told from one that
#    did not run (L98).
tags_are 0.1.0 0.3.0 0.5.0
OUT="$(run_watch)"; ST=$?
check "a pin that is the newest release is the healthy outcome" "$ST" "0"
check "and it names the version it compared" "$(says "$OUT" "0.5.0")" "yes"
check "and it read backstage's pin, not the first exact pin in the file" "$(says "$OUT" "9.9.9")" "no"

# 2. A NEWER RELEASE EXISTS, which is the finding. It names every release past
#    the pin, because each one's notes are what somebody has to read before moving.
SPEC_OVERRIDE="$(spec_pinning spec-old.yml 'exactVersion: "0.3.0"')"
tags_are 0.1.0 0.3.0 0.4.0 0.5.0
OUT="$(run_watch)"; ST=$?
check "a newer release than the pin is its own outcome" "$ST" "3"
check "and it names the newest" "$(says "$OUT" "0.5.0")" "yes"
check "and every release in between, whose notes also have to be read" "$(says "$OUT" "0.4.0")" "yes"
check "and the version pinned now, so the finding is a comparison" "$(says "$OUT" "0.3.0")" "yes"
check "and it does not list a release older than the pin as news" "$(says "$OUT" "0.1.0")" "no"
unset SPEC_OVERRIDE

# 3. VERSIONS COMPARE AS NUMBERS. 0.10.0 is newer than 0.9.0 and sorts earlier as
#    text, so a string comparison would report the healthy day for ever.
SPEC_OVERRIDE="$(spec_pinning spec-nine.yml 'exactVersion: "0.9.0"')"
tags_are 0.9.0 0.10.0
OUT="$(run_watch)"; ST=$?
check "0.10.0 is newer than 0.9.0" "$ST" "3"
unset SPEC_OVERRIDE

# 4. ONLY RELEASE VERSIONS COUNT. A pre-release or any other tag is not a
#    release to move to, and it must neither fire the finding nor break the read.
tags_are 0.5.0 0.6.0-rc1 nightly
OUT="$(run_watch)"; ST=$?
check "a pre-release or a stray tag is not a newer release" "$ST" "0"

# 5. AN ANNOTATED TAG IS LISTED TWICE, once peeled with ^{}. It is the same
#    release, read as a version, not a second one and not an unreadable one.
: > "$TAGS"
printf 'aaaa\trefs/tags/0.5.0\nbbbb\trefs/tags/0.6.0\ncccc\trefs/tags/0.6.0^{}\n' >> "$TAGS"
OUT="$(run_watch)"; ST=$?
check "a peeled annotated tag is read as its version" "$ST" "3"
check "and listed once, not twice" "$(grep -c 'releases/tag/0\.6\.0' <<< "$OUT")" "1"

# 6. THE PINNED VERSION IS NOT A PUBLISHED TAG. A fresh checkout cannot resolve
#    it, so this is not an upgrade going spare and it is not reported as one: it
#    refuses, and takes precedence over a newer release also being there (L11).
SPEC_OVERRIDE="$(spec_pinning spec-gone.yml 'exactVersion: "0.4.1"')"
tags_are 0.4.0 0.5.0
OUT="$(run_watch)"; ST=$?
check "a pin that names no published tag refuses" "$ST" "1"
check "and it says the pinned version is not there" "$(says "$OUT" "0.4.1")" "yes"
unset SPEC_OVERRIDE

# 7. THE LISTING CANNOT BE READ. Never the healthy day: a fetch that failed is
#    not backstage having published nothing (L98). It tries three times first,
#    through an injectable sleep, so one dropped request is not an outage (L524).
tags_are 0.5.0
echo 99 > "$FAILS_LEFT"
OUT="$(run_watch)"; ST=$?
check "a listing that cannot be read is CANNOT MEASURE" "$ST" "2"
check "after three attempts" "$(count_of "$CALLS")" "3"
check "with a wait between them and none after the last" "$(count_of "$SLEPT")" "2"
check "and it says how many attempts it made" "$(says "$OUT" "3 attempts")" "yes"
rm -f "$FAILS_LEFT"

# 8. ONE FAILED ATTEMPT THEN A GOOD ONE is the healthy answer, read on the retry.
echo 1 > "$FAILS_LEFT"
OUT="$(run_watch)"; ST=$?
check "a listing that fails once and then answers is judged on the answer" "$ST" "0"
check "on the second attempt" "$(count_of "$CALLS")" "2"
rm -f "$FAILS_LEFT"

# 9. A LISTING THAT ANSWERS WITH NO RELEASE AT ALL. A repository holding no
#    version tag is not one whose newest release is the pin.
tags_are nightly 0.6.0-rc1
OUT="$(run_watch)"; ST=$?
check "a listing holding no release version is CANNOT MEASURE" "$ST" "2"

# 10. THE PIN CANNOT BE READ, three ways, each CANNOT MEASURE rather than a guess.
SPEC_OVERRIDE="$WORK/absent.yml"
OUT="$(run_watch)"; ST=$?
check "no project.yml is CANNOT MEASURE" "$ST" "2"
SPEC_OVERRIDE="$(spec_pinning spec-range.yml 'from: "0.3.0"')"
OUT="$(run_watch)"; ST=$?
check "a backstage entry with no exact version is CANNOT MEASURE" "$ST" "2"
check "and it says the pin is not exact, rather than guessing from the range" "$(says "$OUT" "exactVersion")" "yes"
cat > "$WORK/spec-none.yml" <<'EOF'
packages:
  ViewInspector:
    url: https://github.com/nalexn/ViewInspector
    exactVersion: "9.9.9"
EOF
SPEC_OVERRIDE="$WORK/spec-none.yml"
OUT="$(run_watch)"; ST=$?
check "a project.yml with no backstage entry is CANNOT MEASURE" "$ST" "2"
unset SPEC_OVERRIDE

# 11. IT READS AND CHANGES NOTHING, whatever it found (L206).
SPEC_OVERRIDE="$(spec_pinning spec-ro.yml 'exactVersion: "0.3.0"')"
BEFORE="$(cat "$SPEC_OVERRIDE")"
tags_are 0.3.0 0.5.0
run_watch > /dev/null
check "a run that found a newer release did not edit the pin" "$(cat "$SPEC_OVERRIDE")" "$BEFORE"
unset SPEC_OVERRIDE

# 12. THE REAL project.yml IS READABLE, and what it reads is the version the
#     committed Package.resolved records for backstage, a second source (L70).
RESOLVED="Ovation.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
RESOLVED_VERSION="$(python3 -c 'import json,sys; print(next(p["state"]["version"] for p in json.load(open(sys.argv[1]))["pins"] if p["identity"] == "backstage"))' "$RESOLVED" 2>/dev/null)"
tags_are "$RESOLVED_VERSION"
OUT="$(SPEC_OVERRIDE="$PWD/project.yml" run_watch)"; ST=$?
check "the real project.yml pins the version Package.resolved records, and it is read" \
    "$ST:$(says "$OUT" "$RESOLVED_VERSION")" "0:yes"

# 13. THE WIRING THE REPORTING PATH RUNS THROUGH, as test-check-runner-xcode.sh
#     asserts for its own workflow (ovation#379, L151). Every outcome the check
#     documents is handled by exactly one step, and every step's condition names
#     an outcome that exists.
documented_codes() { grep -oE '^#   [0-9]  ' "$TARGET" | tr -dc '0-9\n' | sort -u; }
handled_codes() { grep -oE "outputs\.status == '[0-9]'" "$1" | tr -dc '0-9\n' | sort; }
wiring_gaps() {
    local wf="$1" code
    for code in $(documented_codes); do
        [ "$(handled_codes "$wf" | grep -cx "$code")" -eq 1 ] || echo "outcome $code handled $(handled_codes "$wf" | grep -cx "$code") time(s)"
    done
    for code in $(handled_codes "$wf" | sort -u); do
        documented_codes | grep -qx "$code" || echo "condition on $code, which the check never exits with"
    done
}
check "every outcome the check documents is handled by exactly one step of its workflow" \
    "$(wiring_gaps .github/workflows/backstage-release.yml)" ""
sed "s/outputs.status == '3'/outputs.status == '8'/" .github/workflows/backstage-release.yml > "$WORK/broken-wiring.yml"
check "and a workflow whose condition stopped matching an outcome is caught" \
    "$(wiring_gaps "$WORK/broken-wiring.yml" | grep -c .)" "2"
check "and the check documents four outcomes, so the comparison has something to compare" \
    "$(documented_codes | grep -c .)" "4"


# 14. THE FINDING'S TITLE IS WRITTEN ONCE. report-finding.sh finds the open issue
#     by its exact title, so a close step carrying its own copy that drifted from
#     the filing step's would match nothing and exit 3, which is the ordinary
#     "none was open" state: the finding would stay open for ever with every run
#     green (L41). So the title is one workflow level variable, it is the only
#     place the words appear, and every report-finding call passes that variable.
title_gaps() {
    local wf="$1" defined titles
    defined="$(grep -cE '^  FINDING_TITLE: ' "$wf")"
    [ "$defined" -eq 1 ] || echo "FINDING_TITLE defined $defined time(s) at workflow level"
    titles="$(grep -E -- '--title ' "$wf")"
    [ -n "$titles" ] || echo "no report-finding call passes a title"
    grep -vF -- '--title "${FINDING_TITLE}"' <<< "$titles" | grep -q . && echo "a call passes a title other than FINDING_TITLE"
    local words
    words="$(sed -nE 's/^  FINDING_TITLE: (.*)$/\1/p' "$wf")"
    [ -z "$words" ] || [ "$(grep -cF -- "$words" "$wf")" -eq 1 ] || echo "the title's words are written more than once"
}
check "the finding's title is defined once and every report-finding call passes it" \
    "$(title_gaps .github/workflows/backstage-release.yml)" ""
check "and there are two calls passing it, the filing and the close" \
    "$(grep -cF -- '--title "${FINDING_TITLE}"' .github/workflows/backstage-release.yml)" "2"
# The SECOND call only, by awk rather than sed's 0,/re/ address, which BSD sed on
# this Mac does not have and GNU sed on the Linux job does (L434).
awk -v copy='--title "backstage has a release newer than the one Ovation pins"' '
    index($0, "--title \"${FINDING_TITLE}\"") { n++; if (n == 2) sub(/--title "\$\{FINDING_TITLE\}"/, copy) }
    { print }
' .github/workflows/backstage-release.yml > "$WORK/second-copy.yml"
check "and a close step carrying its own copy of the words is caught" \
    "$(title_gaps "$WORK/second-copy.yml" | grep -c .)" "2"

harness_end
