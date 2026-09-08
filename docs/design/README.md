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

**Zero network requests, and `scripts/check-design-self-contained.sh` is what keeps that true.**
It runs in the ordinary suite and on every push, and refuses any file here that reaches the network
OR names another file on disk. Until ovation#114 this paragraph was a claim with nothing behind it:
a `<link>` to a font service added by anyone would have made it false with no symptom at all, since
the file goes on rendering perfectly on a machine with a network and fails only years later,
offline, which is the exact scenario the embedding exists for.

The three typefaces are embedded as base64 inside the file, so it
renders identically with no internet, forever. `scripts/embed-web-fonts.py` is what does the
embedding (ovation#115), so the step is the same for every file rather than as good as whoever did
it that day: it takes a Google Fonts CSS URL, keeps the latin subset, folds a variable font served
as one file into a single face with a weight range, and REFUSES a face it could not verify rather
than emitting one. A face that quietly fails to embed falls back to a system font and the page
still looks finished. Latin subset only, since the page is pure
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

`ovation#95` where the venue and shoot times live. The receipts queue (`ovation#100`), the
review and send screen (`ovation#101`) and the invoice screen inside the app (`ovation#111`)
are not designed yet.

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

## The invoice PDF

`invoice-pdf.html` is the agreed design for the document a client receives, settled with Dan
on 2026-09-07 over five rounds, tracked as `ovation#93`. **Open it in a browser.** The buttons
above the page switch which invoice is shown, which is behaviour rather than a chooser: the
rules only become visible under the six inputs that exercise them.

**It answers to the LETTERHEAD, not to the app.** This is the only Ovation surface a client
ever sees, so it obeys Dan Wright Photography's stationery rather than the espresso interface
language every other file here shares. It also has to survive being printed in black and white,
opened in a mail preview pane, and read by an accounts department.

**The brand kit and the letterhead disagree, and the letterhead won.** The kit (v1.0, 2025)
specifies Deep Teal Blue `#2E5866` and Warm Cream `#F5E6D3`. Measured from a render of
`Letterhead.psd`, the actual stationery uses neither: header band `#9FD4C6`, footer bar
`#7FA99E`, banner `#221F20`, ground `#F7F5F2`. Dan chose the letterhead, so the kit is the
thing that is out of date; correcting that document is outside this repository. The kit's
typography stands, because the letterhead does not contradict it.

| | |
| --- | --- |
| Shape | Statement. What is owed and by when, answered at the top right at 25px before anything else. |
| The total | Said twice on purpose, once at 25px at the top and once at 10.5px closing the arithmetic. |
| A line | Description, Hours, Rate, Amount. The client sees the rate and can reconstruct every figure. |
| Identity | The real mark alone, 218px wide. No contact details beside it and no signature. |
| Contact | At the foot, beside the payment terms. |
| Tax | Drawn on every invoice. Reads `$0.00` and names the reason where the client is exempt. |
| Colour | One bar at the foot in `#7FA99E`. Nothing else on the document carries colour. |
| Type | Merriweather for the title and the amount, Lato for everything else, both embedded. |

**The decisions with code consequences are in the PRD as requirements 50 to 50f**, so the PRD
stays the single alignment document.

### Three things worth knowing before changing it

**The ordinary invoice is ONE line.** 16 of 19 real bookings are a single one hour shoot, so
its content stops around 550px down a 1056px page. Every shape was judged on that rather than
on a full one. A change judged on the busy fixture is judged on a case that does not occur.

**Two repetitions are deliberate and are not to be tidied away.** The total appears at both
ends, and on an ordinary invoice `$250.00` appears three times, as the rate, the amount and
the subtotal. Both were measured and put in front of Dan in those words before he chose them.
An invoice is not a screen: restating a figure across a calculation is how a reader checks it.

**A measured zero is drawn; an absence is not.** The exempt client's tax line reads `$0.00`
rather than disappearing, because an accounts department has to be able to tell a deliberate
exemption from an oversight. This is the second recorded exception to the zero rule the
Clients screen settled, after the comped invoice totalling `$0.00`. A first draft removed the
line by analogy with the sidebar counts, which was that rule applied outside the domain it was
written for.

### Two faults the measuring caught that looking would not have

A colour option built its class as `c-barRules` while the stylesheet asked for `c-barrules`,
and CSS class matching is case sensitive, so that option rendered identically to its neighbour
and would have read as a design finding rather than as a bug. And on the full stationery
option the small label on the mint band measured 3.40 to 1, under the 4.5 to 1 body text
needs. Neither was the option chosen, but both were live when Dan looked.

### What it does not yet answer

The wording `Sales tax (exempt)` is Claude's rather than Dan's, and along with the note to
customer and the payment line it still owes the cold read PRD 41a requires of every outbound
sentence. Nothing has been checked on a real printer. And `ovation#112` bears on the line
directly: Downbeat derives a booking's end time from its start, so on 16 of 19 real bookings
the duration that prices the invoice is a default rather than a measurement.

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

### Round 4, settled 2026-09-07: a quantity of nothing is not drawn, anywhere

Four treatments were rendered for keeping money held apart from referral credit, because PRD
5.14c says they must never read as one balance: drawn alike, credit nobody paid could settle an
invoice. Dan took the third, credit drawn only where there is any, **and extended it to money
held in the same breath**: "I basically don't need to ever see a $0 there."

**That is the same rule for the third time**, after the sidebar card in round 3 and credit in
this one, so it is promoted out of the Clients screen and written down once:

> **A quantity of nothing is not drawn.**

**It is a rule about ABSENCE and not about zero**, and that distinction is load bearing rather
than pedantic. Two places in the product would break under the blunt version, and both were
checked before the rule was written:

1. **A comped shoot invoiced at nothing totals $0.00 and that total is always drawn.** PRD 5.1b
   makes a zero invoice legitimate and says no guard may refuse one. It is a measured value that
   happens to be zero, not an absence.
2. **An absence meaning something is MISSING is still drawn.** A client with no tax status reads
   `Not recorded`, out loud, on 25 of the 31, because that is work waiting rather than nothing to
   do (PRD 5, 5a).

So the rule is: an absence meaning *nothing is waiting here* is not drawn. An absence meaning
*something should be here and is not* is drawn.

**The second half was Claude's inference and Dan confirmed it on 2026-09-07**, which is recorded
because it decides what 25 of the 31 clients look like. He said only that a quantity of nothing
is not drawn; the exception for a missing value was read out of PRD 5 and 5a and put to him
separately. Without it the roster gaps go invisible until ovation#40 gives them a surface.

**The screen was judged at ONE window width and that was not enough.** Narrowing it shows the
shoot names truncating at 1004px and the detail pane scrolling sideways at 874px, which is the
fault the invoice list record celebrates having removed. Filed as ovation#110.

Measured at the real count: 3 of the 31 hold money, 5 carry credit, 1 has both, and **24 of 31
show no money row at all**.

**The switcher is stripped from the committed file**, which the earlier rounds' versions were
not: what is left is the design, plus two things that are behaviour rather than choice. Clicking
a name changes the client, which is what the real screen does and is the only way to see the
rule at work. The day switch shows the quiet state, which is where the zero rule is visible.

### Round 5, settled 2026-09-07: the roster gets its own screen, and it is not there when it is empty

Four places were rendered for the roster clean up. Dan took the first, its own screen holding
everything that stops an invoice going out, **and added two rules with it**: only show that
screen when there are clients needing fixing, and put broken addresses above tax statuses because
a broken address matters more.

**The premise had to be corrected first, and it shrank the job to almost nothing.** The round was
built on ovation#40's framing, that an empty contract email is a gap. Dan: "not having a contract
email is the default. Most clients don't have this because the person that hired me is the person
I email the contract/invoices to." So a client has TWO addresses, the second is an override, and
its absence is ordinary. Then, reading the result: "I should be allowed to do two addresses in one
field. There's nothing stopping me from invoicing 2 emails at the same company at the same time
for the same event."

Re-measured against the real export under those corrections, counts only:

| | |
| --- | --- |
| Clients | 31 |
| With no address at all | 0 |
| With one address | 29 |
| With two addresses on purpose | 1 |
| Genuinely broken, being text rather than an address | **1** |
| Overrides that are an exact copy of the main address | 30 |
| Genuine overrides | 1 (invented for this fixture; the real count is 0) |
| Sharing one address | 2 |
| With no tax status | 25 |

So the pass is **one address and 25 tax statuses**, not the mixed pile of four or five problems
the issue described. Three of the four problem kinds turned out not to be problems.

**Ordered by cost, not by count.** One broken address sits above 25 missing statuses. Frequency
earns real estate on a list read daily; consequence earns it on a list cleared once.

**The zero rule now reaches a whole place in the app.** Once the roster is clear, `Settle the
roster` is gone from the sidebar rather than sitting there saying zero. Use the day switch to see
it. That is the same rule as every count in the card and as money held, stated for the fourth
time and now applying to navigation.

**A place you are standing in does not vanish underneath you** (Dan, 2026-09-07). The roster
screen leaves the sidebar once it is empty, but if you are ON it when you answer the last
question it stays, says `Nothing left to settle`, and goes only when you do. Answering the last
one is the moment you most deserve to be told you finished, and the worst possible moment for the
screen to disappear. This is a general rule rather than a Clients one, and it is the second time
the zero rule has needed an exception written beside it: the first was that an absence meaning
something is MISSING is still drawn.

**The committed file is the design, not the chooser.** What is left is behaviour: the sidebar
navigates between the two screens and clicking a name changes the client, both of which the real
window does.

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

## The invoice screen

`invoice.html` is the agreed design for the screen where an invoice is built, settled with Dan on
2026-09-07 over nine rounds, tracked as `ovation#111`. **Open it in any browser.** It needs nothing
external, and that is enforced rather than asserted: `scripts/check-design-self-contained.sh` refuses
a file that reaches out (ovation#114). Zero network requests, all four typefaces embedded.

The switch above the window is BEHAVIOUR rather than a chooser, the same as the quiet day switch on
the Clients screen: an invoice passes through all of these states and none of them can be seen from a
still. Set the two times, answer the tax status, press History in the header, and take a discount or
a referral credit from the Edit menu.

It shipped on 2026-09-08 as two files, `invoice-being-priced.html` and `invoice-after-sending.html`,
which was a decision made at midnight rather than a design decision: rounds 1 to 8 built the draft
being priced and round 9 built what it becomes after sending, and they always shared a shell, a
fixture and every rule. Merging them was measured rather than attempted blind, and it was safe: 216
of the roughly 240 selectors were already byte identical and only five differed, four of those being
a block declared twice over rather than a decision. What the merge deleted was the CSS of options the
rounds REJECTED, which nothing drew any more.

### What the nine rounds settled

| | |
| --- | --- |
| Shape | The invoice takes the whole content area. The list gives way and the title bar carries the way back. |
| Arriving | A push: the list stands aside to the left by 18% while the invoice comes in from the right, 280ms. |
| The hours | Derived from the shoot's real start and end times, which sit beside the shoot. Never typed directly. |
| Rounding | To the nearest quarter hour, with the one hour minimum, and always spelled out: `1h 32m, billed as 1.50 hours, rounded to the nearest quarter`. |
| Unpriced | `Needs hours` where the amount goes. Never `$0.00`, which is a legitimate comped invoice. |
| Refusals | One at a time, in order: the times first, then the tax status. The Send greys out with a tip naming what it waits on. |
| Tax | No figure and no total until the status is answered. Exempt draws the line at `0.00` and names the reason. |
| Discount | Reached from the Edit menu, never on the screen until there is one. Below the subtotal, dollars or percent. |
| Referral credit | Its own block above the subtotal, out of the line items. Contradicts PRD 5.8, deliberately (ovation#126). |
| After sending | The action for the state with the next most likely beside it, and the audit history in a pane that pushes the invoice across. |

### Three things worth knowing before changing it

**The time control is not the browser's.** It is segmented, hour, minute and meridiem, because the
macOS control is and because a single typed field has to resolve "7:30", which is ambiguous. In the
real app this is a SwiftUI `DatePicker` limited to `hourAndMinute` in its field style, both confirmed
present on macOS in the 26.5 SDK. What that LOOKS like has not been checked, only that it exists.

**Every rule behind this screen is executable, and the screen RUNS the rules rather than resembling
them.** `rules/` holds them as functions with their cases, run by `scripts/test-design-rules.sh` as
part of the ordinary suite: 150 cases across the duration, the time field and its typing, the tax
line, the money, and what the invoice is waiting on. They exist so whoever ports this to Swift has something to port AGAINST rather
than a description to interpret.

A design file must be one self contained document (ovation#114), so it cannot load `rules/` at render
time and carries its own copy instead. That is two copies of one rule with nothing comparing them,
and it had already gone wrong: `a12b32a` fixed a real NaN defect in `typeDigit` in
`rules/time-field.js`, added a case for it, and left the identical copy in the design file untouched.
The suite stayed green, because the suite reads `rules/`. The screen the design record IS still held
the defect and nothing could have said so. **`scripts/check-design-rules-inline.sh` now refuses a
design file whose copy of a rule has drifted**, comparing each rule as a contiguous run of lines
rather than as lines that merely all occur somewhere. The rules block in `invoice.html` was copied
from `rules/` by a script rather than typed, and nothing stops the next person editing one side
alone: what stops it SHIPPING is the guard, in the push gate. Change the rule in `rules/`, and copy
it back.

The page prints its own verdict line above the window, and it reports the same 150 across the same 6
suites that `scripts/test-design-rules.sh` reports. Two numbers that must agree, from two places,
which is the cheapest possible check that the copy is the copy.

**The 12 hour cap above which a duration prices nothing is Dan's**, settled 2026-09-08 against 8, 7
and no cap at all, with the measurement in front of him: his longest ever billed is 6.25 hours and
his median is 1.625. He took the loosest of the four that still refuses something, accepting that a
mistyped meridiem on an evening job comes to 10 hours and is priced rather than caught. It had been
Claude's until then.

**The history pane is 300px wide, and that is Dan's**, settled 2026-09-08 against 220, 272 and 330
with each option's consequence measured and drawn beside it. 300 is the first width at which every
entry settles to two lines, including the one carrying a client's real email address, which is the
longest thing the pane ever holds. Past it the invoice keeps giving up width and the entries stop
improving, so 330 was drawn and is dominated. It was 272 until that day, which was Claude's, and at
272 the sent entry still wrapped to three lines. The invoice works at 556px as well as at 856px, and
that is measured rather than assumed.

**Two things about the pane are still Claude's, not Dan's**, and are marked as such on ovation#111:
where the button sits, and what each entry says. Neither has been drawn against an alternative.

**That round could not be run on the first attempt**, which is worth recording because it is how the
worst defect of the day was found. Dan opened the four options and answered "I can't see the history
pane at all in the rendo": his browser window was narrower than the record needs, and rather than
scrolling, the page was deleting the right hand side of the app window and saying nothing. See below.

### Four things found by looking, every one of them invisible to the suite

**The history pane's own file said twice that it OVERLAYS the invoice**, once in the page's visible
copy and once in a code comment, when Dan had chosen the push ("it should push the invoice over, not
cover it") and the CSS implemented the push. Corrected. Measured after the width was settled: the
invoice goes from 856px to 556px and the browser reports the slide running 3ms to 278ms, the 280 it
is written to take.

**THE SCREEN WAS CUTTING ITS OWN RIGHT HAND SIDE OFF, SILENTLY.** Found by Dan, who could not see the
history pane in a round about the history pane. Measured at a 1100px browser window: the stage
squeezed the 1120px screen to 1002, the 1064px window inside it overflowed by 62px, `.screen`'s own
`overflow: hidden` cut those 62px off, and the page reported no horizontal scroll at all. The pane
sits exactly in that band. Even at 1440 the screen had been 1082 rather than its declared 1120, so it
had never once been drawn at its own size.

The cause was this merge: `invoice.html` inherited `display: flex` on its stage from the two round
files it was built from, where centring mattered because they were choosers rather than screens, and
a flex item shrinks. `invoice-list.html` and `clients.html` have a plain block stage and never had
this. The fix is their treatment, not a new one, and the near miss is the part worth keeping: the
obvious remedy is `overflow-x: auto` on the stage, and `invoice-list.html` carries a comment saying
that exact thing was tried and rejected, because setting overflow on one axis makes the other compute
to auto too and the stage starts clipping its own bottom while the page looks finished (L566). It was
very nearly shipped here before that comment was found (L542).

**The rounding sentence was never drawn as round 4 settled it.** The round's own record gives two
sentences, `1h 32m, billed as 1.50 hours, rounded to the nearest quarter` and, at the floor,
`billed as 1.00 hours, the one hour minimum`. Both files stopped at "billed as 1.50", so the reason
the figure had moved was on the page nowhere, and `durationBetween` had returned `atMinimum` since
the day it was written with nothing ever reading it. Both sentences are drawn now. Drawing the second
one immediately exposed a third fault: an elapsed time under an hour read as `0h 40m`, which neither
file could ever have shown, because both fixtures were an hour and a half.

**The payment in the audit history named a constant, `$408.28`,** which was true only while the total
could not change. It is the invoice's own total now, because a history contradicting the invoice it
belongs to is worse than one that says less.

### What is deliberately still open

What the sidebar counts do about an invoice that cannot be sent (ovation#129). The discount's edit
line, which was chosen to solve a layout problem rather than designed. And the history pane's own
width, button and wording.

**The hours are never typed, settled 2026-09-08.** The question had been whether they stay separately
typable for a shoot whose times were never noted, and Dan's answer removed it rather than choosing
between the four renderings: "I plan to create drafts with no end time (although I can put the start
time in from the creation). When I go to send the invoice I will always know the end time." He always
has both times at the moment it matters, so there is no case for a second way in, and a second way in
would be a second source of truth for one number.

**What his answer did produce is `rules/waiting.js`,** because the state he described is the ordinary
state of every draft and the screen was drawing it as the empty one. A draft carrying a start time
and no end time said `Needs the times`, with one of them plainly on screen, and its greyed Send read
`Waiting on the shoot's start and end times` while waiting on one. No fixture had ever reached it,
because every fixture had both times or neither (L101). The screen now asks the rule what it is
waiting on and gets a reason with the two sentences that carry it, so what is drawn beside the times
and what the Send says cannot disagree about one invoice.

That rule also closed the cap's surface question, which this section named as open a few hours
earlier. Both times present and 23 hours apart is not the same fact as no times at all, so it has its
own reason: the screen says `Longer than a shoot` where the figure would be, and the Send says
`That is more than 12 hours, so it prices nothing. Check the times.` PRD 5.3b asks for such a value
to be refused BY NAME, and that is the name.

The referral credit and the discount ARE drawn now, above and below the subtotal as PRD 5.4a and 5.8
settle them, using treatments the screen already had. Nobody has approved how they look: Dan chose on
2026-09-08 to leave them drawn and settle their treatment in the discount round rather than take them
back out, so read them as the starting point for that round and not as agreed.
