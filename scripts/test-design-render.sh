#!/bin/bash
# The suite for scripts/lib/design_render.py, the renderer every design check uses.
#
# ovation#316. CI run 34882448119 failed in scripts/test-clients-screen-draws.sh
# with `CANNOT MEASURE: the browser did not answer its Page.navigate request
# within 120 seconds`, twice, while the browser printed `Trying to load the
# allocator multiple times. This is *not* supported`. The same suite passed 53 of
# 53 locally on both pushes of that branch and the only change to the page was
# comment text, so the change did not cause it. Scanned on 2026-09-15 across every
# CI run of this repository that did not succeed: ONE occurrence, the one the
# issue names, with 32 runs whose logs could no longer be read and which therefore
# measure nothing either way.
#
# So the browser can stop answering for reasons that have nothing to do with the
# page, and when it does, one check's whole run is lost and an unrelated pull
# request goes red. The renderer now starts a FRESH browser and renders that page
# again, once, and SAYS it did, because a fault that heals silently cannot be
# counted and the next occurrence would look like the first (L293).
#
# WHY THIS SUITE DID NOT EXIST BEFORE. Every other rendering suite drives a TOOL
# and needs a real browser, so all of them answer CANNOT MEASURE where there is
# none. This drives the LIBRARY against a stand in browser that speaks just enough
# DevTools over the pipe, so the restart is exercised on every machine, including
# the Linux job, and the fault can be STAGED rather than waited for (L2, L291).
#
# The stand in is deliberately small and says so: it answers the six requests the
# renderer makes and nothing else. It is not a browser and the suites that need a
# real one still use one.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "design renderer tests" 27

TARGET="scripts/lib/design_render.py"
require_target "$TARGET"
harness_temp_dir WORK

# ---------------------------------------------------------------------------
# THE STAND IN BROWSER. It reads NUL terminated JSON on fd 3 and writes replies
# on fd 4, which is where the renderer puts the pipe.
#
# WHICH RUN IT IS ON is counted in a file, because a restart is a NEW PROCESS and
# the fault has to be staged for the first browser and not the second. That count
# is also what proves a restart happened at all, from outside the renderer (L70).
# ---------------------------------------------------------------------------
cat > "$WORK/fake-browser" <<'FAKE'
#!/usr/bin/env python3
import json, os, time

state = os.environ["FAKE_STATE"]
silent = {int(n) for n in os.environ.get("FAKE_SILENT_RUNS", "").split(",") if n.strip()}
no_report = os.environ.get("FAKE_NO_REPORT", "")
with open(os.path.join(state, "runs"), "a") as handle:
    handle.write("x")
run = os.path.getsize(os.path.join(state, "runs"))

url = "about:blank"
buffer = b""
while True:
    chunk = os.read(3, 1 << 16)
    if not chunk:
        break
    buffer += chunk
    while b"\0" in buffer:
        raw, buffer = buffer.split(b"\0", 1)
        message = json.loads(raw)
        method, params = message.get("method"), message.get("params") or {}
        if method == "Browser.close":
            raise SystemExit(0)
        if method == "Page.navigate":
            url = params.get("url", url)
            if run in silent:
                # THE FAULT: the request is never answered. The renderer's own
                # deadline is what ends this, which is the shape CI saw.
                while True:
                    time.sleep(3600)
        if method == "Target.createTarget":
            result = {"targetId": "T%d" % run}
        elif method == "Target.attachToTarget":
            result = {"sessionId": "S%d" % run}
        elif method == "Runtime.evaluate":
            result = {"result": {"value": {"href": url, "ready": "complete",
                                           "report": None if no_report else json.dumps({"ran": run}),
                                           "bytes": 120}}}
        else:
            result = {}
        os.write(4, json.dumps({"id": message.get("id"), "result": result}).encode("utf-8") + b"\0")
FAKE
chmod +x "$WORK/fake-browser"

printf '<!doctype html>\n<html><body>a page</body></html>\n' > "$WORK/page.html"

# One render, reported the way a tool reports it.
cat > "$WORK/render-once.py" <<'DRIVER'
import json, os, sys
sys.path.insert(0, os.environ["LIBDIR"])
from design_render import CannotMeasure, open_browser

