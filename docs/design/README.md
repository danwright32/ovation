# The invoice list design

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

`ovation#95` where the venue and shoot times live. `ovation#18` the app icon, which was
waiting on the palette and is now unblocked. The receipts queue and the review and send
screen are not designed yet.

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
