/* THE FOOT OF THE RAIL: EACH OPEN THING BY A SHORT NAME, WITH READ BESIDE IT,
   AND READ OPENING A POPOVER (Dan, 2026-09-26, four rendered rounds on ovation#99
   and ovation#566, PRD 44c to 44g). Each answer is quoted from the comment that
   records it.

   THE FORM. Asked "How should the first problem and Read sit at the bottom of the
   sidebar?", answer "Shortened beside Read": "the rail foot shows a one line
   short name for the first problem with Read beside it, Read looking like a
   control at rest, and the full sentence only behind Read. It fits at the 620
   point minimum window height with the longest real sentence, which the two full
   sentence options did not." (ovation#99)

   A NOTICE THAT ARRIVES MID SESSION. Asked "Where does a notice go when it
   arrives while an invoice is open?", answer "In the sidebar's foot": "an unread
   notice mid session becomes the rail foot's first line in the form settled on
   ovation#99 ... nothing drawn over the content, the invoice left open."
   (ovation#566)

   WHAT READ OPENS. Asked "What should pressing Read in the sidebar's foot
   open?", answer "Popover from Read": "Read opens a popover anchored to Read
   holding the full sentence and "I have read this", and nothing else moves; the
   invoice stays open." Measured in that round: 300 by 207 points, 8 lines for
   the export sentence. (ovation#99, ovation#566)

   THE WORDS. Asked "What should the lines at the foot of the sidebar say?",
   answer "Name each open thing": "the foot carries no count. Each open item gets
   its own line, its short name with its own Read beside it, newest first, at
   most two lines, then "and N more". Read and unread items look the same (a
   notice closes once read, so what stays is standing problems). Nothing open:
   the whole foot disappears (the zero rule). This retires both "1 more to read"
   and "1 other problem" in the foot." (ovation#99, ovation#566)

   THE LAST LOOKED LINE STAYS. Asked "On a day with nothing open, should the
   sidebar still say when Ovation last looked for bookings and receipts?", answer
   "Keep that line": "the zero rule removes only the problem and notice lines:
   the "Last looked for bookings and receipts ... Ovation only looks while it is
   open." line stays on every day (PRD 32), so a quiet foot still proves Ovation
   is checking." (Dan, 2026-09-27, ovation#566)

   A NOTICE UNREAD AT LAUNCH. Asked "When Ovation opens with an unread notice
   waiting, what happens?", answer "Foot, like the rest": "a notice unread at
   launch goes in the rail foot with Read like any other, and Ovation opens
   straight onto the shell". So nothing here tells a launch notice apart.
   (Dan, 2026-09-26, ovation#566)

   WHAT "AND N MORE" DOES. Asked "What should 'and N more' at the foot of the
   sidebar do?", answer "Opens a list pop-up": ""and N more" is a control like
   Read: it opens a popover beside it listing every open item, each with its full
   sentence and "I have read this", so every open problem and notice can be read
   from the shell." (ovation#566)

   ONE COPY FOR EVERY SCREEN THAT DRAWS THE RAIL, because the rail is chrome and
   the foot is part of it: three files drawing it by hand is three places for the
   retired count to come back.
   CARRIED BY: invoice-list.html, invoice.html, clients.html */

/* The lines the foot draws for the items open, newest first. `drawn` false is
   the zero rule: no problem or notice line, not a line saying nothing. `looked`
   is drawn on every day, open items or none. `listed` is what
   "and N more" opens: every open item, the two named above it included, and
   nothing when there is no such line. */
function footLines(items) {
  var names = items.slice(0, 2);
  var rest = items.length - names.length;
  return { drawn: items.length > 0, names: names,
           looked: "Last looked for bookings and receipts 2 minutes ago. "
             + "Ovation only looks while it is open.",
           more: rest > 0 ? "and " + rest + " more" : null,
           listed: rest > 0 ? items.slice() : [] };
}

/* What is still open once one item is read. A notice closes once read; a
   standing problem stays open until its condition clears. A new list, never the
   one given changed in place. */
function afterRead(items, key) {
  return items.filter(function (it) { return !(it.key === key && it.closesOnceRead); });
}

/* THE TWO REAL ITEMS THE ROUNDS WERE DRAWN WITH, newest first: the year end
   export's result (YearEndExportCommand's sentence for a written export, a
   notice) and the stale backup (StoreLaunchSequence's, a standing problem). The
   short names are the ones the rounds wrote; the folder is written from the home
   folder rather than as one person's full path. A THIRD, oldest, so that "and 1
   more" is drawn and can be pressed: BookingDraftCommand's notice for bookings
   drafted from the queue, whose short name no round wrote. */
