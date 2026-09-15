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
harness_begin "design renderer tests" 12

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

harness_end
