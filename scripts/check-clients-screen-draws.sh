#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
# Started with bash, the line above runs this file under python3 instead (ovation#257).
__doc__ = """Refuse a Clients design file that DRAWS the held money figure wrongly.

    check-clients-screen-draws.sh [design file]

ovation#98, settled 2026-09-10: the name list keeps its held money figure on
every client that has one EXCEPT the client whose box is open beside it, so the
same client's money is never stated twice at once. `check-invoice-screen-draws`
is the neighbour and this is the same argument: every other check on these files
reads their SOURCE, and a rule about what is drawn WHEN SOMETHING IS PRESSED
cannot be seen there at all.

IT IS A RULE ABOUT A PRESS, WHICH IS WHY IT NEEDS A BROWSER. The file's own
repaint used to touch only the selection class and the detail pane, never the
rows, so a first implementation of this rule draws correctly on load and then
never again: the figure stays missing from whoever was selected when the page
opened and stays present on whoever you actually click. That version passes
every reading of the source and every claim that does not press anything, and
it is exactly the version this check plants in its own suite.

WHAT IT CLAIMS, and each is one way the rule can be got wrong:

  1. With a client holding nothing selected, which is the state the file opens
     in, every holder carries its figure.
  2. Pressing a holder takes the figure off ITS row and leaves the others alone.
  3. Pressing another holder moves it: the newly selected row loses the figure
     and the one just left gets it back.
  4. Pressing a client that holds NO money leaves all three figures drawn, which
     is the claim that catches a repaint hiding the figure on every row.
  5. The selected holder's own box still states the money, so what the row gave
     up is stated exactly once rather than nowhere.

AND THE REST OF THE SCREEN (ovation#186, ovation#209). Eight rounds settled this
file and each was measured by hand on the day and by nothing since, so these are
claimed in THIS check rather than in a second one, which would be one more
browser start in the CI step ovation#183 already counts:

  6. The two balances are told apart by their faces (PRD 14f): the held money
     value is in the mono tabular face and the referral credit in the body face,
     compared as COMPUTED styles, because a rule written as a bare class loses to
     a more specific one and comes out identical while the source reads right.
  7. A single arrival is never broken down, and a balance of two is (PRD 14l).
  8. The payment terms value opens the four terms (PRD 51j), and
  9. choosing one changes the value, closes the list and keeps the selected
     client, which is three things a person meets after the press.
 10. A roster section with nothing in it is not drawn (PRD 5a, ovation#209),
     measured on the day switch's day with the address fixed, and only believed
     when that day really draws fewer sections than the day with work.
 11. The roster pass reports the number it started with, as the clients in it
     and never the section counts added together.
 12. Standing on the roster as it empties keeps it, saying nothing is left, and
 13. on a settled day the roster is gone from the rail.
 14. A quantity of nothing is not drawn, on the clients screen or the rail: no
     box for a balance a client does not hold, and on a settled day no count, no
     held line and no figure on any row.

THE DAY SWITCH IS PRESSED, NEVER SET. It names the day it moves to in
`data-day`, so reaching a day is pressing the real control, and a switch that
never gets there is a refusal rather than a claim made on the wrong day.

EVERY CLAIM ABOUT A SELECTED HOLDER IS MADE AFTER A PRESS, never on load. The
file opens on a client who holds nothing, so on load the selected row has no
figure to give up and the rule's own case has not arisen: a claim made there
would pass on a file that has never implemented it (L98).

WHICH CLIENTS HOLD MONEY IS READ FROM THE PAGE'S OWN DATA, never from the marks
on screen, because a file drawing no figure anywhere would otherwise satisfy
every claim about where figures are not (L98).

IT REFUSES TO GUESS WHEN IT CANNOT MEASURE. With no headless browser it exits 3
and says so, rather than exiting 0, because "every claim held" and "nothing was
checked" must never be the same answer.

Exit codes: 0 every claim held, 1 a claim failed, 2 used wrongly, 3 cannot
measure. Set OVATION_HEADLESS_BROWSER to name the browser binary.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

from design_render import CannotMeasure, open_browser  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_FILE = os.path.join(REPO, "docs/design/clients.html")

PROBE = r"""
<script>
window.addEventListener("load", function () {
  var result = { claims: {}, notes: [], errors: [] };
  function claim(name, ok, saw) { result.claims[name] = { ok: !!ok, saw: saw }; }

  function rows() {
    var out = {};
    Array.prototype.forEach.call(document.querySelectorAll(".names .nrow"), function (n) {
      out[n.dataset.client] = {
        node: n,
        selected: n.classList.contains("sel"),
        figure: n.querySelector(".nheld") ? n.querySelector(".nheld").textContent.trim() : null
      };
    });
    return out;
  }

  /* The clients that hold money, from the page's own data rather than from what
     it drew: a file drawing no figure at all must not satisfy claims about where
     figures are absent. */
  function holders() {
    return (typeof HELD === "undefined" ? [] : HELD).map(function (k) { return k.c; });
  }

  /* ---------------------------------------------------------------------------
     THE REST OF THE SCREEN (ovation#186, ovation#209). Every client named below
     is chosen from the page's own data by what it HOLDS, never by name, so a
     fixture that changes cannot turn a claim into one about nobody (L98).
     --------------------------------------------------------------------------- */
  function pick(test) { return CLIENTS.filter(test)[0]; }
  function pressClient(c) {
    var r = rows()[c];
    if (!r) throw new Error("no name row for a client the page's own data lists");
    r.node.click();
  }
  function boxesByLabel() {
    var out = {};
    Array.prototype.forEach.call(document.querySelectorAll(".detail .mbox"), function (b) {
      var l = b.querySelector(".mlabel");
      out[l ? l.textContent.trim() : "(no label)"] = b;
    });
    return out;
  }
  function railItem(label) {
    return Array.prototype.filter.call(document.querySelectorAll(".side .item"), function (n) {
      return n.textContent.trim() === label;
    })[0] || null;
  }
  /* A FIGURE THAT SAYS NOTHING. Zero in any spelling the screen uses, or an
     element drawn to hold a figure with no figure in it, which is the same
     absence with a label over it.

     A FIGURE THAT DOES NOT PARSE IS REPORTED TOO, never read as "not zero".
     Number() answers NaN rather than failing, NaN loses every comparison, so
     `NaN === 0` would wave a `NaN` or `undefined` drawn in a money box straight
     through as a real figure (L50). */
  var FIGURES = ".card .ln b, .railheld b, .nheld, .mval, .aamt, .passhead .n";
  function nothingDrawn() {
    var out = [];
    Array.prototype.forEach.call(document.querySelectorAll(FIGURES), function (n) {
      var bare = n.textContent.replace(/[$,\s]|hrs?/g, "");
      var value = bare === "" ? NaN : Number(bare);
      var where = "'" + n.textContent.trim() + "' in ." + n.className.split(" ")[0];
      if (bare === "") out.push("an empty figure " + where);
      else if (isNaN(value)) out.push("a figure that is not a number " + where);
      else if (value === 0) out.push("a zero " + where);
    });
    return out;
  }
  /* THE DAY SWITCH IS PRESSED, never set, and it names the day it moves TO in
     `data-day`. It cycles, so reaching a day means pressing until the press that
     was about to move there has happened; a switch that never reaches it is a
     refusal rather than a claim quietly made on the wrong day. */
  function pressDay(key) {
    for (var i = 0; i < 4; i++) {
      var b = document.querySelector("[data-day]");
      if (!b) return false;
      var next = b.getAttribute("data-day");
      b.click();
      if (next === key) return true;
    }
    return false;
  }
  function rosterReading() {
    var heads = Array.prototype.map.call(document.querySelectorAll(".pass .passhead"), function (h) {
      var drawn = 0, sib = h.nextElementSibling;
      while (sib && !sib.classList.contains("passhead") && !sib.classList.contains("passfoot")) {
        drawn++;
        sib = sib.nextElementSibling;
      }
      var t = h.querySelector("h6"), n = h.querySelector(".n");
      return { title: t ? t.textContent.trim() : "", said: n ? n.textContent.trim() : "", rows: drawn };
    });
    var names = {};
    Array.prototype.forEach.call(document.querySelectorAll(".pass .pname"), function (p) {
      names[p.textContent.trim()] = true;
    });
    var foot = document.querySelector(".passfoot b");
    var meta = document.querySelector(".main .toolbar .meta");
    return { heads: heads, distinct: Object.keys(names).length,
             foot: foot ? foot.textContent.trim() : "", meta: meta ? meta.textContent.trim() : "" };
  }
  function sayRoster(r) {
    return r.heads.map(function (h) { return h.title + " says " + h.said + " over " + h.rows + " row(s)"; })
             .join("; ") + " | " + r.distinct + " distinct client(s) | foot '" + r.foot + "' | meta '" + r.meta + "'";
  }
  function sectionsHonest(r) {
    return r.heads.length > 0 && r.heads.every(function (h) {
      return h.rows > 0 && h.said === String(h.rows);
    });
  }
  function startedHonest(r) {
    var m = /^Started with (\d+) of (\d+)$/.exec(r.foot);
    return !!m && Number(m[1]) === r.distinct && Number(m[2]) === CLIENTS.length &&
           r.meta === m[1] + " of " + m[2] + " clients";
  }

  function drivesTheRest() {
    var both = pick(function (k) { return k.h && k.r; });
    var neither = pick(function (k) { return !k.h && !k.r; });
    var creditOnly = pick(function (k) { return k.r && !k.h; });
    var heldOnly = pick(function (k) { return k.h && !k.r; });
    if (!both || !neither || !creditOnly || !heldOnly) {
      result.errors.push("the fixture lacks a client holding both balances, neither, credit alone " +
                         "or money alone, so the claims about the balances cannot be measured");
      return;
    }

    /* ---- PRD 14f: the two balances are told apart by their FACES. Compared as
       computed styles, because a rule written as a bare class loses to a more
       specific one and comes out identical while the source reads correctly. */
    pressClient(both.c);
    var bx = boxesByLabel();
    var busyBoxes = Object.keys(bx).length;
    var heldVal = bx["Money held"] ? bx["Money held"].querySelector(".mval") : null;
    var credVal = bx["Referral credit"] ? bx["Referral credit"].querySelector(".mval") : null;
    var bodyFace = getComputedStyle(document.querySelector(".detail")).fontFamily;
    if (heldVal && credVal) {
      var hs = getComputedStyle(heldVal), cs = getComputedStyle(credVal);
      claim("the held money value is in the mono tabular face and the referral credit in the body face",
            /IBM Plex Mono/.test(hs.fontFamily) && /tabular-nums/.test(hs.fontVariantNumeric) &&
            cs.fontFamily === bodyFace && !/IBM Plex Mono/.test(cs.fontFamily) &&
            !/tabular-nums/.test(cs.fontVariantNumeric),
            "held " + hs.fontFamily.split(",")[0] + " " + hs.fontVariantNumeric +
            "; credit " + cs.fontFamily.split(",")[0] + " " + cs.fontVariantNumeric +
            "; body " + bodyFace.split(",")[0]);
    } else {
      claim("the held money value is in the mono tabular face and the referral credit in the body face",
            false, "a client holding both balances did not draw both boxes");
    }

    /* ---- PRD 14l: a single arrival is never broken down, and two are ---- */
    var arrivals = typeof ARRIVALS === "undefined" ? {} : ARRIVALS;
    var several = HELD.filter(function (k) { return (arrivals[k.c] || []).length > 1; });
    var single = HELD.filter(function (k) { return (arrivals[k.c] || []).length === 1; });
    if (several.length === 0 || single.length === 0) {
      result.errors.push("the fixture needs a balance of one arrival and one of several, " +
                         "so the claim about breaking a balance down cannot be measured");
    } else {
      var seen = [], ok = true;
      several.concat(single).forEach(function (k) {
        pressClient(k.c);
        var box = boxesByLabel()["Money held"];
        var listed = box ? box.querySelectorAll(".arrival").length : -1;
        var noted = box ? box.querySelectorAll(".mnote").length : -1;
        var want = arrivals[k.c].length;
        var right = want > 1 ? listed === want : (listed === 0 && noted === 1);
        if (!right) ok = false;
        seen.push(want + " arrival(s): " + listed + " listed, " + noted + " note(s)");
      });
      claim("a single arrival is never broken down, and a balance of two is", ok, seen.join("; "));
    }

    /* ---- a quantity of nothing is not drawn, on the clients screen ---- */
    var nothing = [];
    function noBox(k, label) {
      pressClient(k.c);
      var have = boxesByLabel();
      if (label ? have[label] : Object.keys(have).length) {
        nothing.push((label || "a money box") + " drawn for a client holding none");
      }
      if (!label && document.querySelector(".detail .money")) {
        nothing.push("an empty money row drawn for a client holding nothing");
      }
      nothing = nothing.concat(nothingDrawn());
    }
    noBox(neither, null);
    noBox(creditOnly, "Money held");
    noBox(heldOnly, "Referral credit");

    /* ---- PRD 51j: the payment terms value is the control ---- */
    pressClient(heldOnly.c);
    var terms = typeof TERMS === "undefined" ? [] : TERMS;
    var btn = document.querySelector(".detail .termbtn");
    var before = btn ? btn.textContent.trim() : "";
    if (btn) btn.click();
    var offered = Array.prototype.map.call(document.querySelectorAll(".detail .termlist .termitem"),
                                           function (n) { return n.textContent.trim(); });
    claim("the payment terms value opens the four terms",
          !!btn && terms.length === 4 && offered.join("|") === terms.join("|"),
          (btn ? "pressed " + before : "no terms control drawn") + ", offered " +
          (offered.join(", ") || "nothing") + " against " + terms.join(", "));
    var target = terms.filter(function (t) { return t !== before; }).slice(-1)[0];
    var item = Array.prototype.filter.call(document.querySelectorAll(".detail .termlist .termitem"),
                                           function (n) { return n.textContent.trim() === target; })[0];
    if (!item) {
      claim("choosing a term changes the value, closes the list and keeps the selected client",
            false, "the list never offered " + target + ", so nothing could be chosen");
    } else {
      item.click();
      var after = document.querySelector(".detail .termbtn");
      var sel = document.querySelector(".names .nrow.sel");
      var head = document.querySelector(".detail h5");
      claim("choosing a term changes the value, closes the list and keeps the selected client",
            !!after && after.textContent.trim() === target &&
            !document.querySelector(".termlist") &&
            !!sel && sel.dataset.client === heldOnly.c && !!head && head.textContent.trim() === heldOnly.c,
            "chose " + target + ": value " + (after ? after.textContent.trim() : "gone") +
            ", list " + (document.querySelector(".termlist") ? "still open" : "closed") +
            ", selected " + (sel && sel.dataset.client === heldOnly.c ? "kept" : "changed") +
            ", pane " + (head && head.textContent.trim() === heldOnly.c ? "kept" : "changed"));
    }

    /* ---- the roster pass, on the day with work, then with the addresses fixed ---- */
    var toRoster = railItem("Settle the roster");
    if (!toRoster) {
      result.errors.push("the rail offers no roster on a day with work waiting, so nothing about " +
                         "the pass can be measured");
      return;
    }
    toRoster.click();
    var busy = rosterReading();
    if (!pressDay("addresses")) {
      result.errors.push("the day switch never reached the day the addresses are fixed, so the " +
                         "empty section cannot be drawn");
      return;
    }
    var fixed = rosterReading();
    /* THE SWITCH HAS TO HAVE EMPTIED SOMETHING, or a pass that draws the same
       sections on both days satisfies every word of the claim (L98). */
    claim("a roster section with nothing in it is not drawn",
          sectionsHonest(busy) && sectionsHonest(fixed) && fixed.heads.length < busy.heads.length,
          "work waiting: " + sayRoster(busy) + " || addresses fixed: " + sayRoster(fixed));
    claim("the roster pass reports the number it started with",
          startedHonest(busy) && startedHonest(fixed),
          "work waiting: " + sayRoster(busy) + " || addresses fixed: " + sayRoster(fixed));

    /* ---- the settled day, standing on the roster and then leaving it ---- */
    if (!pressDay("quiet")) {
      result.errors.push("the day switch never reached a settled day, so nothing about it can be measured");
      return;
    }
    var done = document.querySelector(".pass .queue h5");
    var stillThere = railItem("Settle the roster");
    claim("standing on the roster as it empties keeps it, saying nothing is left",
          !!stillThere && !!done && /Nothing left to settle/.test(done.textContent),
          "rail " + (stillThere ? "still offers it" : "dropped it") + ", screen says " +
          (done ? "'" + done.textContent.trim() + "'" : "nothing"));
    var toClients = railItem("Clients");
    if (!toClients) {
      result.errors.push("the rail offers no Clients item, so the settled day cannot be left");
      return;
    }
    toClients.click();
    claim("on a settled day the roster is gone from the rail",
          !railItem("Settle the roster"),
          "rail: " + Array.prototype.map.call(document.querySelectorAll(".side .item"),
                                              function (n) { return n.textContent.trim(); }).join(", "));

    /* The same rule on the settled day: the client who held both balances on the
       day with work now shows neither, and the rail says no count and no sum. */
    pressClient(both.c);
    if (Object.keys(boxesByLabel()).length) nothing.push("a money box drawn on a settled day");
    if (document.querySelector(".names .nheld")) nothing.push("a held figure on a name row on a settled day");
    if (document.querySelector(".card .ln")) nothing.push("a count in the card on a settled day");
    if (document.querySelector(".railheld")) nothing.push("the rail's held money line on a settled day");
    nothing = nothing.concat(nothingDrawn());
    claim("a quantity of nothing is not drawn on the clients screen or the rail",
          nothing.length === 0 && busyBoxes === 2,
          (nothing.join("; ") || "nothing drawn for any absent quantity") +
          " | the client holding both drew " + busyBoxes + " box(es) on the day with work");
  }

  function describe(map, who) {
    return who.map(function (c) {
      var r = map[c];
      if (!r) return c + ": NO ROW";
      return c + ": " + (r.figure || "no figure") + (r.selected ? " (selected)" : "");
    }).join("; ");
  }

  try {
    var who = holders();
    if (who.length < 2) {
      result.errors.push("the file's own data lists " + who.length +
        " client(s) holding money, and this rule cannot be measured under two");
    } else {
      /* ---- 1, the state the file OPENS in, which is a client holding nothing ---- */
      var onLoad = rows();
      var openSelection = Object.keys(onLoad).filter(function (c) { return onLoad[c].selected; });
      var missingOnLoad = who.filter(function (c) {
        return !onLoad[c] || onLoad[c].figure === null;
      });
      claim("with a client holding nothing selected, every holder carries its figure",
            missingOnLoad.length === 0 && openSelection.length === 1 &&
            who.indexOf(openSelection[0]) === -1,
            describe(onLoad, who) + " | selected: " + (openSelection.join(",") || "none"));

      /* THE RULE'S OWN CASE HAS TO BE REACHED BY PRESSING. The file opens on a
         client who holds nothing, so on load the selected row has no figure to
         give up and every claim about the selected holder is true of a case that
         did not arise (L98). Everything below is measured after pressing one. */
      var first = who[0], second = who[1];
      onLoad[first].node.click();
      var held = rows();
      var others = who.filter(function (c) { return c !== first; });
      claim("pressing a holder takes the figure off ITS row and leaves the others",
            held[first] && held[first].figure === null && held[first].selected &&
            others.every(function (c) { return held[c] && held[c].figure !== null; }),
            describe(held, who));

      /* ---- the box still says it, for the holder now selected ---- */
      var boxLabel = document.querySelector(".mlabel");
      var box = document.querySelector(".mval");
      claim("the selected holder's own box still states the money",
            !!(box && boxLabel && /Money held/.test(boxLabel.textContent) &&
               /\d/.test(box.textContent)),
            box && boxLabel ? boxLabel.textContent.trim() + " " + box.textContent.trim()
                            : "no money box drawn");

      /* ---- pressing another holder moves it ---- */
      held[second].node.click();
      var moved = rows();
      claim("pressing another holder moves the figure off it and back onto the one left",
            moved[second] && moved[second].figure === null &&
            moved[first] && moved[first].figure !== null,
            describe(moved, who));

      /* ---- pressing a client with no money leaves every figure drawn ---- */
      var poor = Object.keys(moved).filter(function (c) { return who.indexOf(c) === -1; })[0];
      if (!poor) {
        result.errors.push("every client in the fixture holds money, so the claim about " +
                           "pressing one that holds nothing cannot be measured");
      } else {
        moved[poor].node.click();
        var third = rows();
        var missing = who.filter(function (c) { return !third[c] || third[c].figure === null; });
        claim("pressing a client holding nothing leaves every figure drawn",
              missing.length === 0,
              describe(third, who) + " | pressed: " + poor);
      }
      drivesTheRest();
    }
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
    print("check-clients-screen-draws: " + message, file=sys.stderr)
    sys.exit(code)


def main(argv):
    if len(argv) > 2:
        fail(__doc__.strip().splitlines()[2].strip())
    path = argv[1] if len(argv) == 2 else DEFAULT_FILE
    if not os.path.isfile(path):
        fail("the design file is not there: %s" % path)

    try:
        session = open_browser()
    except CannotMeasure as err:
        # IN THE WORDS, not only in the exit code (ovation#214). This branch used
        # to print a bare sentence while its four sibling rendering checks all
        # print CANNOT MEASURE, so a reader of the output could not tell a run
        # that measured nothing from one that measured and found nothing (L11,
        # L98). The code was always 3; only the sentence was missing.
        print("CANNOT MEASURE: %s" % err)
        return 3

    try:
        report = session.render(path, PROBE)
    except CannotMeasure as err:
        # IN THE WORDS, not only in the exit code (ovation#214). This branch used
        # to print a bare sentence while its four sibling rendering checks all
        # print CANNOT MEASURE, so a reader of the output could not tell a run
        # that measured nothing from one that measured and found nothing (L11,
        # L98). The code was always 3; only the sentence was missing.
        print("CANNOT MEASURE: %s" % err)
        return 3
    claims = report.get("claims", {})
    errors = report.get("errors", [])
    if not claims and not errors:
        fail("the probe reported no claims at all, so nothing was measured", 3)

    print("Rendered %s in %s" % (os.path.relpath(path, REPO), os.path.basename(session.path)))
    broken = []
    for name, outcome in claims.items():
        mark = "ok  " if outcome.get("ok") else "FAIL"
        print("  %s %s: %s" % (mark, name, outcome.get("saw")))
        if not outcome.get("ok"):
            broken.append(name)
    for line in errors:
        print("  FAIL " + line)
        broken.append(line)

    if broken:
        print("\nREFUSED: %d of %d claims about what this file DRAWS did not hold."
              % (len(broken), len(claims) + len(errors)))
        return 1
    print("\nOK: all %d claims about what this file draws held." % len(claims))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
