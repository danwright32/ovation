"""Render a design file in a headless browser and read back what it reports.

ovation#141 established this: every other check on the design files reads their
SOURCE, so it can see that a rule is declared and never that the rule put the
thing in the wrong place, or that a token it names resolves to nothing. Both
faults it was written for were invisible in the source and were found by looking
at a rendering.

ovation#120 gave it a second subject, so the plumbing is here rather than copied
into the second checker (L370). The checkers differ only in the PROBE they
inject and what they make of the answer.

HOW IT WORKS. The probe is appended to a temporary copy of the page, the page is
opened in the browser, and the probe writes its report as JSON into a
`<pre id="ovation-probe">`, which is read back once the page has loaded. A page
that loads but writes nothing is a failure to measure rather than a pass,
because the two are otherwise the same event (L98).

ONE BROWSER, MANY PAGES (ovation#183). Every render used to start its own
browser with --dump-dom, and the start was most of what a render cost: measured
on 2026-09-14 on this Mac, a browser that rendered nothing took 0.13s and one
that rendered invoice.html 0.16s. So a `Browser` is started once and driven over
the DevTools pipe, and each render opens a FRESH PAGE in it and closes it
afterwards. A fresh page rather than a shared one, and not every probe injected
into one page, because the probes are not independent: check-design-draws.sh
presses every control, the invoice and clients checks drive their screens, and
the sidebar check presses the day switch, so a probe sharing a page would be
measuring what another had pressed. Before the change every probe was rendered
on every committed file both ways and the 27 reports were identical.

WHAT MOVED WITH IT. --dump-dom took the page after a virtual time budget, which
also fast forwards the page's timers; this reads the report as soon as the page
has loaded and the probe has written it, and waits `budget` milliseconds of real
time for a report that is late. Every probe writes its report while the page
loads, which is what made the reports agree, and the only timer in the record,
review-send.html's send, starts only when Send is pressed.

NO BROWSER IS ITS OWN OUTCOME. A check that cannot render has no answer to give,
and giving one would be a green tick over an unrun check, so callers report
CANNOT MEASURE and exit 3 rather than 0 or 1.

Imported by every rendering check. Never run on its own.

Seams: OVATION_HEADLESS_BROWSER names the browser, OVATION_RENDER_TIMEOUT is how
many seconds the browser has to answer any one request (120), and
OVATION_RENDER_WAIT_MS overrides how long a loaded page has to produce its
report.
"""
import atexit
import fcntl
import glob
import json
import os
import pathlib
import select
import shutil
import subprocess
import sys
import tempfile
import time

