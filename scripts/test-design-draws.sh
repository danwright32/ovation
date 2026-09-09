#!/bin/bash
# The suite for scripts/check-design-draws.sh.
#
# ovation#141. Every claim in that harness is about a fault that once shipped,
# and a guard is only real once it has been seen to fail (L1). So each case here
# plants ONE defect in a copy of a committed design file and asserts that the
# claim written for it, and no other, is the one that fires: a defect large
# enough to break everything makes every claim fail and is indistinguishable
# from the one that should have (L154).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "design rendering checks" 42

TARGET="scripts/check-design-draws.sh"
require_target "$TARGET"
require_target "docs/design/invoice-pdf.html"
harness_temp_dir WORK

# The check answers 3 when it has nothing to render in, and that is the first
# thing to establish: every assertion below would otherwise be measuring the
# absence of a browser rather than the presence of a defect. The status is
# captured on its own line, because `if ! cmd` makes `$?` the negation's status.
python3 "$TARGET" docs/design/invoice-pdf.html >/dev/null 2>&1
BROWSER_PROBE=$?
if [ "$BROWSER_PROBE" = "3" ]; then
    harness_cannot_measure \
        "no headless browser, so nothing can be rendered and no claim here proves anything" \
        "npx playwright install chromium, or set OVATION_HEADLESS_BROWSER"
fi

# ONE WIDTH FOR THE PLANTED CASES, so a mutation reports one failure rather than
# one per width and the count below stays readable. The committed record is run
# at both, which is the run that matters.
one() { OVATION_DESIGN_WIDTHS=1440 python3 "$TARGET" "$1" 2>&1; }
one_status() { one "$1" >/dev/null 2>&1; printf '%s' "$?"; }
fired() { one "$1" | sed -n 's/^  FAIL [^:]*: \([^:]*\): .*/\1/p' | sort -u | tr '\n' ';'; }

mutate() {
    # $1 destination, $2 sed expression, $3 a pattern the result must contain.
    # A mutation that matched NOTHING leaves a healthy file and every claim
    # holds, which reads exactly like a guard that works (L100).
    sed "$2" docs/design/"$4" > "$1"
    grep -c "$3" "$1"
}

# ---------------------------------------------------------------------------
# The committed record, which is the case that proves the claims are not simply
# always failing.
# ---------------------------------------------------------------------------
python3 "$TARGET" > "$WORK/healthy.txt" 2>&1
check "the committed design record passes at both widths" "$?" "0"
check "and the verdict names both widths" \
    "$(grep -c '1440px and 1280px' "$WORK/healthy.txt")" "1"
check "and says how many marked blocks of figures it judged" \
    "$(grep -c 'marked block(s) of figures were judged' "$WORK/healthy.txt")" "1"
check "and how many controls it pressed" \
    "$(grep -c 'control(s) pressed across those renders' "$WORK/healthy.txt")" "1"
HEALTHY="$(sed -n 's/^OK: all \([0-9]*\) claim.*/\1/p' "$WORK/healthy.txt")"
check "with more than one claim in it" \
    "$([ "${HEALTHY:-0}" -ge 20 ] && echo many)" "many"

# ---------------------------------------------------------------------------
# 1. THE CONSOLE, when the page throws while it is being DRIVEN. This is
#    ovation#170 exactly: a line carrying an explicitly empty hours value made
#    the invoice PDF render as a blank white sheet, and the only fixture with
#    such a line was three buttons from the one the page opens on.
# ---------------------------------------------------------------------------
THREW="$WORK/threw.html"
check "the hours guard is where the mutation expects it" \
    "$(mutate "$THREW" 's|r.append(mk("td", "r", l.hours == null ? "" : hours(l.hours)));|r.append(mk("td", "r", l.hours !== undefined ? hours(l.hours) : ""));|' 'hours(l.hours) : ""' invoice-pdf.html)" "1"
check "a page that throws while being driven is refused" "$(one_status "$THREW")" "1"
check "and the claim that fired names the console under driving" \
    "$(fired "$THREW")" "the console is still silent after every control has been pressed;"

# ---------------------------------------------------------------------------
# 2. THE CONSOLE AT REST, which is a different claim and needs the catcher
#    installed BEFORE the page's own scripts.
# ---------------------------------------------------------------------------
NOISY="$WORK/noisy.html"
check "the page's opening script is where the mutation expects it" \
    "$(mutate "$NOISY" 's|<body>|<body><script>console.error("something the page said");</script>|' 'something the page said' invoice-pdf.html)" "1"
check "a page that logs an error at rest is refused" "$(one_status "$NOISY")" "1"
check "and the at rest console claim is one of the ones that fired" \
    "$(one "$NOISY" | grep -c 'the console said nothing')" "1"

# ---------------------------------------------------------------------------
# 3. CONTENT CUT OFF WITH NO WAY TO REACH IT. The fault that deleted the invoice
#    screen's right hand side: a stage narrower than the window it holds.
# ---------------------------------------------------------------------------
CUT="$WORK/cut.html"
check "the screen's width is where the mutation expects it" \
    "$(mutate "$CUT" 's|^\.screen { width: 1120px;|.screen { width: 820px;|' 'width: 820px' invoice.html)" "1"