try:
    with open_browser() as browser:
        print("REPORT " + json.dumps(browser.render(os.environ["PAGE"], "<script>1</script>")))
except CannotMeasure as refusal:
    print("CANNOT MEASURE: %s" % refusal)
    sys.exit(3)
DRIVER

# $1 the runs that stay silent, as a comma list. Every seam is set, so no case can
# reach a real browser or a real design file (L2, L284).
render() {
    rm -rf "$WORK/state"; mkdir -p "$WORK/state"
    # A SUBSHELL, and every variable EXPORTED in it. An assignment built by
    # expansion is not read as an assignment at all, so the optional one below
    # became a command name and the case answered 127 rather than the refusal it
    # was about (measured while writing this).
    (
        export FAKE_STATE="$WORK/state" FAKE_SILENT_RUNS="$1"
        export LIBDIR="$PWD/scripts/lib" PAGE="$WORK/page.html"
        export OVATION_HEADLESS_BROWSER="$WORK/fake-browser"
        export OVATION_RENDER_TIMEOUT="${TIMEOUT_OVERRIDE:-1}"
        export OVATION_RENDER_WAIT_MS=200
        [ -n "${NO_REPORT_OVERRIDE:-}" ] && export FAKE_NO_REPORT="$NO_REPORT_OVERRIDE"
        [ -n "${RESTARTS_OVERRIDE:-}" ] && export OVATION_RENDER_RESTARTS="$RESTARTS_OVERRIDE"
        # NAMED OR CLEARED, never inherited (L439, L284). CI SETS this seam for
        # the whole Linux job, so a case that merely left it alone would write a
        # fault this suite STAGED into the record the workflow carries to the
        # tracker, and a staged fault would be reported as a real one.
        if [ -n "${LOG_OVERRIDE:-}" ]; then
            export OVATION_RENDER_RESTART_LOG="$LOG_OVERRIDE"
        else
            unset OVATION_RENDER_RESTART_LOG
        fi
        # A HOME OF ITS OWN, on every case (ovation#332). The default record lives
        # under the home directory, and a case that forgot to name one would
        # otherwise append to Dan's real record from a fault this suite STAGED
        # (L2). It is exported here rather than in the one case that asserts it,
        # so no case written later can reach the real file by omission (L284).
        export HOME="$WORK/home"
        python3 "$WORK/render-once.py" 2>&1
    )
}
render_status() { render "$1" >/dev/null 2>&1; printf '%s' "$?"; }
browsers_started() { printf '%s' "$(wc -c < "$WORK/state/runs" | tr -d ' ')"; }

# ---------------------------------------------------------------------------
# THE CONTROL FIRST. A case that stages a fault proves nothing until the same
# fixture is seen to WORK without it (L159).
# ---------------------------------------------------------------------------
check "an ordinary render returns the probe's report" \
    "$(render "" | grep -c '^REPORT {"ran": 1}')" "1"
check "and it starts one browser and no more" "$(browsers_started)" "1"

# ---------------------------------------------------------------------------
# THE CASE THIS EXISTS FOR: the browser stops answering Page.navigate.
# ---------------------------------------------------------------------------
check "a browser that stops answering is started again and the page renders" \
    "$(render 1 | grep -c '^REPORT {"ran": 2}')" "1"
check "and the second browser is the one that answered" "$(browsers_started)" "2"
check "and the restart is said out loud, so it can be counted" \
    "$(render 1 | grep -c 'started a fresh browser')" "1"
check "and the restart line itself names the request that went unanswered" \
    "$(render 1 | grep 'started a fresh browser' | grep -c 'Page.navigate')" "1"

# ---------------------------------------------------------------------------
# AND THE RESTART IS WHAT SAVES IT, not something else about the fixture: the
# same fault with restarts turned off is the refusal CI reported (L1).
# ---------------------------------------------------------------------------
RESTARTS_OVERRIDE=0
check "with restarts turned off the same fault refuses" "$(render_status 1)" "3"
check "and refuses in the words CI reported" \
    "$(render 1 | grep -c 'did not answer its Page.navigate request')" "1"
unset RESTARTS_OVERRIDE

