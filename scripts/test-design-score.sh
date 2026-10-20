#!/bin/bash
# The design match score runner, driven with stand ins for the score's tools and
# for the test runner, so every refusal and every hand off is seen here without a
# browser, a build or the shared tools in ~/.claude.
#
# ovation#760. The real run is proved by hand both ways (the proof screen at 100%,
# then a colour changed on purpose and below it), because it needs Playwright, the
# app build and the sibling locks; what this suite holds is the ORDER, the STOPS
# and the EXIT CODE. A runner that went on to score after a snapshot that failed
# would score the previous run's pictures and report them as this one's (L98), and
# one that exited 0 on its own success rather than the score's would read as a
# match on every run.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "design score runner tests" 25

TARGET="scripts/design-score.sh"
require_target "$TARGET"
harness_temp_dir WORK
[ -n "$WORK" ] || exit 1

ADAPTER_REL="vendor/design-score/DesignScoreCapture.swift"

# The score's tools, as the shared folder lays them out. Each records how it was
# called in one log, in order, and fails when told to.
TOOLS="$WORK/tools"
mkdir -p "$TOOLS/swiftui/DesignScoreTests"
echo "// the adapter, as claude-config has it" > "$TOOLS/swiftui/DesignScoreTests/DesignScoreCapture.swift"
cat > "$TOOLS/capture-web.mjs" <<'JS'
import fs from "node:fs";
const args = process.argv.slice(2);
fs.appendFileSync(process.env.FAKE_LOG, "capture " + args.join(" ") + "\n");
const out = args[args.indexOf("--out") + 1];
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(out + "/capture.json", "{}");
process.exit(Number(process.env.FAKE_CAPTURE_EXIT || 0));
JS
cat > "$TOOLS/design_score.py" <<'PY'
import os, sys
with open(os.environ["FAKE_LOG"], "a") as fh:
    fh.write(" ".join(["score-tool"] + sys.argv[1:]) + "\n")
if sys.argv[1] == "score":
    print("fake score")
    sys.exit(int(os.environ.get("FAKE_SCORE_EXIT", "0")))
sys.exit(int(os.environ.get("FAKE_POST_EXIT", "0")))
PY

# A throwaway repository holding the runner, a stand in for run-tests.sh, two
# designs, the adapter's copy and one snapshot suite.
REPO="$WORK/repo"
mkdir -p "$REPO/scripts" "$REPO/docs/design" "$REPO/OvationHostedTests/DesignScore" "$REPO/vendor/design-score" "$REPO/elsewhere"
cp "$TARGET" "$REPO/scripts/design-score.sh"
cat > "$REPO/scripts/run-tests.sh" <<'SH'
#!/bin/bash
echo "tests $* capture=${TEST_RUNNER_DESIGN_SCORE_CAPTURE:-} commit=${TEST_RUNNER_DESIGN_SCORE_COMMIT:-} dirty=${TEST_RUNNER_DESIGN_SCORE_DIRTY:-}" >> "$FAKE_LOG"
exit "${FAKE_TESTS_EXIT:-0}"
SH
echo "<!doctype html>" > "$REPO/docs/design/proof.html"
echo "<!doctype html>" > "$REPO/docs/design/clients.html"
echo "<!doctype html>" > "$REPO/elsewhere/other.html"
cp "$TOOLS/swiftui/DesignScoreTests/DesignScoreCapture.swift" "$REPO/$ADAPTER_REL"
echo "struct ProofDesignScoreTests {}" > "$REPO/OvationHostedTests/DesignScore/ProofDesignScoreTests.swift"
( cd "$REPO" && git init -q -b main && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm x ) >/dev/null 2>&1
HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"

LOG="$WORK/log"
run() {
  : > "$LOG"
  ( cd "$REPO" && TMPDIR="$WORK" FAKE_LOG="$LOG" DESIGN_SCORE_TOOLS="${TOOLS_FOR_RUN:-$TOOLS}" bash scripts/design-score.sh "$@" 2>&1 )
}
logged() { grep -c "^$1" "$LOG"; }
field() { grep "^tests " "$LOG" | tr ' ' '\n' | sed -n "s/^$1=//p"; }

OUT="$(run)"; ST=$?
check "with no screen named it refuses as could not score" "$ST" "2"
OUT="$(run nowhere)"; ST=$?
check "a screen with no design file refuses as could not score" "$ST" "2"
check "and names the file it looked for" "$(grep -c 'docs/design/nowhere.html' <<< "$OUT")" "1"
check "and ran nothing" "$(grep -c . "$LOG")" "0"
OUT="$(run clients)"; ST=$?
check "a design with no snapshot suite refuses, naming the suite it needs" \
    "$ST $(grep -c 'ClientsDesignScoreTests' <<< "$OUT")" "2 1"