check "a screen that cuts off what it holds is refused" "$(one_status "$CUT")" "1"
check "and the claim that fired names the unreachable content" \
    "$(one "$CUT" | grep -c 'nothing hides content there is no way to reach')" "1"

# ---------------------------------------------------------------------------
# 4. A PAGE THAT SCROLLS SIDEWAYS.
# ---------------------------------------------------------------------------
WIDE="$WORK/wide.html"
check "the page body is where the mutation expects it" \
    "$(mutate "$WIDE" 's|<body>|<body><div style="width:3000px;height:4px"></div>|' 'width:3000px' invoice-pdf.html)" "1"
check "a page that scrolls sideways is refused" "$(one_status "$WIDE")" "1"
check "and the claim that fired names the sideways scroll" \
    "$(one "$WIDE" | grep -c 'the page does not scroll sideways')" "1"

# ---------------------------------------------------------------------------
# 5. A FIGURE OFF THE SHARED RIGHT EDGE, which the record has had to fix twice.
# ---------------------------------------------------------------------------
EDGE="$WORK/edge.html"
check "the money row is where the mutation expects it" \
    "$(mutate "$EDGE" 's|r.append(mk("span", "num", v));|r.append(mk("span", "num", v)); if (k === "Subtotal") r.lastChild.style.marginRight = "24px";|' 'marginRight' invoice-pdf.html)" "1"
check "a figure off the shared right edge is refused" "$(one_status "$EDGE")" "1"
check "and the claim that fired names the right edge" \
    "$(fired "$EDGE")" "every figure in a block that says its figures line up does;"

# ---------------------------------------------------------------------------
# 6. A PAGE THAT DREW ALMOST NOTHING. Without this every claim above passes
#    vacuously over an empty page, which is the shape L98 exists for.
# ---------------------------------------------------------------------------
EMPTY="$WORK/empty.html"
printf '<!doctype html>\n<html><head><title>x</title></head><body><p>one</p></body></html>\n' > "$EMPTY"
check "a page that drew almost nothing is refused" "$(one_status "$EMPTY")" "1"
check "and the claim that fired says so" \
    "$(one "$EMPTY" | grep -c 'the page drew something')" "1"

# ---------------------------------------------------------------------------
# NOTHING TO MEASURE IS NOT A PASS, and each way of having nothing is its own
# outcome (L98, L11).
# ---------------------------------------------------------------------------
check "a named file that is not there is refused, never skipped" \
    "$(python3 "$TARGET" "$WORK/nowhere.html" >/dev/null 2>&1; printf '%s' "$?")" "2"
check "and it says which file" \
    "$(python3 "$TARGET" "$WORK/nowhere.html" 2>&1 | grep -c 'no such design file')" "1"
check "an empty design root cannot measure" \
    "$(OVATION_DESIGN_ROOT="$WORK/nothing-here" python3 "$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "2"
check "a width list that is not a list of widths is used wrongly" \
    "$(OVATION_DESIGN_WIDTHS='wide' python3 "$TARGET" docs/design/invoice-pdf.html >/dev/null 2>&1; printf '%s' "$?")" "2"
check "a browser that is not there cannot measure, and is not a pass" \
    "$(OVATION_HEADLESS_BROWSER="$WORK/no-such-browser" python3 "$TARGET" \
        docs/design/invoice-pdf.html >/dev/null 2>&1; printf '%s' "$?")" "3"
check "and says so rather than reporting health" \
    "$(OVATION_HEADLESS_BROWSER="$WORK/no-such-browser" python3 "$TARGET" \
        docs/design/invoice-pdf.html 2>&1 | grep -c 'CANNOT MEASURE')" "1"

# ---------------------------------------------------------------------------
# THE BROWSER LOOKUP KNOWS BOTH PLATFORMS (ovation#160).
#
# These checks now run on the Linux CI job as well as on Dan's Mac, and
# playwright puts its browsers under a different cache root and a different per
# platform directory on each. A lookup that knew only the Mac paths would answer
# "no browser" on the runner, so all three checks would go on printing CANNOT
# MEASURE while the workflow looked correct: honest, reading as normal, and the
# exact state ovation#160 exists to end (L400, L98).
#
# THE PLANTED BROWSER IS NEVER RUN. What is under test is where the lookup
# LOOKS, so each case plants an executable file at a real playwright path and
# asserts the lookup returns it.
found_under() {
    # $1 a HOME to search from. Prints the path found, or "nothing".
    HOME="$1" python3 - <<'PYEOF'
import os, sys
sys.path.insert(0, os.path.join(os.getcwd(), "scripts/lib"))
from design_render import find_browser
print(find_browser() or "nothing")
PYEOF
}