# ---------------------------------------------------------------------------
# A BROWSER THAT NEVER ANSWERS IS STILL A REFUSAL. The retry is one attempt, not
# a loop: a check that hangs forever is worse than one that fails (L110).
# ---------------------------------------------------------------------------
check "a browser that never answers is refused rather than retried forever" \
    "$(render_status 1,2,3 )" "3"
check "and only one extra browser was ever started" "$(browsers_started)" "2"


# ---------------------------------------------------------------------------
# AND ONLY A BROWSER THAT STOPPED IS RETRIED. A page that LOADED and wrote no
# report is the page's fault, and rendering it again in a fresh browser would
# hide exactly the defect these checks exist to find (L151: every outcome the
# contract names gets a case that produces it).
# ---------------------------------------------------------------------------
NO_REPORT_OVERRIDE=1
check "a page that loaded and wrote no report is refused, not rendered again" \
    "$(render "" | grep -c 'no probe report')" "1"
check "and no second browser was started for it" "$(browsers_started)" "1"
unset NO_REPORT_OVERRIDE

# ---------------------------------------------------------------------------
# AND THE RESTART IS WRITTEN DOWN, NOT ONLY PRINTED (ovation#332).
#
# The print reaches a CI log and nothing else, and a CI log expires: scanning
# every unsuccessful run of this repository on 2026-09-15 found ONE occurrence
# and 32 runs whose logs could no longer be read at all. So the horizon for
# counting this was however long the logs live, and the next occurrence would
# have looked like the first all over again, which is the whole thing ovation#316
# printed the line to prevent (L293).
# ---------------------------------------------------------------------------
LOG_OVERRIDE="$WORK/restarts.tsv"

rm -f "$LOG_OVERRIDE"
render "" >/dev/null 2>&1
check "an ordinary render records nothing, so the record counts restarts only" \
    "$([ -s "$LOG_OVERRIDE" ] && echo written || echo empty)" "empty"

rm -f "$LOG_OVERRIDE"
render 1 >/dev/null 2>&1
check "a restart is appended to a record that outlives the log" \
    "$(wc -l < "$LOG_OVERRIDE" | tr -d ' ')" "1"
check "and the line carries the day it happened, the request, and the page" \
    "$(awk -F'\t' 'NR == 1 && $1 ~ /^20[0-9][0-9]-[01][0-9]-[0-3][0-9]T/ && $2 == "Page.navigate" && $3 == "page.html" { print "all three" }' "$LOG_OVERRIDE")" \
    "all three"
# THE PAGE IS NAMED BY ITS BASENAME, never its path. A CI job carries this record
# out to the tracker (ovation#332), and a full path names a home directory or a
# runner's workspace, which is somebody's business and nobody's evidence.
check "and the page is named without the directories it sat in" \
    "$(awk -F'\t' 'NR == 1 { print $3 }' "$LOG_OVERRIDE" | grep -c '/')" "0"

render 1 >/dev/null 2>&1
check "a second restart is a second line, which is what counting recurrence needs" \
    "$(wc -l < "$LOG_OVERRIDE" | tr -d ' ')" "2"
check "and the restart says how many the record now holds, the way a lock wait does" \
    "$(render 1 | grep -cE '3 browser restart\(s\) recorded since 20[0-9][0-9]-[01][0-9]-[0-3][0-9]')" "1"

# A RECORD THAT CANNOT BE WRITTEN IS SAID, AND IS NEVER THE VERDICT. It is a
# measurement of a fault, not part of judging the page, so a check that rendered
# perfectly well must not fail because a log directory was read only (L11, L632).
LOG_OVERRIDE="/dev/null/there-is-no-directory-here/restarts.tsv"
OUT332="$(render 1 2>&1)"
check "a record that cannot be written does not cost the render its result" \
    "$(printf '%s' "$OUT332" | grep -c '^REPORT {"ran": 2}')" "1"
check "and it says the record could not be written rather than swallowing it" \
    "$(printf '%s' "$OUT332" | grep -c 'restart record .* could not be written')" "1"
unset LOG_OVERRIDE

# AND A RUN DRIVEN WITH A STAND IN BROWSER WRITES NOTHING ANYWHERE unless it
# names a record. Every case above names one; this is the case that proves the
# default cannot be reached from a staged fault (L2).
render 1 >/dev/null 2>&1
check "a staged fault with no record named writes nothing under the home directory" \
    "$(find "$WORK/home" -type f 2>/dev/null | wc -l | tr -d ' ')" "0"

