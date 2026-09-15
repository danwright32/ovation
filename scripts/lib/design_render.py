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

Imported by every rendering check and by build-design-screenshot.sh, each of
which gets its browser through `open_browser`. Never run on its own.

A BROWSER THAT STOPS ANSWERING IS STARTED AGAIN, ONCE (ovation#316). CI run
34882448119 lost two cases of one check to `the browser did not answer its
Page.navigate request within 120 seconds`, while the browser printed `Trying to
load the allocator multiple times`, on a page whose only change was comment text.
That is the browser failing, not the page, and it cost an unrelated pull request
its green. So a render whose browser stops talking is tried once more in a FRESH
browser, and the restart is PRINTED: a fault that heals silently cannot be
counted, and the next occurrence would look like the first (L293).

It is one more attempt, never a loop, because a check that hangs is worse than one
that fails (L110). And only a browser that STOPPED is retried: a page that loaded
and wrote no report is the page's fault, and rendering it again would hide it.

Seams: OVATION_HEADLESS_BROWSER names the browser, OVATION_BROWSER_GLOBS replaces
where the lookup searches (and a refusal for want of a browser then says so),
OVATION_RENDER_TIMEOUT is how many seconds the browser has to answer any one
request (120), OVATION_RENDER_WAIT_MS overrides how long a loaded page has to
produce its report, and OVATION_RENDER_RESTARTS is how many times a browser that
stopped answering is started again (1).
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
    # WHERE TO LOOK CAN BE NARROWED, so a tool's answer to "no browser at all" can
    # be driven on a machine that has one (L394). A colon separated list of globs
    # replaces the whole search, and whatever refuses for want of a browser says
    # the search was narrowed, so the seam can never quietly turn a check off.
    narrowed = os.environ.get("OVATION_BROWSER_GLOBS", "").strip()
    if narrowed:
        return [piece for piece in narrowed.split(":") if piece]
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


class _BrowserStopped(CannotMeasure):
    """The browser died, or stopped answering. It is told apart from every other
    CannotMeasure because it is the only one worth trying again in a fresh browser:
    it says nothing about the page (ovation#316).

    It CARRIES the request it was waiting for, so a restart can name that without
    repeating the whole complaint. Saying the complaint twice, once on the way to
    the retry and once in the refusal, made every check that counts a phrase in
    this library's output find two where it asserts one (measured on
    test-design-draws.sh, five cases)."""

    def __init__(self, said, request=None):
        super().__init__(said)
        self.request = request


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


def _count(name, default):
    """A seam that is a WHOLE NUMBER OF TIMES, zero included.

    `_number` below reads durations and refuses zero, because a deadline of no
    time is a mistake. None of that is true of a count of attempts: zero restarts
    is a legitimate answer, and a suite has to be able to ask for it to show that
    the restart is what saved a render rather than something about its fixture
    (L1). A value that is not a whole number is refused rather than replaced by
    the default, for the reason `_number` gives (L50, L320)."""
    said = os.environ.get(name, "").strip()
    if not said:
        return default
    try:
        value = int(said)
    except ValueError:
        raise CannotMeasure("%s must be a whole number of times, and it says %r" % (name, said))
    if value < 0:
        raise CannotMeasure("%s cannot be fewer than no times, and it says %r" % (name, said))
    return value


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
        # How many times a browser that stopped answering is started again
        # (ovation#316). A seam, so a suite can stage the fault with the retry off
        # and see that the retry is what saves the render rather than the fixture.
        self.restarts = _count("OVATION_RENDER_RESTARTS", 1)
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

    def restart(self):
        """Stop this browser and start another, for one more attempt at a page.

        The buffered bytes and the pending events belong to the browser that is
        going, and a fresh one numbers nothing the same way, so both are dropped
        rather than carried across (ovation#316)."""
        self.close()
        self._buffer = b""
        self._events = []
        self.start()

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
        return _BrowserStopped("the browser returned no page at all, so the probe never had one "
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
                raise _BrowserStopped("the browser did not answer its %s request within %g "
                                      "seconds, so nothing was measured. The browser said: %s"
                                      % (waiting_for, self.timeout, self._said()),
                                      request=waiting_for)
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
            url = pathlib.Path(probed).as_uri()
            attempts = max(self.restarts, 0) + 1
            for attempt in range(attempts):
                try:
                    return self._render_page(url, width, height, wait)
                except _BrowserStopped as stopped:
                    if attempt + 1 >= attempts:
                        if attempt == 0:
                            raise
                        raise CannotMeasure(
                            "%s A fresh browser was started and the page rendered again, "
                            "and it answered no better, so this is not one browser's fault."
                            % stopped)
                    # SAID, NOT SWALLOWED. This is the only record that it happened,
                    # and counting recurrences is what ovation#316 could not do.
                    # NAMED, NOT QUOTED. The complaint itself belongs in the refusal,
                    # and printing it here as well is what made a phrase this library's
                    # own checks count once appear twice.
                    print("==> the browser stopped answering%s, so this started a fresh "
                          "browser and rendered the page again."
                          % (" its %s request" % stopped.request if stopped.request else ""),
                          file=sys.stderr)
                    self.restart()
        finally:
            shutil.rmtree(holder, ignore_errors=True)

    def _render_page(self, url, width, height, wait):
        # A NEW WINDOW OF THAT SIZE, not a page given a size. The Linux runner's
        # browser refused the second (`Target position can only be set for new
        # windows`) on the first CI run of this renderer, after accepting it for
        # a page or two, while the Mac browser always accepted it, so the push
        # gate could not see it. Asked for as a new window, every report on the
        # committed record matched the --dump-dom renderer's, 27 of 27.
        target = self.call("Target.createTarget",
                           {"url": "about:blank", "newWindow": True,
                            "width": width, "height": height})["targetId"]
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


def open_browser():
    """The one way a tool gets a browser to render in, or a CannotMeasure saying
    why there is none.

    EVERY TOOL THAT RENDERS STARTS HERE, so none can skip the question. Each used
    to call find_browser and test the answer itself, and the window ceiling check
    never tested it: on a machine with no browser it handed nothing to the
    renderer and died with a traceback and exit 1, which reads as a refusal,
    rather than CANNOT MEASURE and exit 3. A tool prints the message after
    `CANNOT MEASURE: ` and exits 3, and test-design-draws.sh drives every tool
    through this with no browser to find.

    Nothing is started here: the browser starts when the first page is rendered,
    so asking first costs nothing when there turns out to be nothing to render.
    """
    found = find_browser()
    if found is None:
        why = NO_BROWSER[len("CANNOT MEASURE: "):]
        narrowed = os.environ.get("OVATION_BROWSER_GLOBS", "").strip()
        if narrowed:
            why += ("\n  The search was narrowed by OVATION_BROWSER_GLOBS=%s, so only "
                    "those places were looked in." % narrowed)
        raise CannotMeasure(why)
    return Browser(found)