LINUX_HOME="$WORK/linux-home"
LINUX_AT="$LINUX_HOME/.cache/ms-playwright/chromium_headless_shell-1200/chrome-linux"
mkdir -p "$LINUX_AT"
printf '#!/bin/sh\nexit 9\n' > "$LINUX_AT/headless_shell"
chmod +x "$LINUX_AT/headless_shell"
check "the lookup finds a browser where playwright puts it on Linux" \
    "$(found_under "$LINUX_HOME")" "$LINUX_AT/headless_shell"

MAC_HOME="$WORK/mac-home"
MAC_AT="$MAC_HOME/Library/Caches/ms-playwright/chromium_headless_shell-1200/chrome-headless-shell-mac-arm64"
mkdir -p "$MAC_AT"
printf '#!/bin/sh\nexit 9\n' > "$MAC_AT/chrome-headless-shell"
chmod +x "$MAC_AT/chrome-headless-shell"
check "and where it puts one on macOS" \
    "$(found_under "$MAC_HOME")" "$MAC_AT/chrome-headless-shell"

# The refusal is a raised CannotMeasure, so python prints the message twice: once
# in the traceback's source line and once as the exception. Both lines are the
# refusal; what matters is that a browser IS on this machine and was not
# returned (L320).
check "a NAMED browser that is not there is refused, never fallen back from" \
    "$(OVATION_HEADLESS_BROWSER="$WORK/no-such-browser" found_under "$LINUX_HOME" 2>&1 \
        | grep -c 'which is not there')" "2"

# A BROWSER THAT COULD NOT RENDER SAYS WHY (ovation#160). The first CI run of
# these checks reported `browser exit -6`, which is the signal and not the
# cause: chromium aborts under its own sandbox on a hosted ubuntu runner. A
# refusal whose message does not say what happened leaves whoever reads it with
# the same command and no way to learn why (L148).
BAD_BROWSER="$WORK/refuses.sh"
printf '#!/bin/sh\necho "the browser is unhappy about something" >&2\nexit 6\n' > "$BAD_BROWSER"
chmod +x "$BAD_BROWSER"
check "a browser that renders nothing cannot measure" \
    "$(OVATION_HEADLESS_BROWSER="$BAD_BROWSER" python3 "$TARGET" \
        docs/design/invoice-pdf.html >/dev/null 2>&1; printf '%s' "$?")" "3"
check "and the browser's own complaint is in the message" \
    "$(OVATION_HEADLESS_BROWSER="$BAD_BROWSER" python3 "$TARGET" \
        docs/design/invoice-pdf.html 2>&1 | grep -c 'the browser is unhappy about something')" "1"
check "and so is the exit code it left" \
    "$(OVATION_HEADLESS_BROWSER="$BAD_BROWSER" python3 "$TARGET" \
        docs/design/invoice-pdf.html 2>&1 | grep -c 'browser exit 6')" "1"

SILENT_BROWSER="$WORK/silent.sh"
printf '#!/bin/sh\nexit 0\n' > "$SILENT_BROWSER"
chmod +x "$SILENT_BROWSER"
check "a browser that says nothing at all still cannot measure" \
    "$(OVATION_HEADLESS_BROWSER="$SILENT_BROWSER" python3 "$TARGET" \
        docs/design/invoice-pdf.html >/dev/null 2>&1; printf '%s' "$?")" "3"
check "and the message says it said nothing rather than leaving a blank" \
    "$(OVATION_HEADLESS_BROWSER="$SILENT_BROWSER" python3 "$TARGET" \
        docs/design/invoice-pdf.html 2>&1 | grep -c 'and said nothing')" "1"

# ---------------------------------------------------------------------------
# AND THE LINUX JOB ACTUALLY RUNS THEM (ovation#160). A workflow that installs a
# browser and never uses it, or uses it and never proves it is there, is the
# same silence in a different place.
# ---------------------------------------------------------------------------
WORKFLOW=".github/workflows/ci.yml"
check "the Linux job installs a headless browser" \
    "$(grep -c 'playwright@[0-9.]* install' "$WORKFLOW")" "1"
check "on a pinned version, so an upgrade is a change somebody made" \
    "$(grep -c 'playwright@1\.63\.0 install' "$WORKFLOW")" "1"
check "and the browser download is cached on that version" \
    "$(grep -c 'key: playwright-1\.63\.0-chromium' "$WORKFLOW")" "1"
check "and every rendered check is named as running there" \
    "$(grep -cE '^ *python3 scripts/check-(design-draws|invoice-screen-draws|design-tokens-resolve)\.sh$' \
        "$WORKFLOW")" "3"
# THE FLAGS THAT MAKE IT RUN THERE AT ALL, asserted in the library rather than
# in the workflow, because that is where they live and a workflow that installs
# a browser it cannot start is the same silence in a different place.
check "and the renderer turns off the sandbox chromium cannot build on a runner" \
    "$(grep -c 'no-sandbox' scripts/lib/design_render.py)" "1"
check "only on Linux, so the Mac still renders in the browser Dan uses" \
    "$(grep -c 'sys.platform.startswith("linux")' scripts/lib/design_render.py)" "1"

harness_end