var RAIL_OPEN = [
  { key: "export", short: "2026 export written", closesOnceRead: true,
    sentence: "The 2026 export is written: income.csv, expenses.csv, manifest.json in "
      + "~/Library/Application Support/Ovation/exports. Every row was read back off the "
      + "disk and reconciled against a second reading of the store before this was said." },
  { key: "backup", short: "Backup 3 days behind", closesOnceRead: false,
    sentence: "Your work on 2026-09-23 is in no backup: the newest was taken on 2026-09-20." },
  { key: "bookings", short: "2 bookings drafted", closesOnceRead: true,
    sentence: "2 booking(s) from the queue are now drafts, waiting on the shoot times "
      + "before they can be sent." }
];
var RAIL_READING = null;
var RAIL_LIST = "and-more";

function railEl(tag, cls, text) {
  var n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined) n.textContent = text;
  return n;
}

/* The foot and, while one is being read, its popover. The caller puts the foot
   at the bottom of the rail and the popover in the window's `.app`, then calls
   placeRailPop once both are on the page. A settled day has nothing open, and
   its foot is the last looked line alone. */
function railFootFor(quiet, redraw) {
  var items = quiet ? [] : RAIL_OPEN;
  var lines = footLines(items);
  var st = railEl("div", "status");
  var pop = null;
  lines.names.forEach(function (it) {
    var row = railEl("div", "fault");
    var read = railEl("button", "read", "Read");
    read.type = "button";
    read.setAttribute("aria-expanded", String(RAIL_READING === it.key));
    read.addEventListener("click", function () {
      RAIL_READING = RAIL_READING === it.key ? null : it.key;
      redraw();
      placeRailPop();
    });
    row.append(railEl("b", null, it.short), read);
    st.append(row);
    if (RAIL_READING === it.key) {
      pop = railEl("div", "railpop");
      pop.setAttribute("role", "dialog");
      pop.setAttribute("aria-label", it.short);
      var ack = railEl("button", "railack", "I have read this");
      ack.type = "button";
      ack.addEventListener("click", function () {
        RAIL_OPEN = afterRead(RAIL_OPEN, it.key);
        RAIL_READING = null;
        redraw();
        placeRailPop();
      });
      pop.append(railEl("div", "railsay", it.sentence), ack, railEl("div", "railarrow"));
    }
  });
  if (lines.more) {
    var more = railEl("button", "more", lines.more);
    more.type = "button";
    more.setAttribute("aria-expanded", String(RAIL_READING === RAIL_LIST));
    more.addEventListener("click", function () {
      RAIL_READING = RAIL_READING === RAIL_LIST ? null : RAIL_LIST;
      redraw();
      placeRailPop();
    });
    st.append(more);
    if (RAIL_READING === RAIL_LIST) {
      pop = railEl("div", "railpop");
      pop.setAttribute("role", "dialog");
      pop.setAttribute("aria-label", "Everything open");
      lines.listed.forEach(function (it) {
        var entry = railEl("div", "railitem");
        var ack = railEl("button", "railack", "I have read this");
        ack.type = "button";
        ack.addEventListener("click", function () {
          RAIL_OPEN = afterRead(RAIL_OPEN, it.key);
          if (!footLines(RAIL_OPEN).more) RAIL_READING = null;
          redraw();
          placeRailPop();
        });
        entry.append(railEl("div", "railname", it.short), railEl("div", "railsay", it.sentence), ack);
        pop.append(entry);
      });
      pop.append(railEl("div", "railarrow"));
    }
  }
  st.append(railEl("div", "looked", lines.looked));
  return { foot: st, pop: pop };
}

/* Anchored to the control that opened it, pointing at it, and kept inside the
   window. It starts just past the sidebar's edge rather than just past the
   control, because "and 1 more" is short and a popover beside it would cover the
   very names above it. Measured from the page, so it has to run once the window
   is on it. */
function placeRailPop() {
  var pop = document.querySelector(".railpop");
  var read = document.querySelector('.status [aria-expanded="true"]');
  if (!pop || !read) return;
  var a = pop.parentElement.getBoundingClientRect(), r = read.getBoundingClientRect();
  var mid = r.top + r.height / 2 - a.top;
  var h = pop.getBoundingClientRect().height;
  var top = Math.max(12, Math.min(mid - h + 30, a.height - h - 12));
  var side = document.querySelector(".side");
  var edge = side ? Math.max(r.right, side.getBoundingClientRect().right) : r.right;
  pop.style.left = Math.round(edge - a.left + 10) + "px";
  pop.style.top = Math.round(top) + "px";
  pop.querySelector(".railarrow").style.top = Math.round(mid - top - 7) + "px";
}
