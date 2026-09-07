# The design record

## The invoice list

`invoice-list.html` is the agreed design for Ovation's main screen, settled with Dan
on 2026-09-06 over eleven rounds. **Open it in any browser.** It is one self contained
file with no build step, committed here rather than left at a hosted URL so it outlives
whatever service rendered it.

**It is a RENDERING, not the app.** It is HTML standing in for a SwiftUI window, so
three things in it are web idioms that must be translated rather than copied:

1. The action words are underlined. **They should not be.** Downbeat already ships the
   right control: `DBPlainButtonStyle` in `Downbeat/UI/Components/DownbeatButtonStyles.swift`,
   a word with padding, no border and no underline, used in 18 places. Ovation's quiet
   tier is that, not a link.
2. The window chrome, the traffic lights and the menu bar are drawn by hand here and are
   drawn by the system in the real app.
3. Type is drawn by the system in a real app. Here the faces are **embedded in the file**,
   so it needs no network at all (see below).

## What the design settles

| | |
| --- | --- |
| Shell | One window. Invoices, Expenses, Clients. Export and Import are File menu commands, Settings is in the app menu. Single window is a hard rule (PRD 41b), asserted by a test. |
| Sidebar | A full height panel in espresso running to the top of the window with the traffic lights on it, which is the macOS pattern when a sidebar carries colour. The title bar exists only over the content. |
| The list | No group headings and no per row chips. Both said what the action word on the right already says. The groups still decide ORDER, they are simply not drawn (see ovation#49). |
| A row | One line at 29px: client and shoot name, shoot date, invoice number or draft, amount, action. Venue and shoot times are deliberately absent and need a home (ovation#95). Where one invoice covers several shoots it names the LAST one, counts the rest, and shows a date span. |
| Actions | A word, not a button. "Mark cleared" and "Mark sent", never "Cleared" or "It was sent": a control says what it does. |
| Selection | A tint only, no left bar. A bar flush against the espresso sidebar is invisible, and a tint is what macOS uses anyway. |
| Counts | Four, in the sidebar card, each appearing exactly once. No inventory counts: a number in the chrome only ever means this many things need you. |
| Idle invoices | Disclosures at the foot, with Sent awaiting payment open by default. No "Nothing to do" label above them: the group names already say it. |
| Colour | Espresso `#3B2B21`. Light mode only, deliberately (PRD 43). No red anywhere (PRD 45). |

## It needs nothing external

**Zero network requests.** The three typefaces are embedded as base64 inside the file, so it
renders identically with no internet, forever. Latin subset only, since the page is pure
ASCII. Archivo is a variable font and Google serves one identical file for all four weights,
verified by hash, so it is embedded once with a weight range rather than four times, which
saved 105KB. All three families are open licensed (OFL), so embedding is permitted. The file
is 119KB as a result, up from 30KB, which is the price of the record being self contained.

`invoice-list.png` is a rendering of the same file at 2x, framed to the window, for when an
image is more convenient than opening the page.

## Type

Instrument Serif for the window title. Archivo for everything else. IBM Plex Mono for
every figure, date and invoice number, always with tabular figures so money aligns.

## Every measurement in it was checked, not eyeballed

Contrast was audited across all candidate palettes and then re-measured in a live browser,
not just computed on paper. The rail palettes cleared 4.5 to 1 on 72 pairs, worst 4.83.
Two faults were caught that way and would not have been caught by looking: a sidebar that
rendered fully transparent because a stale rule pointed at a variable the new palettes did
not define, and a disclosure triangle that arrived as broken characters because it was a
typed glyph rather than a drawn one. **The triangle is now drawn in CSS and the whole file
is pure ASCII**, so no pipe between here and a browser can mangle it.

## What is still open

`ovation#95` where the venue and shoot times live. The receipts queue and the review and
send screen are not designed yet.

**`ovation#18`, the app icon, is settled and shipped (2026-09-07).** It was listed here as
waiting on the palette, and the palette is what it waited for: the artwork is a cream paper
`O` with a receipt curling out of it, on espresso, over a faint bar chart, drawn to sit
inside the colour this file settled rather than the other way round. That inversion was the
point. Downbeat and Overture each derived their palette FROM their icon; Ovation chose the
design language first.

The source artwork is `icon/ovation-app-icon.png` and the shipped catalog is derived from it
by `scripts/build-app-icon.sh`, never by hand. **No drop shadow is composited into the
artwork**, deliberately: macOS draws its own, and a fabricated one inside a build script is
a design decision nobody would ever find to argue with. If the icon should carry one of its
own, that decision belongs here.

**ovation#97 is answered. Its answers opened three things, one of which is now settled.**
It was listed here as blocking on whether a three night run is one invoice or three. It was
not blocking: the PRD had answered it, in three places. What the interview of 2026-09-06
found instead is that the recorded answer was WRONG, and correcting it changes this design
rather than unblocking it.

1. ~~A row assumes one shoot~~ **Settled 2026-09-07 and built into the file.** The row names
   the LAST shoot, counts the others ("+1 shoot"), and shows a span where the days differ.
   Fixing it exposed two faults nothing else would have caught, both found by measuring in a
   browser rather than by looking: the span did not fit the date column, so the row silently
   WRAPPED to two lines and broke the one line rule, and sizing that column to its content
   instead broke the alignment of every column after it, because each row is its own grid.
   See PRD 47a and 47b.
2. ~~Dismissing a draft needs a word on the row~~ **Settled 2026-09-07: it is not on this
   screen at all.** Four placements were rendered, from both actions at equal weight down to
   a right click menu on the row, and Dan rejected all four on one principle: space on the
   main list is earned by frequency, and deciding not to bill is rare. It lives inside the
   invoice instead, so this list is unchanged. See PRD 5.1c, which also records what that
   costs.
3. ~~Money held against a client has no surface~~ **Settled 2026-09-07 as far as it can be
   here: it lives under Clients, not on this list.** It belongs to a client rather than to
   any invoice. How it appears is deliberately left until the Clients screen is designed as
   a whole, rather than deciding one element of a screen that does not exist and settling
   the screen by accident. Tracked as ovation#98. See PRD 5.14a.

## The Clients screen

`clients.html` is the Clients screen in progress, ovation#98. It reuses the invoice list's
shell, type and palette byte for byte, so a round moves one variable and nothing else.
**Open it in a browser.** `#R1` to `#R4` in the address bar select a position directly.

### Round 1, settled 2026-09-07: names on the left, one client on the right

Three shapes were built at the real count of 31 clients, carrying the distribution measured
against the live export on 2026-08-28: six with a tax status, one with no contract email, two
sharing one address.

**Dan chose the two pane shape from the descriptions before the renderings were put in front
of him**, which is recorded because it is the opposite of how every other round here was
decided, and because it means the shape has been chosen rather than seen. It was opened for
him immediately afterwards and stands unless looking at it changes it.

What the shape buys: money held and referral credit get room to be LABELLED, rather than
being two columns whose units the reader has to know, and the client's invoices are on the
same screen. What it spends, stated plainly rather than discovered later: **the left column
carries names and nothing else, so the screen cannot answer who owes what without clicking
each client**, and at 31 clients **15 are visible at once**, measured, so half the roster is
below the fold at any moment.

The other two shapes and what killed them: a flat A to Z list of all 31 put money held in a
column that is empty on 28 rows. A "what needs you first" list, which is the invoice list's
own idea, collapses at these numbers: 27 of 31 rise to the top, because a missing tax status
is the norm rather than the exception until the roster clean up in ovation#40 has been run.
That is the shape working exactly as designed and still being wrong for the data.

### Round 2, settled 2026-09-07: BOTH, on the name and in the sidebar

Four positions on one axis, from the pane alone up to a line in the sidebar card that reaches
every screen. Three of the 31 clients hold money, $1,837.50 between them.

Dan took two of the four together: the amount rides beside the client in the list, so the
screen can say WHICH clients without a click, and a line in the sidebar card carries it to
every screen including Invoices. He added a rule with it: **it must not say Money held 0.**

**One argument put to him against the sidebar line was wrong and is recorded as wrong.** It
was argued that held money is a fact about a client rather than a thing that needs you, and so
did not belong in a card whose every number means this many things need you. Dan's question,
whether applying a deposit to an invoice clears it from this screen, is what exposed it: it
does, so held money counts DOWN as it is dealt with, exactly like the other four, and it fits
the card's rule rather than breaking it.

Two costs were measured in the browser rather than guessed, and both are named on the page
itself rather than left for the implementer to find: putting the amount on the name cuts
"Ashgrove Chamber Players" short in a 240px column, and the strip above the list costs 43px,
which in a real window comes out of the list and drops it from 15 visible clients to 14.

### Round 3, settled 2026-09-07: a count of nothing is not drawn, and one line says so

Nothing in the PRD or in this record has ever decided what a sidebar count does at zero, so
Dan's rule lands on a card that already holds four other lines. Three positions: only the
money line obeys it, every line obeys it and the card disappears, or every line obeys it and
one line says nothing is waiting.

The cost is movement, measured between a busy day and a quiet one as how far Invoices,
Expenses and Clients shift: **26px, 180px and 106px**. None of the three holds perfectly still,
because the money line comes and goes in all of them, and a first draft of the page claimed Z1
did hold still until it was measured.

**Settled on Z3:** one rule for every line in the card, and when it takes all five the card says
`Nothing waiting` rather than disappearing, because a card that draws nothing on the healthy day
is indistinguishable from one that failed to draw.

**The card line is a COUNT of clients, not the total held** (Dan, 2026-09-07, overruling the
amount it first carried). The argument put for the amount was that three clients holding $87.50
between them and one holding $5,000.00 are the same count. The argument that won is the card's
own rule: its four neighbours are counts of things needing you, and a sum among them is a second
kind of number in one small object. The amounts are not lost, they are beside the clients in the
list, which is where the count sends you.

### What the screen still is not

Referral credit sits beside held money as an equal box and nothing yet keeps them from reading
as one balance. The roster clean up has no surface: 25 of the 31 have no tax status and the
screen says it quietly, and two share a contract email and it says nothing at all. And nothing
on the screen is an ACTION: applying held money to an invoice is what makes it useful and there
is no control for it.

### What is deliberately still open

How held money and referral credit are kept from reading as one balance, which is the one with
a real consequence: PRD 5.14c, drawing them alike would let credit nobody paid settle an
invoice. Whether a deposit is distinguishable from an overpayment at all (ovation#96): both
land in held money by design, and the money behaves identically either way. Where the
ovation#40 roster clean up lives, since a shared contract email is currently drawn no
differently from any other. A first attempt marked it one
shade quieter, which measured as no difference at all on screen and was removed rather than
left as a distinction the page claims and does not draw.