OUT="$(TOOLS_FOR_RUN="$WORK/no-tools" run proof)"; ST=$?
check "without the score's tools it refuses rather than skipping the score" "$ST $(grep -c . "$LOG")" "2 0"

# THE ADAPTER IS A COPY, and a copy that has fallen behind draws the build side
# with code the score was not written against.
echo "// changed here" >> "$REPO/$ADAPTER_REL"
OUT="$(run proof)"; ST=$?
check "an adapter copy that differs from the shared one refuses" "$ST $(grep -c . "$LOG")" "2 0"
check "and says the command that refreshes it" "$(grep -c "cp .*DesignScoreCapture.swift" <<< "$OUT")" "1"
git -C "$REPO" checkout -q -- "$ADAPTER_REL"

OUT="$(run proof)"; ST=$?
check "a matched score exits 0" "$ST" "0"
check "the design side is drawn alone, from the design file" \
    "$(grep -c "^capture --design $REPO/docs/design/proof.html --out .* --design-only$" "$LOG")" "1"
CAPTURE="$(sed -n 's/^capture .* --out \([^ ]*\) .*/\1/p' "$LOG")"
check "then the screen's snapshot suite runs through the test runner" \
    "$(grep -c '^tests --only OvationHostedTests/ProofDesignScoreTests ' "$LOG")" "1"
check "handed the same capture folder" "$(field capture)" "$CAPTURE"
check "and the commit it is drawing" "$(field commit)" "$HEAD_SHA"
check "and that nothing is uncommitted" "$(field dirty)" "0"
check "then the capture is scored, in that order" \
    "$(cut -d' ' -f1 "$LOG" | tr '\n' ' ')" "capture tests score-tool "
check "the score reads the same folder" "$(grep -c "^score-tool score $CAPTURE$" "$LOG")" "1"

OUT="$(FAKE_SCORE_EXIT=1 run proof)"; ST=$?
check "not matched yet is the score's 1, passed through" "$ST" "1"

echo changed > "$REPO/docs/design/proof.html"
run proof >/dev/null
check "a checkout with uncommitted changes says so to the snapshot" "$(field dirty)" "1"
git -C "$REPO" checkout -q -- docs/design/proof.html

OUT="$(FAKE_CAPTURE_EXIT=2 run proof)"; ST=$?
check "a design side that failed stops the run, as could not score" "$ST $(logged tests)" "2 0"
OUT="$(FAKE_TESTS_EXIT=65 run proof)"; ST=$?
check "a snapshot that failed stops before the score reads stale pictures" "$ST $(logged score-tool)" "2 0"

OUT="$(FAKE_SCORE_EXIT=1 run proof --pr 12)"; ST=$?
CAPTURE="$(sed -n 's/^capture .* --out \([^ ]*\) .*/\1/p' "$LOG")"
check "with a pull request named, this run's score is posted on it" \
    "$ST $(grep -c "^score-tool post $CAPTURE/score.json --repo danwright32/ovation --pr 12$" "$LOG")" "1 1"
OUT="$(FAKE_SCORE_EXIT=2 run proof --pr 12)"; ST=$?
check "and no score is never posted as one" "$ST $(grep -c 'score-tool post' "$LOG")" "2 0"
# design_score.py post exits 0 posted on both, 1 posted on the pull request only
# (no Match issue in its milestone), 2 nothing posted. Found on #764: the proof's
# score posted and the runner said it could not be, because it read 1 as failure.
OUT="$(FAKE_SCORE_EXIT=0 FAKE_POST_EXIT=1 run proof --pr 12)"; ST=$?
check "a score posted on the pull request only is still the score, and says where it went" \
    "$ST $(grep -c 'could not be posted' <<< "$OUT") $(grep -c 'on #12 only' <<< "$OUT")" "0 0 1"
OUT="$(FAKE_SCORE_EXIT=0 FAKE_POST_EXIT=2 run proof --pr 12)"; ST=$?
check "a post that failed is said, not passed off as the score" "$ST $(grep -c 'could not be posted' <<< "$OUT")" "2 1"

OUT="$(run proof --design elsewhere/other.html)"; ST=$?
check "a design file kept elsewhere can be named instead" \
    "$ST $(grep -c "^capture --design $REPO/elsewhere/other.html " "$LOG")" "0 1"

harness_end
