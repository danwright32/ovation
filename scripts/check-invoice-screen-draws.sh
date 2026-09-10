#!/usr/bin/env python3
"""Refuse an invoice design file that DRAWS something wrong.

    check-invoice-screen-draws.sh [design file]

ovation#141 says it outright: nothing measures what a design file actually
draws. Every other check on these files reads their SOURCE, so it can see that a
rule is declared and never that the rule put the thing in the wrong place. Round
A of ovation#111 found three faults in one afternoon that no source reading
could have caught, and each of the claims below is the fingerprint of one of
them:

  1. The first line's amount was the LINES TOTAL rather than its own figure.
     The two are the same number while an invoice can only carry one line, so
     the defect could not exist until a second line was added, and then a 375.00
     line read as 450.00 with a 75.00 line beneath it (L101).
  2. The Edit menu opened 46px to the LEFT of Edit, under File, because it was
     positioned by a constant the menu bar's wording had moved out from under.
     A menu drawn in the wrong place still draws, so nothing reported it.
  3. Choosing something in that menu left it standing, covering the invoice it
     had just changed.

IT RENDERS THE FILE AND READS THE RESULT BACK. It drives the screen the way a
person does, by pressing what is on it, rather than asserting about the source,
because the source was correct in all three cases above.

IT REFUSES TO GUESS WHEN IT CANNOT MEASURE. With no headless browser it exits 3
and says so, rather than exiting 0, because "every claim held" and "nothing was
checked" must never be the same answer (L98).

Exit codes: 0 every claim held, 1 a claim failed, 2 used wrongly, 3 cannot
measure. Set OVATION_HEADLESS_BROWSER to name the browser binary.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

from design_render import CannotMeasure, NO_BROWSER, find_browser, render  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_FILE = os.path.join(REPO, "docs/design/invoice.html")

# The probe. It runs INSIDE the rendered page and reports what the page drew.
#
# IT REACHES FOR THE PAGE'S OWN ensureIssued() rather than typing into the time
# fields. Typing would test the time field, which has its own suite, and would
# make every claim below depend on it: a broken time field would then report as
# a broken line table, which is two situations with one message (L11).
PROBE = r"""
<script>
window.addEventListener("load", function () {
  var result = { claims: {}, notes: [], errors: [] };
  function claim(name, ok, saw) {
    result.claims[name] = { ok: !!ok, saw: saw };
  }
  try {
    var verdict = document.getElementById("verdict");
    claim("the page's own rule suites pass",
          verdict && /^All \d+ cases pass/.test(verdict.textContent),
          verdict ? verdict.textContent.slice(0, 70) : "no verdict element");

    /* ---- the Edit menu ---- */
    var edit = Array.prototype.filter.call(
      document.querySelectorAll(".menubar [role=button]"),
      function (s) { return s.textContent === "Edit"; })[0];
    if (!edit) {
      claim("the Edit menu opens under Edit", false, "no Edit item in the menu bar");
      claim("choosing something closes the menu", false, "no Edit item in the menu bar");
    } else {
      edit.click();
      var menu = document.querySelector(".menu");
      if (!menu) {
        claim("the Edit menu opens under Edit", false, "pressing Edit drew no menu");
        claim("choosing something closes the menu", false, "pressing Edit drew no menu");
      } else {
        var item = Array.prototype.filter.call(
          document.querySelectorAll(".menubar [role=button]"),
          function (s) { return s.textContent === "Edit"; })[0];
        var offset = Math.round(menu.getBoundingClientRect().left
                                - item.getBoundingClientRect().left);
        /* macOS hangs a menu on its own item, a few pixels left of the word to
           allow for the highlight. Twelve is generous and still catches the
           46px this check was written for. */
        claim("the Edit menu opens under Edit", Math.abs(offset) <= 12,
              "the menu's left edge is " + offset + "px from Edit's");

        /* THE CHIP AND THE HIGHLIGHTED ROW ACTUALLY PAINT. Both declare
           `background: var(--accent)` and both sit OUTSIDE the app window,
           where the palette did not reach until 2026-09-08, so both computed to
           rgba(0, 0, 0, 0) and neither had ever been drawn. A token referenced
           and not defined leaves no error and no mark, and the declaration goes
           on reading as correct (L585). This is the one claim here whose
           failure is a thing NOT being drawn, so nothing but a measurement can
           see it. */
        var chip = document.querySelector(".menubar .openmenu");
        var lit = document.querySelector(".menu div.on");
        function painted(node) {
          if (!node) return null;
          var background = getComputedStyle(node).backgroundColor;
          return /rgba\(0, 0, 0, 0\)|transparent/.test(background) ? null : background;
        }
        claim("the open menu's chip in the menu bar is painted", !!painted(chip),
              chip ? "background " + getComputedStyle(chip).backgroundColor
                   : "no chip on the menu bar");
        claim("the menu's highlighted row is painted", !!painted(lit),
              lit ? "background " + getComputedStyle(lit).backgroundColor
                  : "no highlighted row in the menu");

        var wired = Array.prototype.filter.call(
          document.querySelectorAll(".menu div"),
          function (d) { return /^Add a discount$/.test(d.textContent); })[0];
        if (!wired) {
          claim("choosing something closes the menu", false,
                "the menu has no 'Add a discount' to choose");
        } else {
          wired.click();
          claim("choosing something closes the menu",
                !document.querySelector(".menu"),
                document.querySelector(".menu") ? "the menu is still open" : "it closed");
        }
      }
    }

    /* ---- the line table, on an invoice that has been priced ---- */
    ensureIssued();
    redraw();

    var word = document.querySelector(".laddbtn");
    claim("a draft offers a way to add a line", !!word,
          word ? word.textContent : "nothing on the lines to press");
    if (word) {
      word.click();
      var chooser = document.querySelector(".typebtn");
      claim("the new row asks for a service type", !!chooser,
            chooser ? chooser.textContent : "no chooser in the new row");
      if (chooser) {
        chooser.click();
        var list = document.querySelector(".poplist");
        var names = list ? Array.prototype.map.call(list.querySelectorAll("button"),
                                                   function (b) { return b.textContent; }) : [];
        claim("the service types are offered", names.length >= 2, names.join(", "));

        /* AND THE LIST IS ACTUALLY PAINTED WHERE IT SITS. Every other claim
           here reads the DOM, and the DOM cannot tell a list that is drawn from
           one that is clipped away: `.ldesc` sets overflow hidden so a long
           description ellipsises, and an absolutely positioned box inside a
           clipping one is clipped by it (L566). On the day round A shipped, the
           list was in the DOM with all three types and the TOTALS BLOCK was
           what got painted at its coordinates. So this asks the browser what is
           drawn at the last type's own centre.

           The window size matters and is set by the caller: elementFromPoint
           answers null for anything below the viewport, so at the default
           800x600 this claim would fail on a perfectly drawn list, which is a
           measurement reporting on the measurer. */
        var drawn = null;
        if (list) {
          var buttons = list.querySelectorAll("button");
          var last = buttons[buttons.length - 1];
          var lb = last.getBoundingClientRect();
          var below = lb.bottom > window.innerHeight || lb.right > window.innerWidth;
          if (below) {
            claim("the list of types is painted where it sits", false,
                  "the list is outside the " + window.innerWidth + "x" + window.innerHeight
                    + " window, so nothing could be measured");
          } else {
            drawn = document.elementFromPoint(lb.left + lb.width / 2, lb.top + lb.height / 2);
            claim("the list of types is painted where it sits",
                  !!drawn && list.contains(drawn),
                  drawn ? "what is drawn there: " + (drawn.className || drawn.tagName)
                        : "nothing is drawn there");
          }
        }
        if (list) {
          list.querySelectorAll("button")[1].click();
          var field = document.querySelector(".lamt");
          claim("the new row takes an amount", !!field,
                field ? "an amount field" : "no amount field");

          if (field) {
            claim("the amount asserts no figure it was not given",
                  !field.placeholder || !/\d/.test(field.placeholder),
                  "placeholder: " + JSON.stringify(field.placeholder));
            field.value = "75";
            field.dispatchEvent(new Event("blur"));
          }
        }
      }

      /* A TYPE THAT DOES NOT EXIST YET, on a SECOND line, because the first one
         now carries a type and so no longer offers a chooser to press. The
         panel's second question is only worth asking if something reads the
         answer, so this creates a type WITH a usual amount and checks the line
         comes back carrying it: a field nothing reads is the defect this claim
         exists to catch. */
      var again = document.querySelector(".laddbtn");
      if (again) { again.click(); }
      var chooser2 = document.querySelector(".typebtn");
      if (chooser2) { chooser2.click(); }
      var makenew = document.querySelector(".poplist .plast");
      if (!makenew) {
        claim("a type that does not exist yet can be made from here", false,
              "the list has no entry for making one");
      } else {
        makenew.click();
        var panel = document.querySelector(".newpanel");
        var boxes = panel ? panel.querySelectorAll("input") : [];
        if (boxes.length < 2) {
          claim("a type that does not exist yet can be made from here", false,
                panel ? "the panel asks " + boxes.length + " question(s)" : "no panel opened");
        } else {
          boxes[0].value = "Rehearsal coverage";
          boxes[0].dispatchEvent(new Event("input"));
          boxes[1].value = "140";
          panel.querySelector(".panelacts .go").click();
          var named = document.querySelector(".lrow.newrow .ldesc");
          var filled = document.querySelector(".lamt");
          claim("a type that does not exist yet can be made from here",
                !!named && named.textContent.trim() === "Rehearsal coverage"
                  && !!filled && parseFloat(filled.value) === 140,
                "the line reads " + JSON.stringify(named ? named.textContent.trim() : null)
                  + " and its amount holds " + JSON.stringify(filled ? filled.value : null));
          /* Left uncommitted deliberately: the row being filled in is part of
             what the geometry claims below have to hold for. */
        }
      }
    }

    var rows = document.querySelectorAll(".lrow");
    var texts = Array.prototype.map.call(rows, function (r) {
      return Array.prototype.map.call(r.children, function (c) {
        return c.textContent.trim();
      }).join(" | ");
    });
    result.notes = texts;
    claim("the added line is on the invoice", rows.length === 3, texts.join("  //  "));

    /* THE FIRST LINE SHOWS ITS OWN AMOUNT. Its hours times its rate, read off
       the row itself, so this cannot be satisfied by agreeing with a total that
       is also wrong. */
    if (rows.length >= 2) {
      var cells = rows[0].children;
      var hours = parseFloat(cells[1].textContent.replace(/,/g, ""));
      var rate = parseFloat(cells[2].textContent.replace(/,/g, ""));
      var shown = parseFloat(cells[3].textContent.replace(/,/g, ""));
      /* A FIGURE THAT COULD NOT BE READ IS ITS OWN ANSWER, never a comparison.
         NaN compares false against every threshold, so without this the claim
         would fail on the fail safe side while its message read "NaN x NaN
         should be NaN": a row drawn with no figures at all and a row drawn with
         the wrong figure are different faults and cannot share one sentence
         (L50, L11). */
      if (!isFinite(hours) || !isFinite(rate) || !isFinite(shown)) {
        claim("the first line shows its own amount, not the lines total", false,
              "the row's figures could not be read as numbers: hours "
                + JSON.stringify(cells[1].textContent) + ", rate "
                + JSON.stringify(cells[2].textContent) + ", amount "
                + JSON.stringify(cells[3].textContent));
      } else {
        claim("the first line shows its own amount, not the lines total",
              Math.abs(shown - hours * rate) < 0.005,
              hours + " x " + rate + " should be " + (hours * rate).toFixed(2)
                + ", the row says " + shown.toFixed(2));
      }
    }

    /* ---- the due date, in the foot ---- */
    var foot = document.querySelector(".invwhen");
    var duebtn = document.querySelector(".duebtn");
    claim("the due date in the foot is a control", !!duebtn,
          foot ? foot.textContent.trim().replace(/\s+/g, " ") : "no foot");
    if (duebtn) {
      var before = duebtn.textContent.trim();
      duebtn.click();
      var terms = document.querySelector(".poplist.up");
      var rows = terms ? terms.querySelectorAll("button") : [];
      /* EVERY TERM SAYS THE DATE IT LANDS ON. A term is only meaningful as the
         date it produces, and the whole reason this option was kept over typing
         a date is that it names the common answers. */
      var withDates = 0;
      Array.prototype.forEach.call(rows, function (r) { if (r.querySelector(".when")) withDates++; });
      claim("every term says the date it lands on", rows.length >= 3 && withDates === rows.length - 1,
            rows.length + " rows, " + withDates + " of them carrying a date");

      if (terms && rows.length) {
        var tb = rows[rows.length - 2].getBoundingClientRect();
        if (tb.bottom > window.innerHeight || tb.top < 0) {
          claim("the terms are painted where they sit", false,
                "the list is outside the window, so nothing could be measured");
        } else {
          var on = document.elementFromPoint(tb.left + tb.width / 2, tb.top + tb.height / 2);
          claim("the terms are painted where they sit", !!on && terms.contains(on),
                on ? "what is drawn there: " + (on.className || on.tagName)
                   : "nothing is drawn there");
        }

        /* A DATE THAT DOES NOT EXIST IS REFUSED, WITH A REASON. 31 Sep rolls
           forward to 1 Oct in Date.UTC, so an unguarded reader accepts a date
           nobody typed, and the due date is what every chase is timed from. */
        rows[rows.length - 1].click();
        var panel = document.querySelector(".duepanel");
        var box = panel ? panel.querySelector("input") : null;
        if (!box) {
          claim("a date that does not exist is refused, and says why", false,
                panel ? "the panel has no field" : "another date opened no panel");
        } else {
          box.value = "31 Sep 2026";
          box.dispatchEvent(new KeyboardEvent("keydown",
            { key: "Enter", bubbles: true, cancelable: true }));
          var says = document.querySelector(".duebad");
          var moved = document.querySelector(".invwhen").textContent.indexOf("1 Oct") !== -1;
          claim("a date that does not exist is refused, and says why",
                !!says && !moved,
                (says ? "it says: " + says.textContent : "it said nothing")
                  + (moved ? ", and the invoice took 1 Oct" : ", and the date did not move"));
          var cancel = document.querySelector(".duepanel .panelacts button");
          if (cancel) cancel.click();
        }
      }
    }

    /* THE DRAFT'S MAIN ACTION NAMES WHAT IT DOES (PRD 52a, ovation#169). It
       opens the review sheet and sends nothing, so it may not say Send. The
       word is read off what the foot DREW rather than off footFor, because a
       rule returning the right string and a foot drawing a different one are
       two situations a source reading cannot tell apart. */
    var mainAct = document.querySelector(".invfoot .acts .invact");
    var mainWord = mainAct ? mainAct.textContent.trim() : null;
    claim("the draft's main action names what it does, and it is not Send",
          mainWord === "Review",
          "the foot's main action says " + JSON.stringify(mainWord));

    /* ---- money held on the client (ovation#109, settled 2026-09-10) ----

       These run BEFORE the not billed flow below, which replaces the totals
       with a single sentence: after it there is no sumBox to make any claim
       about, and the claims would fail for a reason that is not theirs.

       THE ARITHMETIC IS THE POINT, not the placement. A payment is not a price
       reduction, so nothing about applying it may reach the subtotal, the
       referral credit block or the tax. That is invisible in the source: the
       block is appended a few lines below the total and would look equally
       correct appended a few lines above it, and the wrong one produces a wrong
       invoice rather than a wrong layout. */
    function totalsNow() {
      var out = {};
      Array.prototype.forEach.call(document.querySelectorAll(".invsum .sline"), function (ln) {
        out[ln.firstChild.textContent.trim()] = ln.querySelector(".fig").textContent.trim();
      });
      return out;
    }

    var applied = document.querySelector(".sline.heldline");
    if (!applied) {
      claim("held money is applied, and says so", false,
            "no held money line on an invoice whose client is holding some");
      claim("applying held money leaves the subtotal and the tax alone", false,
            "no held money line to apply");
      claim("what is left over stays held, and the invoice says how much", false,
            "no held money line to leave anything over");
      claim("Remove is on the held money line itself", false, "no held money line");
      claim("with two invoices open it is applied to neither, and says why", false,
            "no held money line");
    } else {
      var before = totalsNow();
      var heldFig = applied.querySelector(".fig").textContent.trim();
      claim("held money is applied, and says so",
            heldFig.charAt(0) === "-" && "Outstanding" in before,
            "the line reads " + JSON.stringify(heldFig)
              + " and the totals are " + JSON.stringify(before));

      /* REMOVE IS ON THE LINE, not under the total, which is where it named
         nothing (Dan, 2026-09-10). Being INSIDE .heldlabel is the claim: a
         Remove anywhere else in the totals box would still be found by a
         looser selector and would pass this while being the rejected design. */
      var removeWord = applied.querySelector(".heldlabel .heldback");
      claim("Remove is on the held money line itself",
            !!removeWord && removeWord.textContent.trim() === "Remove",
            removeWord ? "on the line, reading " + JSON.stringify(removeWord.textContent.trim())
                       : "not inside the held money line's own label");

      /* THE CLAIM BELOW LOOKS FOR REMOVE MORE LOOSELY ON PURPOSE. It is about
         the arithmetic, and it needs something to press to measure it; sharing
         the strict selector above would make a Remove in the wrong PLACE fire
         two claims at once, and a mutation that breaks two claims proves
         neither of them (L154). */
      var pressable = document.querySelector(".invsum .heldback");

      /* WHAT IS LEFT OVER IS STATED (PRD 5.14e). The fixture's invoice is
         smaller than the balance, so this is the partial case by construction. */
      var leftover = document.querySelector(".invsum .heldwhy");
      var owed = parseFloat((before.Total || "0").replace(/,/g, ""));
      var used = Math.abs(parseFloat(heldFig.replace(/[-,]/g, "")));
      claim("what is left over stays held, and the invoice says how much",
            used >= owed - 0.005
              ? !!leftover && /stays held/.test(leftover.textContent)
              : !leftover,
            used >= owed - 0.005
              ? (leftover ? leftover.textContent.trim() : "nothing said about the rest")
              : "the whole balance was used, so there is nothing left to say");

      if (pressable) {
        pressable.click();
        var after = totalsNow();
        claim("applying held money leaves the subtotal and the tax alone",
              before.Subtotal === after.Subtotal
                && before["Sales tax, 8.875%"] === after["Sales tax, 8.875%"]
                && before.Total === after.Total,
              "before " + JSON.stringify(before) + " after " + JSON.stringify(after));
        /* Put it back, so the claims after this one see the settled screen. */
        var useAgain = document.querySelector(".invsum .heldoffer .heldbtn");
        if (useAgain) useAgain.click();
      } else {
        claim("applying held money leaves the subtotal and the tax alone", false,
              "no Remove to press, so nothing could be compared");
      }

      /* THE SECOND BRANCH, which no still can show. With more than one invoice
         open, nothing is applied and the invoice says why (round C3): two
         allocations of one payment may never both fit (PRD 5.14b), and a
         chooser nobody can see is worse than a question. */
      var counts = document.querySelectorAll(".statebar");
      var twoBtn = counts.length > 1
        ? Array.prototype.filter.call(counts[1].querySelectorAll(".sbtn"),
            function (b) { return /2 invoices open/.test(b.textContent); })[0]
        : null;
      if (!twoBtn) {
        claim("with two invoices open it is applied to neither, and says why", false,
              "the page has no switch for a second open invoice, so that branch "
                + "cannot be drawn at all");
      } else {
        twoBtn.click();
        var stillApplied = document.querySelector(".sline.heldline");
        var why = document.querySelector(".invsum .heldwhy");
        var offered = document.querySelector(".invsum .heldoffer .heldbtn");
        claim("with two invoices open it is applied to neither, and says why",
              !stillApplied && !!why && /invoices are open/.test(why.textContent)
                && !!offered,
              (stillApplied ? "STILL APPLIED" : "not applied")
                + ", " + (why ? JSON.stringify(why.textContent.trim()) : "no reason given")
                + ", " + (offered ? "offered here" : "NOT OFFERED here"));
        /* Back to one, for the claims below. */
        var oneBtn = Array.prototype.filter.call(counts[1].querySelectorAll(".sbtn"),
          function (b) { return /1 invoice open/.test(b.textContent); })[0];
        if (oneBtn) oneBtn.click();
      }
    }

    /* ---- asking before a rare, consequential action ---- */
    var edit2 = Array.prototype.filter.call(
      document.querySelectorAll(".menubar [role=button]"),
      function (s) { return s.textContent === "Edit"; })[0];
    if (edit2) {
      /* OPEN it, never toggle it: an earlier claim can leave the menu standing,
         and a second click would then CLOSE it, so this claim would fail for a
         reason that has nothing to do with what it is about. */
      if (!document.querySelector(".menu")) edit2.click();
      var dismiss = Array.prototype.filter.call(
        document.querySelectorAll(".menu div"),
        function (d) { return d.textContent === "Dismiss this draft"; })[0];
      if (!dismiss) {
        claim("a rare action asks before it acts, and names this shoot", false,
              "the Edit menu has no Dismiss this draft");
      } else {
        dismiss.click();
        var asking = document.querySelector(".askpanel");
        var text = asking ? asking.textContent : "";
        claim("a rare action asks before it acts, and names this shoot",
              !!asking && text.indexOf("Side by Side concert") !== -1
                && text.indexOf("stays in the list") !== -1,
              asking ? text.trim().replace(/\s+/g, " ").slice(0, 120)
                     : "nothing asked");
        if (asking) {
          /* THE DESTRUCTIVE WORD DOES NOT LOOK LIKE THE ORDINARY ONE. It is a
             rule about two colours being DIFFERENT, which no source reading can
             check: written as a bare class it loses to the panel's own more
             specific rule and comes out in the ordinary accent. */
          var harm = asking.querySelector(".harm");
          var ordinary = asking.querySelectorAll(".panelacts button")[0];
          var harmColour = harm ? getComputedStyle(harm).color : null;
          var plainColour = ordinary ? getComputedStyle(ordinary).color : null;
          /* IT IS COMPARED AGAINST THE ACCENT AN ORDINARY CONFIRM IS DRAWN IN,
             not only against the quiet word beside it. Against the quiet word
             alone, removing the destructive colour altogether still passes:
             the button falls back to the accent, which differs from quiet just
             as much. Measured that way it agreed with the right answer for the
             wrong reason. */
          var accent = getComputedStyle(asking).getPropertyValue("--accent").trim();
          var asRgb = /^#[0-9a-fA-F]{6}$/.test(accent)
            ? "rgb(" + parseInt(accent.slice(1, 3), 16) + ", "
                     + parseInt(accent.slice(3, 5), 16) + ", "
                     + parseInt(accent.slice(5, 7), 16) + ")"
            : null;
          if (asRgb === null) {
            /* AN UNREADABLE ACCENT IS ITS OWN ANSWER. Left as the raw string it
               would never equal a computed colour, so half the comparison would
               silently succeed and the claim would pass having checked one
               thing rather than two (L50). The token going missing is exactly
               the fault that made the menu chip stop painting, so it is a
               refusal here rather than a shrug. */
            claim("the destructive word does not look like the ordinary one", false,
                  "the accent could not be read as a colour ("
                    + JSON.stringify(accent) + "), so the comparison could not be made");
          } else {
            claim("the destructive word does not look like the ordinary one",
                  !!harm && !!ordinary && harmColour !== plainColour && harmColour !== asRgb,
                  harm ? harmColour + " against the quiet " + plainColour
                         + " and the ordinary confirm's " + asRgb
                       : "no destructive word");
          }
          if (harm) harm.click();

          /* AN INVOICE RECORDED AS NOT BILLED IS NOT A DELETED ONE (PRD 1b), so
             it stays on screen saying what it now is, and it KEEPS ITS HISTORY:
             this ending of buildInvoice is a second one, and an invoice losing
             its pane depending on which ending it took is a defect nothing on
             screen would explain. */
          var footNow = document.querySelector(".invfoot");
          var quiet = document.querySelector(".inv.notbilled");
          var pane = document.querySelector(".hpane");
          claim("an invoice recorded as not billed says so and keeps its history",
                !!quiet && !!pane && footNow
                  && footNow.textContent.indexOf("recorded as not billed") !== -1,
                (quiet ? "drawn quiet" : "NOT drawn quiet")
                  + ", " + (pane ? "history kept" : "HISTORY GONE")
                  + ", foot says " + JSON.stringify(
                      footNow ? footNow.textContent.trim().replace(/\s+/g, " ").slice(0, 60) : null));
        }
      }
    }

    /* EVERY FIGURE KEEPS ONE RIGHT EDGE, which is what the totals were measured
       twice to protect and what a widened row silently breaks. */
    var edges = {};
    Array.prototype.forEach.call(
      document.querySelectorAll(".lrow .fig:last-child, .sline .fig"),
      function (f) {
        var right = Math.round(f.getBoundingClientRect().right);
        edges[right] = (edges[right] || 0) + 1;
      });
    claim("every figure keeps one right edge", Object.keys(edges).length === 1,
          JSON.stringify(edges));

    /* Nothing may overflow the invoice sideways (L76, L566). */
    var inv = document.querySelector(".inv");
    claim("the invoice does not cut off its own side",
          inv && inv.scrollWidth <= inv.clientWidth + 1,
          inv ? (inv.scrollWidth - inv.clientWidth) + "px over" : "no invoice drawn");
  } catch (err) {
    result.errors.push("THREW " + (err && err.message));
  }
  var out = document.createElement("pre");
  out.id = "ovation-probe";
  out.textContent = JSON.stringify(result);
  document.body.prepend(out);
});
</script>
"""


def fail(message, code=2):
    print("check-invoice-screen-draws: " + message, file=sys.stderr)
    sys.exit(code)


def main(argv):
    if len(argv) > 2:
        fail(__doc__.strip().splitlines()[2].strip())
    path = argv[1] if len(argv) == 2 else DEFAULT_FILE
    if not os.path.isfile(path):
        fail("the design file is not there: %s" % path)

    try:
        browser = find_browser()
    except CannotMeasure as err:
        fail(str(err), 3)
    if browser is None:
        print(NO_BROWSER)
        return 3

    try:
        report = render(browser, path, PROBE)
    except CannotMeasure as err:
        fail(str(err), 3)
    claims = report.get("claims", {})
    if not claims:
        fail("the probe reported no claims at all, so nothing was measured", 3)

    print("Rendered %s in %s" % (os.path.relpath(path, REPO), os.path.basename(browser)))
    broken = []
    for name, outcome in claims.items():
        mark = "ok  " if outcome.get("ok") else "FAIL"
        print("  %s %s: %s" % (mark, name, outcome.get("saw")))
        if not outcome.get("ok"):
            broken.append(name)
    for line in report.get("errors", []):
        print("  FAIL " + line)
        broken.append(line)

    if broken:
        print("\nREFUSED: %d of %d claims about what this file DRAWS did not hold."
              % (len(broken), len(claims)))
        return 1
    print("\nOK: all %d claims about what this file draws held." % len(claims))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