# AND NOT INTO AN INHERITED ONE EITHER, which is the case that matters on CI:
# the Linux job SETS this seam for every step, this suite runs inside that job,
# and a fault it staged would otherwise be appended to the record the workflow
# carries out to the tracker and reported as a real one (L439).
AMBIENT="$WORK/ambient.tsv"
rm -f "$AMBIENT"
OVATION_RENDER_RESTART_LOG="$AMBIENT" render 1 >/dev/null 2>&1
check "and a staged fault never reaches a record the environment named" \
    "$([ -e "$AMBIENT" ] && echo written || echo untouched)" "untouched"

# ---------------------------------------------------------------------------
# AND CI'S RECORD LEAVES THE RUNNER (ovation#332).
#
# A CI job runs on a fresh runner every time, so a file under its home directory
# is destroyed with the machine and records nothing anybody can count. The job
# names the record, keeps it as an artifact, and a second workflow carries what
# it holds to the tracker, which is the only store in this system that does not
# expire.
#
# THE ARTIFACT'S NAME IS ONE FACT IN TWO FILES and nothing in YAML can derive one
# from the other, so the agreement is asserted here rather than left to be
# noticed the day a restart is written down and reported to nobody (L41, L58).
CI_YML=".github/workflows/ci.yml"
RESTARTS_YML=".github/workflows/browser-restarts.yml"
RESTARTS_SH="scripts/report-browser-restarts.sh"
check "the CI job names the record, so it lands somewhere the job can keep" \
    "$(grep -c 'OVATION_RENDER_RESTART_LOG' "$CI_YML")" "1"
# Each side's name is READ OUT of its own file and the two are compared, rather
# than both being compared against a name written a third time here, which would
# only ever prove this suite agrees with itself (L70).
# READ FROM INSIDE A FUNCTION, and that is not a style choice. These awk programs
# name their own first FIELD as $1, and the rule in test-run-tests.sh that refuses
# a suite reading its own first ARGUMENT matches an unindented $1 whatever it
# belongs to. It refused this file until these moved, which is the same over match
# ovation#344 records for a quoted heredoc's body.
kept_artifact() {
    awk '/uses: actions\/upload-artifact/ { seen = 1 } seen && $1 == "name:" { print $2; exit }' "$CI_YML"
}
# READ FROM THE SCRIPT the workflow runs, since ovation#352 moved the decision
# out of YAML: the name lives beside the code that asks for it, and the other
# side of the pair is still CI's own upload step.
asked_artifact() {
    awk -F'"' '$0 ~ /^ARTIFACT=/ { print $2; exit }' "$RESTARTS_SH"
}
KEPT_AS="$(kept_artifact)"
ASKED_FOR="$(asked_artifact)"
check "and CI keeps that record as an artifact with a name of its own" \
    "$([ -n "$KEPT_AS" ] && echo "$KEPT_AS" || echo "nothing is uploaded")" "browser-restarts"
check "and the reporting workflow asks for the artifact CI actually keeps" \
    "$([ -n "$ASKED_FOR" ] && [ "$ASKED_FOR" = "$KEPT_AS" ] && echo agree || echo "kept as $KEPT_AS, asked for $ASKED_FOR")" \
    "agree"
# AND IT MAY NOT OPEN AN ISSUE, which is Dan's decision of 2026-09-15 and the one
# thing about this workflow that cannot be read off its own words: `stands` files
# one when none is open and `recurred` refuses to, and they differ by a word.
check "the reporting workflow adds to an issue and never files one" \
    "$([ "$(grep -cE '^ *"\$\{REPORTER\}" recurred' "$RESTARTS_SH")" = "1" ] && [ "$(grep -cE '"\$\{REPORTER\}" stands' "$RESTARTS_SH")" = "0" ] && echo adds || echo files)" \
    "adds"
check "and it reports through the one script that owns reporting, not its own gh issue calls" \
    "$([ "$(grep -c 'report-finding.sh' "$RESTARTS_SH")" -ge 1 ] \
        && [ "$(grep -h 'gh issue' "$RESTARTS_SH" "$RESTARTS_YML" | grep -c .)" -eq 0 ] && echo through || echo "its own")" \
    "through"

harness_end
