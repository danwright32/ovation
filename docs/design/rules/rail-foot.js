/* THE FOOT OF THE RAIL: EACH OPEN THING BY A SHORT NAME, WITH READ BESIDE IT,
   AND READ OPENING A POPOVER (Dan, 2026-09-26, four rendered rounds on ovation#99
   and ovation#566, PRD 44c to 44f). Each answer is quoted from the comment that
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

   ONE COPY FOR EVERY SCREEN THAT DRAWS THE RAIL, because the rail is chrome and
   the foot is part of it: three files drawing it by hand is three places for the
   retired count to come back.
   CARRIED BY: invoice-list.html, invoice.html, clients.html */

/* The lines the foot draws for the items open, newest first. `drawn` false is
   the zero rule: no foot at all, not a foot saying nothing. */
function footLines(items) {
  var names = items.slice(0, 2);
  var rest = items.length - names.length;
  return { drawn: items.length > 0, names: names,
           more: rest > 0 ? "and " + rest + " more" : null };
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
   folder rather than as one person's full path. */
var RAIL_OPEN = [
  { key: "export", short: "2026 export written", closesOnceRead: true,
    sentence: "The 2026 export is written: income.csv, expenses.csv, manifest.json in "
      + "~/Library/Application Support/Ovation/exports. Every row was read back off the "
      + "disk and reconciled against a second reading of the store before this was said." },
  { key: "backup", short: "Backup 3 days behind", closesOnceRead: false,
    sentence: "Your work on 2026-09-23 is in no backup: the newest was taken on 2026-09-20." }
];
var RAIL_READING = null;

function railEl(tag, cls, text) {
  var n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined) n.textContent = text;
  return n;
}

/* The foot and, while one is being read, its popover. The caller puts the foot
   at the bottom of the rail and the popover in the window's `.app`, then calls
   placeRailPop once both are on the page. A settled day has nothing open. */
function railFootFor(quiet, redraw) {
  var items = quiet ? [] : RAIL_OPEN;
  var lines = footLines(items);
  if (!lines.drawn) return { foot: null, pop: null };
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
  if (lines.more) st.append(railEl("div", "also", lines.more));
  st.append(railEl("div", "looked", "Last looked for bookings and receipts 2 minutes ago. "
    + "Ovation only looks while it is open."));
  return { foot: st, pop: pop };
}

/* Anchored to the Read that opened it, pointing at it, and kept inside the
   window. Measured from the page, so it has to run once the window is on it. */
function placeRailPop() {
  var pop = document.querySelector(".railpop");
  var read = document.querySelector('.status .read[aria-expanded="true"]');
  if (!pop || !read) return;
  var a = pop.parentElement.getBoundingClientRect(), r = read.getBoundingClientRect();
  var mid = r.top + r.height / 2 - a.top;
  var h = pop.getBoundingClientRect().height;
  var top = Math.max(12, Math.min(mid - h + 30, a.height - h - 12));
  pop.style.left = Math.round(r.right - a.left + 14) + "px";
  pop.style.top = Math.round(top) + "px";
  pop.querySelector(".railarrow").style.top = Math.round(mid - top - 7) + "px";
}
