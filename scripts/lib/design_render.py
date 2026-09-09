"""Render a design file in a headless browser and read back what it reports.

ovation#141 established this: every other check on the design files reads their
SOURCE, so it can see that a rule is declared and never that the rule put the
thing in the wrong place, or that a token it names resolves to nothing. Both
faults it was written for were invisible in the source and were found by looking
at a rendering.

ovation#120 gave it a second subject, so the plumbing is here rather than copied
into the second checker (L370). The two checkers differ only in the PROBE they
inject and what they make of the answer.

HOW IT WORKS. The probe is appended to a temporary copy of the page, the browser
renders it with --dump-dom, and the probe writes its report as JSON into a
`<pre id="ovation-probe">`. A page that renders but writes nothing is a failure
to measure rather than a pass, because the two are otherwise the same event
(L98).

NO BROWSER IS ITS OWN OUTCOME. A check that cannot render has no answer to give,
and giving one would be a green tick over an unrun check, so callers report
CANNOT MEASURE and exit 3 rather than 0 or 1.

Sourced by scripts/check-invoice-screen-draws.sh and
scripts/check-design-tokens-resolve.sh. Never run on its own.
"""
import glob
import json
import os
import re
import subprocess
import tempfile

# Where playwright puts the headless shell. Named as a glob rather than a pinned
# version, because the version moves with whatever last installed it and a check
# that goes quiet after an upgrade is worse than one that is not there.
# BOTH PLATFORMS, because the checks that use this run on Dan's Mac AND on the
# Linux CI job (ovation#160). Playwright puts its browsers under a different
# cache root and a different per platform directory on each, and a lookup that
# knew only the Mac one would answer "no browser" on the runner: the check would
# go on printing CANNOT MEASURE, which is honest, reads as normal, and is the
# exact state ovation#160 exists to end.
BROWSER_GLOBS = [
    # macOS
    os.path.expanduser("~/Library/Caches/ms-playwright/chromium_headless_shell-*/"
                       "chrome-headless-shell-mac-arm64/chrome-headless-shell"),
    os.path.expanduser("~/Library/Caches/ms-playwright/chromium-*/"
                       "chrome-mac/Chromium.app/Contents/MacOS/Chromium"),
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    # Linux
    os.path.expanduser("~/.cache/ms-playwright/chromium_headless_shell-*/"
                       "chrome-linux/headless_shell"),
    os.path.expanduser("~/.cache/ms-playwright/chromium-*/chrome-linux/chrome"),
    "/usr/bin/chromium-browser",
    "/usr/bin/chromium",
    "/usr/bin/google-chrome",
]

NO_BROWSER = ("CANNOT MEASURE: no headless browser found. This check renders the design "
              "file and reads back what it drew, so with nothing to render it in there "
              "is no answer to give, and reporting one would be a green tick over an "
              "unrun check.\n"
              "  Install one with: npx playwright install chromium\n"
              "  Or name one:      OVATION_HEADLESS_BROWSER=/path/to/chrome")


class CannotMeasure(Exception):
    """Raised when nothing could be rendered, which is never a pass."""


def find_browser():
    """The browser to render in, or None. A NAMED one that is not there is a
    refusal rather than a fall back to the default: a tool handed a target it
    cannot use must not quietly measure something else (L320)."""
    named = os.environ.get("OVATION_HEADLESS_BROWSER", "").strip()
    if named:
        if not os.path.isfile(named):
            raise CannotMeasure("OVATION_HEADLESS_BROWSER names %s, which is not there"
                                % named)
        return named
    for pattern in BROWSER_GLOBS:
        found = sorted(glob.glob(pattern))
        if found:
            return found[-1]
    return None


def render(browser, path, probe, window="1440,1200", budget=6000, preamble=""):
    """Render `path` and return the probe's JSON report.

    `probe` is APPENDED, so it runs after the page has built itself, which is
    what every claim about what was drawn needs. `preamble` is inserted at the
    very top instead, before the page's own scripts, which is the only place a
    catcher for an error thrown DURING load can be installed: a probe appended
    to the file is not running yet when the page throws, and a page that threw
    on the way up looks from the bottom exactly like a page with nothing on it
    (ovation#141, L219).
    """
    with open(path, encoding="utf-8", errors="replace") as handle:
        page = handle.read()
    if preamble:
        cut = page.find(">") + 1 if page.lstrip().lower().startswith("<!doctype") else 0
        page = page[:cut] + "\n" + preamble + page[cut:]
    holder = tempfile.mkdtemp(prefix="ovation-render-")
    probed = os.path.join(holder, "probed.html")
    with open(probed, "w", encoding="utf-8") as handle:
        handle.write(page + probe)
    try:
        done = subprocess.run(
            [browser, "--headless", "--disable-gpu",
             "--virtual-time-budget=%d" % budget,
             "--window-size=" + window, "--dump-dom", "file://" + probed],
            capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired) as err:
        raise CannotMeasure("the browser could not render the page: %s" % err)
    found = re.search(r'<pre id="ovation-probe">(.*?)</pre>', done.stdout, re.S)
    if not found:
        raise CannotMeasure("the page rendered but the probe wrote nothing, so nothing "
                            "was measured (browser exit %d)" % done.returncode)
    body = found.group(1).replace("&quot;", '"').replace("&lt;", "<")
    body = body.replace("&gt;", ">").replace("&amp;", "&")
    try:
        return json.loads(body)
    except ValueError as err:
        raise CannotMeasure("the probe's report could not be read: %s" % err)