# Where playwright puts the headless shell. Named as a glob rather than a pinned
# version, because the version moves with whatever last installed it and a check
# that goes quiet after an upgrade is worse than one that is not there.
# BOTH PLATFORMS, because the checks that use this run on Dan's Mac AND on the
# Linux CI job (ovation#160). Playwright puts its browsers under a different
# cache root and a different per platform directory on each, and a lookup that
# knew only the Mac one would answer "no browser" on the runner: the check would
# go on printing CANNOT MEASURE, which is honest, reads as normal, and is the
# exact state ovation#160 exists to end.
#
# COMPUTED WHEN IT IS ASKED, not once at import. `expanduser` bound at module
# level takes the HOME of whoever imported this and keeps it for the life of the
# process, which is the parameter without the replaceability (L394): nothing
# could then point the lookup at a planted browser to test it.
def browser_globs():
    home = os.path.expanduser("~")
    return [
        # What playwright installed, on either platform, and FIRST: it is the
        # browser the checks were calibrated against, and a machine that has
        # both should not be judged by whichever one happens to be listed
        # earlier.
        os.path.join(home, "Library/Caches/ms-playwright/chromium_headless_shell-*/"
                           "chrome-headless-shell-mac-arm64/chrome-headless-shell"),
        os.path.join(home, "Library/Caches/ms-playwright/chromium-*/"
                           "chrome-mac/Chromium.app/Contents/MacOS/Chromium"),
        os.path.join(home, ".cache/ms-playwright/chromium_headless_shell-*/"
                           "chrome-linux/headless_shell"),
        os.path.join(home, ".cache/ms-playwright/chromium-*/chrome-linux/chrome"),
        # Then whatever the machine itself has.
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
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


class _Refused(CannotMeasure):
    """The browser answered a request with an error rather than a result."""


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
    for pattern in browser_globs():
        found = sorted(glob.glob(pattern))
        if found:
            return found[-1]
    return None


def _number(name, default):
    """A seam read from the environment. A value that is not a number is refused
    rather than quietly replaced by the default, which would run the check under
    a bound nobody chose (L50, L320)."""
    said = os.environ.get(name, "").strip()
    if not said:
        return default
    try:
        value = float(said)
    except ValueError:
        raise CannotMeasure("%s must be a number, and it says %r" % (name, said))
    if value <= 0:
        raise CannotMeasure("%s must be more than zero, and it says %r" % (name, said))
    return value


# Read in the page, never a snapshot of its markup: the report is the pre's TEXT,
# so nothing has to undo the escaping a serialiser put on it.
_STATE = ("(function () { var p = document.getElementById('ovation-probe');"
          " return {href: location.href, ready: document.readyState,"
          " report: p ? p.textContent : null,"
          " bytes: document.documentElement"
          " ? new Blob([document.documentElement.outerHTML]).size : 0}; })()")


class Browser:
    """One headless browser, driven over --remote-debugging-pipe, that renders
    many pages. Use it as a context manager so the browser is always stopped."""

    def __init__(self, path):
        self.path = path
        self.proc = None
        self.timeout = _number("OVATION_RENDER_TIMEOUT", 120.0)
        self._next = 0
        self._buffer = b""
        self._events = []

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, *exc):
        self.close()
        return False

    def start(self):
        """Start the browser. `render` calls this for the first page, so a check
        opens a Browser where it used to hold a browser path and a failure to
        start is reported by the render that needed it, in that render's words.
        It is stopped when the process exits as well as by `close`, so a check
        that returns from the middle of its loop cannot leave one running."""
        if self.proc is not None:
            return
        atexit.register(self.close)
        to_browser_r, to_browser_w = os.pipe()
        from_browser_r, from_browser_w = os.pipe()

        def child():
            # THE PIPE IS ON FDS 3 AND 4, because that is where the browser looks.
            # Each end is first copied ABOVE both, so neither dup2 can land on
            # the other end before it has been placed, and a copy that already
            # sat on 3 or 4 cannot stay marked close on exec.
            reads = fcntl.fcntl(to_browser_r, fcntl.F_DUPFD, 10)
            writes = fcntl.fcntl(from_browser_w, fcntl.F_DUPFD, 10)
            os.dup2(reads, 3)
            os.dup2(writes, 4)

        # WHAT A CI RUNNER NEEDS, and it is not optional there. On a GitHub
        # hosted ubuntu runner chromium aborts on startup under its own sandbox,
        # because the runner has no user namespaces to build one in, and it
        # aborts with SIGABRT and no page: the first run of ovation#160's CI step
        # reported `browser exit -6`, which named the signal and not the cause.
        # Both flags are scoped to Linux rather than passed everywhere, because
        # on Dan's Mac the sandbox works and turning it off would be measuring
        # something other than the browser he renders in (L376).
        flags = [self.path, "--headless", "--disable-gpu", "--remote-debugging-pipe",
                 "--window-size=1440,1200"]
        if sys.platform.startswith("linux"):
            flags += ["--no-sandbox", "--disable-dev-shm-usage"]
        # Stderr goes to a file rather than a pipe nobody drains, which a
        # talkative browser would fill and then block on.
        self._stderr = tempfile.TemporaryFile()
        try:
            self.proc = subprocess.Popen(flags, stdin=subprocess.DEVNULL,
                                         stdout=subprocess.DEVNULL, stderr=self._stderr,
                                         preexec_fn=child, close_fds=False)
        except OSError as err:
            raise CannotMeasure("the browser could not be started: %s" % err)
        finally:
            os.close(to_browser_r)
            os.close(from_browser_w)
        self._out = to_browser_w
        self._in = from_browser_r

    def close(self):
        if self.proc is None:
            return
        try:
            if self.proc.poll() is None:
                try:
                    self._send("Browser.close", {})
                except CannotMeasure:
                    pass
                try:
                    self.proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.proc.kill()
                    self.proc.wait()
        finally:
            for fd in (self._out, self._in):
                try:
                    os.close(fd)
                except OSError:
                    pass
            self._stderr.close()
            self.proc = None

    # -- the protocol ----------------------------------------------------------

    def _said(self):
        """The browser's own complaint, truncated. THE BROWSER'S OWN COMPLAINT IS
        THE DIAGNOSIS, and without it a message names an exit signal and leaves
        whoever reads it with the same command and no way to learn why (L148).
        It is stderr rather than the page, so nothing the page DREW reaches a
        log."""
        try:
            self._stderr.seek(0)
            text = self._stderr.read().decode("utf-8", "replace")
        except (OSError, ValueError):
            # UNREAD IS NOT SILENT. A complaint that could not be read and a
            # browser that complained of nothing are different facts, and only
            # the second was measured when the file came back empty (L11).
            return "and its own output could not be read"
        return " ".join(text.split())[:300] or "and said nothing"

    def _gone(self):
        """The browser stopped talking. NO PAGE AND A PAGE WITHOUT A REPORT ARE
        TWO FAULTS (ovation#282): this is the first, so it never says a page
        rendered."""
        try:
            status = self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            status = self.proc.wait()
        return CannotMeasure("the browser returned no page at all, so the probe never had one "
                             "to run in (browser exit %d). The browser said: %s"
                             % (status, self._said()))

    def _send(self, method, params, session=None):
        self._next += 1
        message = {"id": self._next, "method": method, "params": params}
        if session:
            message["sessionId"] = session
        try:
            os.write(self._out, json.dumps(message).encode("utf-8") + b"\0")
        except (BrokenPipeError, OSError):
            raise self._gone()
        return self._next

    def _receive(self, waiting_for, deadline):
        while b"\0" not in self._buffer:
            left = deadline - time.monotonic()
            if left <= 0:
                # A WAIT WITH NO END CANNOT FAIL, ONLY HANG (L110), so the
                # browser gets a bound per request and running out of it is its
                # own sentence. It is stopped, since nothing it says after this
                # could be believed.
                self.proc.kill()
                raise CannotMeasure("the browser did not answer its %s request within %g "
                                    "seconds, so nothing was measured. The browser said: %s"
                                    % (waiting_for, self.timeout, self._said()))
            ready, _, _ = select.select([self._in], [], [], left)
            if not ready:
                continue
            chunk = os.read(self._in, 1 << 16)
            if not chunk:
                raise self._gone()
            self._buffer += chunk
        raw, self._buffer = self._buffer.split(b"\0", 1)
        try:
            return json.loads(raw)
        except ValueError as err:
            raise CannotMeasure("the browser sent something that is not a DevTools message "
                                "while answering %s: %s" % (waiting_for, err))

    def call(self, method, params=None, session=None):
        want = self._send(method, params or {}, session)
        deadline = time.monotonic() + self.timeout
        while True:
            message = self._receive(method, deadline)
            if message.get("id") == want:
                if "error" in message:
                    raise _Refused("the browser refused %s: %s"
                                   % (method, message["error"].get("message")))
                return message.get("result", {})
            if "method" in message:
                self._events.append(message)

    # -- a render --------------------------------------------------------------

    def render(self, path, probe, window="1440,1200", budget=6000, preamble=""):
        """Render `path` in a fresh page and return the probe's JSON report.

        `probe` is APPENDED, so it runs after the page has built itself, which is
        what every claim about what was drawn needs. `preamble` is inserted at
        the very top instead, before the page's own scripts, which is the only
        place a catcher for an error thrown DURING load can be installed: a
        probe appended to the file is not running yet when the page throws, and
        a page that threw on the way up looks from the bottom exactly like a
        page with nothing on it (ovation#141, L219).

        `window` is the page's width and height. `budget` is how many
        milliseconds a loaded page has to produce its report.
        """
        with open(path, encoding="utf-8", errors="replace") as handle:
            page = handle.read()
        if preamble:
            cut = page.find(">") + 1 if page.lstrip().lower().startswith("<!doctype") else 0
            page = page[:cut] + "\n" + preamble + page[cut:]
        width, height = (int(side) for side in window.split(","))
        self.start()
        wait = _number("OVATION_RENDER_WAIT_MS", float(budget)) / 1000.0
        holder = tempfile.mkdtemp(prefix="ovation-render-")
        try:
            probed = os.path.join(holder, "probed.html")
            with open(probed, "w", encoding="utf-8") as handle:
                handle.write(page + probe)
            return self._render_page(pathlib.Path(probed).as_uri(), width, height, wait)
        finally:
            shutil.rmtree(holder, ignore_errors=True)

    def _render_page(self, url, width, height, wait):
        target = self.call("Target.createTarget",
                           {"url": "about:blank", "width": width, "height": height})["targetId"]
        session = None
        try:
            session = self.call("Target.attachToTarget",
                                {"targetId": target, "flatten": True})["sessionId"]
            self.call("Page.enable", session=session)
            self.call("Page.navigate", {"url": url}, session=session)
            # LOADED MEANS THIS PAGE, COMPLETE. The fresh page starts on
            # about:blank and a load event can belong to that, so the page is
            # asked where it is and how far it got rather than trusting the
            # first event to arrive.
            loaded_by = time.monotonic() + self.timeout
            report_by = None
            while True:
                state = self._state(session)
                now = time.monotonic()
                if state and state.get("href") == url and state.get("ready") == "complete":
                    if state.get("report") is not None:
                        return self._parse(state["report"])
                    if report_by is None:
                        report_by = now + wait
                    elif now >= report_by:
                        raise CannotMeasure(
                            "the browser returned a page of %d bytes with no probe report "
                            "in it, so the probe never ran, threw before writing, or wrote "
                            "after the page was taken, and nothing was measured (the "
                            "browser is still running). The browser said: %s"
                            % (state.get("bytes") or 0, self._said()))
                elif now >= loaded_by:
                    raise CannotMeasure("the page did not finish loading within %g seconds, "
                                        "so nothing was measured. The browser said: %s"
                                        % (self.timeout, self._said()))
                time.sleep(0.01)
        finally:
            self._events = [e for e in self._events if e.get("sessionId") != session]
            if self.proc is not None and self.proc.poll() is None:
                try:
                    self.call("Target.closeTarget", {"targetId": target})
                except CannotMeasure:
                    pass

    def _state(self, session):
        """Where the page is and whether its report is there. A page in the
        middle of navigating has no context to answer in, which is not yet an
        answer, so it reads as no state rather than as a failure."""
        try:
            answer = self.call("Runtime.evaluate",
                               {"expression": _STATE, "returnByValue": True}, session=session)
        except _Refused:
            return None
        if "exceptionDetails" in answer:
            return None
        value = (answer.get("result") or {}).get("value")
        return value if isinstance(value, dict) else None

    @staticmethod
    def _parse(text):
        try:
            return json.loads(text)
        except ValueError as err:
            raise CannotMeasure("the probe's report could not be read: %s" % err)


def render(browser, path, probe, window="1440,1200", budget=6000, preamble=""):
    """Render one page in a browser started for it alone. A check that renders
    more than one page opens a `Browser` itself instead, so it starts one."""
    with Browser(browser) as session:
        return session.render(path, probe, window=window, budget=budget, preamble=preamble)
