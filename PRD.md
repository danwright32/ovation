# Ovation

Status: Draft for review by Dan Wright
Date: 2026-08-27
Author: Dan Wright

Every decision below was made by Dan during an interview on 2026-08-25 to 2026-08-27. Anything not settled there is marked as proposed or listed as an open question with an owner.

---

## 1. Problem

Dan runs a one person photography business, shooting roughly 30 to 40 performances a year. The money side of that business runs on a paid subscription product whose features he almost entirely does not use, and the work of getting paid is spread across three systems that do not know about each other.

Observable symptoms:

1. Dan pays a monthly QuickBooks subscription and uses a small fraction of what it does.
2. Every shoot is entered twice by hand. Once in Downbeat, which knows the client, the venue, the dates and the times, and again in QuickBooks, which knows none of that and has to be told.
3. Getting paid is tracked as a sequence of manual reminders in OmniFocus rather than as a state anything can report on. There are separate tasks to create an estimate, convert it to an invoice, send it, check it was paid, and mark it paid.
4. Receipts are captured on a phone at the point of purchase and have no route into any system until Dan moves them by hand.
5. At tax time Dan answers an accountant's questions by assembling the answers himself.

In Dan's framing (2026-08-25): "It's largely just that I'm paying for it and I don't have to be. I don't use most of the features." And on what he wants instead: "I just want something that does exactly what I need. No more or less."

---

## 2. What this product is

Ovation is a native macOS application that holds the money side of Dan Wright Photography: what was billed, what was paid, what was spent, and the records behind all three. It has two halves.

1. **Invoicing and payment.** A booking committed in Downbeat becomes a priced draft invoice in Ovation with no typing. Dan reviews it, sends it as a PDF through Gmail, and records payments against it until it is settled.
2. **Expenses and the tax record.** Receipts arrive by email, are read on the Mac, and are filed against categories that map to the tax lines an accountant works in. At year end Ovation exports what the accountant needs.

What already exists: Downbeat, which records every booking and already publishes a versioned JSON file that Overture reads. Overture, which already holds a proven Gmail connection built on PKCE OAuth. QuickBooks, which holds 2026 to date and is being replaced.

What Ovation adds: the pricing, the invoice document, the payment record, the expense record, and the export.

---

## 3. Who it is for

1. **Dan, the design center.** Sole user. Every decision optimises for his daily use, subject to the two floors below.
2. **Dan's accountant.** Never opens the app. Receives two CSV files and must be able to answer their own questions from them. This is a floor, not a preference: an export the accountant cannot work with is a failure regardless of how good the app feels.
3. **An accounts payable clerk at a client organisation.** Never opens the app. Receives a PDF and must be able to pay from it without emailing Dan first. Also a floor.

Not for: anyone else. There are no other users, no roles and no sharing. Ovation runs on Daniels MacBook Pro 2 and nowhere else, because Downbeat's handoff is a file on that disk.

---

## 4. What success must look like

**Primary measure.** One full tax year is completed in Ovation with no fallback to QuickBooks. Concretely: tax year 2026 is filed from Ovation's export, and QuickBooks is cancelled.

**Baseline.** The QuickBooks subscription cost is TBD, see 9.1. The count of 2026 records to migrate is TBD, see 9.2. Both come from Dan; nothing here invents them.

**Ranked seconds:**

1. No shoot goes unbilled. Ovation can state a checkable fact: bookings received, invoices created, and any difference between them named.
2. Every expense Ovation holds has a receipt or is explicitly marked as having none.
3. The accountant asks no question the two CSV files cannot answer.

**Directional, not pass or fail:** time spent at tax time, and how quickly invoices are paid.

**A measure deliberately not claimed.** Ovation cannot promise every expense was captured. Dan declined statement reconciliation, so nothing independent exists to compare against. Ovation will not be able to distinguish a month in which Dan spent nothing from a month in which he stopped filing, and it will not assert that it can.

---

## 5. What Ovation must do

### Invoices

1. Every committed Downbeat booking becomes a draft invoice, and Ovation can report bookings received against invoices created, naming any difference.
2. An invoice can also be created from scratch, with no booking behind it, for work not booked through Downbeat.
3. Pricing is $250 per hour, computed from the booking's real start and end times, exact to one decimal, with a one hour minimum. One Downbeat booking is one show, so one invoice carries one photography line plus whatever extras Dan adds. A run of three nights arrives as three bookings and becomes three invoices.
4. Line items pick from a fixed list of service types. A new type can be added from inside an invoice without going to settings first. Proposed starting list: Photography (hourly), Rush turnaround, Preview images, Referral credit (negative).
5. Sales tax of 8.875% applies to the whole subtotal, is skipped for clients recorded as exempt, and is applied with a visible warning where the client's status was never recorded. A missing status is not the same as "not exempt", and Ovation says so on the draft.
6. Invoice numbers come from one continuous sequence starting at 1123. A cancelled invoice keeps its number.
7. The invoice is dated its booking's shoot date and is due 14 days later. Overridable per client and per invoice. Ovation warns at send time when the due date is already close or past.
8. A referral credit appears as its own line. One hour is earned per hour of the referred client's first booking, once only, credited when that first invoice is marked paid. Ovation keeps the balance per client and warns when a booking is flagged as spending credit the client does not have.
9. The PDF carries Dan Wright Photography's identity, the client name alone in the Bill to block, the line items, tax, total, the payment instructions and the note to customer, all from settings.
10. Sending goes through Gmail from a review screen showing the exact PDF and the exact recipients, prefilled from the client's contract email with a CC available. Ovation records what it sent, to whom, and when.
10a. Dan cannot mark an invoice Sent by hand. Sent is only ever observed, by one of two routes: Ovation sent it, or Ovation found a message carrying that invoice number in the Gmail Sent folder and derived it. The second route exists because Ovation already reads that mailbox, and because a flag written only by actions inside the product is permanently wrong for work done in the mail client instead (L162, and the same defect already shipped in Overture as `replyHandledAt`). An invoice sent from Spark stops claiming to be a draft; the invoice records which route established it.
11. A sent invoice can be edited and resent. Ovation keeps the history of what changed and the PDF of every version sent.
12. An overdue invoice can produce a drafted reminder that Dan reviews before it goes. Nothing is ever sent to a client without Dan seeing it.
13. Cancelling an invoice that carries payments asks what happened to the money and records a refund with its own date. Under the accrual basis confirmed in 24, cancelling matters more than it did: the invoice itself was income in the year it was issued, so cancelling one issued in a PRIOR tax year removes income from a return already filed. Ovation must refuse to silently cancel such an invoice, and instead say which filed year it belongs to, so Dan can raise it with his accountant rather than discovering the discrepancy later.

### Payments

14. An invoice holds any number of payments, each with a date, an amount and a method. Paid in full is calculated, never typed.
15. Methods are Check, Zelle, Venmo and PayPal. A payment by check gains a Cleared step; other methods do not.

### Expenses

16. Receipts arrive through a Gmail folder. An email with attachments files those; an email with none has its body rendered and captured as the receipt. Several real attachments become several unfiled receipts.
16a. Signature images and tracking pixels are ignored. Because that is a filter matching on shape, it must be tested against the receipts it has to PRESERVE and not only the junk it has to catch (L104): a small receipt image looks very like a logo, and an over matching filter reads exactly like the feature working.
17. Ovation saves the expense record before it touches the email, then moves the logged message to a Logged subfolder. Nothing is deleted.
18. Amount, vendor and date are read on the Mac, and a field is filled only where the reading is unambiguous. Where it is doubtful the field is left empty with the competing readings shown. Nothing is ever guessed.

18a. **Corrected 2026-08-27. There is only one reader, and the ambiguity signal comes from inside it.** This requirement previously specified two independent readers that had to agree. That is not achievable: verified against the macOS 26.5 SDK, the on device Foundation Models framework takes no image input. It can only re-read text that Vision has already extracted, so its agreement corroborates nothing about a number Vision misread, and treating it as a second opinion would manufacture false confidence in exactly the field that matters most. Instead Vision's own alternative candidate readings and its per observation confidence are the independent signal: where a close second candidate exists, for instance $88.20 against $38.20, the field is left empty and both candidates are shown. The behaviour Dan approved is unchanged; what produces it is now something that exists. A language model may still be used to LABEL text (deciding which line is the vendor), never to confirm a digit.

18b. **Ambiguity is expected, so it is counted rather than only handled.** Ovation keeps a running record of how often a field is left empty for doubt, per field, and Dan can see it. Leaving a field empty is correct, but it is also the path a systemic failure takes: a reader quietly degrading looks exactly like ordinary noise, one receipt at a time, and stays invisible for as long as it lasts (L77). Downbeat keeps a questionnaire agreement log for this reason and it is what turned a suspected data problem into a located parser fault. The log records counts and field names only, never the contents of a receipt.

18c. **The reader's identity is recorded with every measurement.** Vision is supplied by the operating system and changes under a system update with no build and no code change, so a number that decides whether the expense half is viable must be pinned to the request revision and OS version it was measured on (L25). Otherwise an update can lower the accuracy silently, in the reassuring direction: more fields are left empty, which reads as caution rather than as regression.

18d. **This is measured before the rest of the expense half is built.** The reader is run over a set of Dan's real receipts, photographed and digital, and the rate at which each field is filled confidently is recorded. Its accuracy on receipts is not known today, and the precedent cited for the original design was measured on typed questionnaires, not on a till receipt photographed at an angle. If fields are rarely filled, filing an expense is typing, which is the single thing most likely to make Dan stop using this half of the product. That has to be known in the first week rather than in January. The pass marks are agreed with Dan and written down BEFORE the measurement runs, so a disappointing number cannot be rationalised afterwards.
19. Every expense carries a category from Dan's own list, and every category maps to a Schedule C line. Proposed starting list, to be corrected: Gear to Supplies or Assets, Software to Office expense, Travel to Travel, Insurance to Insurance, Contract labour to Contract labor, Professional fees to Legal and professional, Marketing to Advertising, Meals to Meals.
19a. The completeness of that map is enforced by a test, not by a default branch, so a category added without a mapping fails loudly rather than landing somewhere plausible in the export (L113).
20. A single purchase above a configurable threshold is flagged as a likely asset rather than an expense, visibly and overridably. The threshold is a suggestion, not a determination.
21. An expense with no receipt is allowed and marked as such, and the mark reaches the CSV.
22. A likely duplicate, same vendor and amount and date, is flagged rather than blocked or merged.

### Export

23. A year end export produces income.csv and expenses.csv for any date range, defaulting to the calendar year.
24. **Income is on an accrual basis: one row per invoice issued, dated by the invoice date, whether or not it has been paid.** Dan confirmed this on 2026-08-27, having first answered the opposite before the term was explained, and reaffirmed it after being told plainly that it is a fact about his filed returns rather than a preference. Three consequences follow and each is a change from what this document said earlier. An unpaid invoice IS income for the year it was issued, so the export cannot exclude it. An invoice issued in December and paid the following January belongs entirely to the December year. And payment dates, while still recorded and still exported, no longer decide which tax year anything falls in.
24a. Because unpaid invoices are income, the export carries the payment state on every row, so an invoice that was billed and never collected can be identified. Writing one off as a bad debt is a decision for Dan and his accountant, not something Ovation does, but the export must make such an invoice findable rather than silently indistinguishable from a paid one.
25. income.csv carries sales tax as its own column so it can be totalled by period for the accountant's sales tax filings.
26. Any single receipt can be exported on its own in one action.

### Migration and data

27. QuickBooks CSV exports import into Ovation. The import reports rows read, rows written, rows refused with the reason for each, and the totals, so they can be checked against QuickBooks before the import counts as done. A row it cannot parse is named and refused, never skipped quietly.
28. Imported 2026 expenses carry no receipt image and are marked as such.
29. Ovation writes dated, self contained backups to a folder Dan chooses, keeps a rolling set, verifies each is readable after writing, and offers Restore in the app. A backup that cannot be read back is reported as a failure, never as silence.
29a. A rolling set is a capped store, so a cheap writer evicts real records. The test suite must be structurally unable to write to the real backup folder, the real receipts folder or the real handoff queue (L2, L191). Downbeat lost a measurement this exact way: 198 of the 200 lines in its agreement log were test writes.
30. Ovation deletes nothing automatically, ever.
31. Every business date is computed in America/New_York through one shared helper, never the host clock's default (L39). Downbeat already pins that zone for the dates it exports. This decides which tax year a 31 December payment falls in, so it is tested at the month, year and midnight boundaries with a pinned clock.

### How it behaves

32. Ovation checks both queues on launch and every few minutes while running, and shows a menu bar item with what is waiting. Nothing runs while the app is closed, so every time based state, overdue included, is only as current as the last launch (L51). Ovation says when it last looked rather than implying it is always watching.
33. Every time taking action, the import, the receipt reading, the send, shows working, still alive, and failed as visibly different states. No bare indefinite spinner.
34. A malformed handoff file, or one from a Downbeat version Ovation does not understand, is refused loudly and named. It is never read as an empty file.
35. **Finding nothing is its own outcome, never success** (L98, L100). A handoff queue directory that does not exist is different from one that is empty. A Gmail receipts folder that is missing, renamed, or has "show in IMAP" switched off returns zero messages, which is otherwise indistinguishable from a week in which Dan filed nothing. Each of those is reported as what it is, and Ovation refuses to conclude anything from a zero it did not earn.
36. **The handoff queue has a redo path** (L512). Ovation keeps its own durable record of every booking identifier it has consumed, independent of the queue files it deletes, so a booking whose invoice is later lost can be recovered after Downbeat's copy has been swept.
37. A second running copy of Ovation refuses and names the copy it stood aside for, as Downbeat already does.
38. Where a client has no usable contract email, Ovation refuses to send and names the client and the field. It never falls back to the other address.
39. Search across invoices, clients and expenses, with filters on the invoice list.
40. Deleting anything gets a confirmation or an undo.
41. Accessibility is built into each control, not added afterwards.
42. Ovation checks that its own stored totals agree with the parts they are made of, rather than trusting a number because it was written. The referral balance in particular has one declared home, the client who earned it, written by exactly one place from both the earning and the spending side (L83).

---

## 6. How it works

**One list, sorted by what needs Dan.** Invoices live in a single searchable, filterable list. The order, top to bottom:

1. Draft, shoot is today. Send it today.
2. Overdue. Chase it.
3. Draft, shoot has passed. Should have been sent.
4. Paid by check, not yet cleared. Confirm it cleared.
5. Sent, awaiting payment. Waiting on them.
6. Draft, shoot still ahead. Nothing to do yet.
7. Paid or cleared.
8. Cancelled.

Oldest first within each group. Today's shoots outrank overdue invoices because sending today's invoice is a thing done once and now, while chasing can happen any time this week. This ordering replaces the estimate trick Dan used in QuickBooks to keep far off work out of his view.

**What one booking is.** Downbeat's booking flow books a whole run in one pass, but it saves one `Booking` row per show, each holding a single date, a single time range and a single venue (`ShowCommitPlan` in `BookingDraftBatch.swift`, committed one plan at a time by `BatchCommitOrchestrator`). So "a booking" throughout this document means one performance, and a three night run reaches Ovation as three of them.

**The booking handoff.** Downbeat writes one small file per committed booking into a queue. Ovation reads it, creates the invoice, saves it, and only then removes the queue file. The order matters: saving first means a crash loses nothing, while acknowledging first would lose the invoice. Downbeat's seven day sweep is untouched, so timing stops mattering entirely. A re run is marked as such and creates nothing new, only a note on the invoice that already exists.

**Cancellations.** Downbeat has no concept of a cancelled booking and cannot tell Ovation about one, so cancelling is done in Ovation. Because Ovation cannot distinguish a cancelled shoot from an invoice Dan forgot, it surfaces drafts whose shoot has passed without being sent, and never guesses which they are.

**Receipts.** Dan photographs a receipt at the register and shares it to mail, or forwards a digital receipt, into a folder in Spark. That folder is a Gmail label underneath. Ovation collects them into an unfiled queue, reads what it can, and Dan completes them at the Mac.

**Client identity.** Ovation matches a booking to a client on Downbeat's stable client identifier. An unknown identifier matching exactly one existing contract email links automatically. A single name only match asks once. No match at all creates a new client.

More than one match is its own refusal, never treated as no match (L521). Two clients sharing a name, or two sharing a contract email, stop the match and say so rather than falling through to the create-new path, because that path manufactures a duplicate identity which every later invoice, payment and referral credit then feeds. A roster sync failed exactly this way in project-enrollment-tracker: it refused two names on one row and never refused one name on two rows, which its own matcher had just detected.

Where Downbeat later sends a client detail that differs from Ovation's copy, Ovation shows both and asks, once per differing value, never repeatedly for the same one.

---

## 7. Non goals

1. **Accepting payment in the app.** Dan is paid by check, Zelle, Venmo and PayPal and records payments himself. Building acceptance would add fees, compliance and a payment provider to solve a problem he does not have.
2. **Recurring expenses, mileage tracking, part business splits and foreign currency.** All four considered and declined. Dan does not drive to shoots, keeps business and personal separate, and does not buy in other currencies.
3. **Linking expenses to a shoot or client, and billing expenses back.** Declined. The cost is that per job profitability is not answerable and reimbursable costs must be typed onto an invoice as ordinary lines.
4. **Reconciling against a bank or card statement.** Declined. See section 4.
5. **Tracking contractor payments for 1099 reporting.** Payments to people file as ordinary expenses under a contract labour category. The obligation remains Dan's.
6. **Sales tax filing support.** The accountant files the periodic returns from the same records.
7. **A second Mac, and any phone version.** Filing a receipt from elsewhere works by emailing it.
8. **Combining several bookings onto one invoice.** One booking, one invoice, always. This is decided knowing what it costs: Downbeat saves one booking per show, so a client who books a three night run receives three invoices, with three numbers and three due dates, for what they think of as one job. Dan chose this over grouping runs (2026-08-27), and the alternative remains available later, see 10.6.
9. **Anything about delivering photographs.** Galleries, exports and delivery stay in Downbeat and OmniFocus.

---

## 8. What Downbeat provides

This section described work Downbeat had to do before Ovation could be built. **All of it shipped on 2026-08-27**, as issues 426 to 431 in `danwright32/downbeat` and 3193 in `danwright32/overture`. What follows is the contract Ovation is now built against, not a request. The authoritative version lives in the Downbeat repository at `Downbeat/Downbeat/Integration/OvertureExport/CONTRACT.md`, nested two levels deep rather than at the repository root, which carries a table naming every consumer of these surfaces.

1. **The handoff queue.** Directory `~/Library/Application Support/Ovation/booking-queue/`, one file per booking named `<BOOKING-UUID>.json`, written atomically at commit. A Debug launch writes to `booking-queue.debug` instead, and a test process writes nothing at all.
2. **Each record is self contained.** It carries the booking, the client and the venue as they were at the moment of commit, rather than pointing at the export file. This is deliberate: the export is current state, so a client edited or removed after the commit would change what an unconsumed record resolves to. The frozen values are what makes requirement 6's "show both and ask" possible, since Ovation can compare what was true at booking against what Downbeat says now.
3. **The record carries the shoot's real start and end instants**, so Ovation can price the invoice, and `isRerunOf`, so a re-run adds a note to the invoice that already exists rather than drafting a second one.
4. **The file is named for the booking id**, which makes the write idempotent: a commit retry lands on the same path and replaces it rather than queueing the shoot twice.
5. **Downbeat reports its own failures.** A booking it cannot queue raises a problem naming that shoot, and it deliberately never retracts, because a later booking queueing cleanly says nothing about the one that did not. So Ovation is not the only thing standing between a commit and a missing invoice.
6. **A re-run replaces the predecessor's row rather than deleting it** (downbeat#429, Dan's decision 2026-08-27). Before that fix, re-running an upcoming shoot removed its days from the export and Overture's scout stopped suppressing nights already booked. It also meant a second re-run of the same booking answered "Booking not found". Both are fixed, and it is why `isRerunOf` now reaches a saved row at all.
7. **The export version gate.** Overture now accepts any version at or above a minimum rather than an exact set (overture#3193). Ovation must do the same. Refusing a payload whole because its version is unfamiliar produces empty data that is indistinguishable from the data genuinely being gone (L255).

---

## 9. Open questions and risks

1. **The QuickBooks subscription cost is unrecorded.** Owner: Dan. Without it the primary measure has no baseline.
2. **The volume of 2026 records is unknown.** Owner: Dan. It decides how the importer is built and how long migration takes.
3. **The accrual basis is confirmed by Dan, not by his accountant, and that is worth one more check.** Settled 2026-08-27, see requirement 24. Recorded here rather than closed because of how it was arrived at: Dan first answered the opposite, changed to accrual once the question was put concretely, and reaffirmed after being told it is a fact about his filed returns rather than a preference. He is entitled to that call and the export is built on it. The two minute confirmation, if he ever wants it, is line F of any past Schedule C, which asks for the accounting method and has a box ticked for Cash or Accrual. If that box says Cash, requirement 24 and everything keyed to it are wrong.
4. **The asset threshold is proposed, not confirmed.** Owner: Dan, with his accountant. $2,500 is the IRS de minimis safe harbour, but it is an election made on the return and Section 179 may make it moot. Note also that the threshold is per item while Ovation sees a receipt total, so it is right on single item purchases and wrong on bulk ones.
5. **Whether sales tax applies to rush and preview charges is unconfirmed.** Owner: Dan, with his accountant. Ovation currently taxes the whole subtotal, matching invoice 1057.
6. **The QuickBooks export format is unverified.** Owner: Dan. A sample of the real CSVs is needed before the importer is built.
7. **The two lists in 5.4 and 5.19 are drafts.** Owner: Dan. Correct them here.
8. **The reader is unmeasured on receipts, and the design it replaced was impossible.** Owner: Dan. See 5.18a: the original two reader agreement design could never have worked, because the on device language model takes no image input, and that was discovered by the planning panel rather than by anyone building it. Measure the corrected single reader design against real receipts, with the pass marks agreed and written down first, before the extraction is trusted.
9. **Whether Spark displays Ovation's sent invoices correctly is unverified.** Owner: Dan. Sending through Gmail should place a copy in the Sent folder, but this has not been observed.
10. **Risk: no deadline and no dry run.** Dan chose no delivery date and chose to prove the app by using it rather than by comparing a full year export against QuickBooks. Together these mean the export is first exercised for real in January, with the accountant waiting, and the subscription keeps renewing meanwhile.
11. **Risk: Downbeat's task templates now contradict reality.** Dan chose to leave them alone for now. Until revisited, every shoot seeds OmniFocus tasks instructing him to create an estimate in a QuickBooks he has cancelled.
12. **Risk: 14 days is a change to how clients are treated.** Current invoices give 30. At 14, clients who have always paid at 30 will show as overdue on day 15 without having changed anything.
13. **Risk: Ovation will be able to modify the mailbox.** Filing receipts needs permission to read and change mail, not only to send. That is wider than invoicing alone requires, and it is the price of automatic receipt intake.
14. **An invoice sent outside Ovation is recovered by reading Gmail, and that match is unproven.** Dan cannot assert Sent by hand, so the derived route in 5.10a is the only thing standing between a Spark send and an invoice stuck as a draft for ever. It matches on the invoice number appearing in a sent message, which has not been tested against a real mailbox. Owner: Dan. If the match proves unreliable, the choice in 5.10a has to be revisited rather than quietly leaving the gap L162 describes.
15. **The invoice PDF design is open.** Dan is not satisfied with the current QuickBooks format. The content is settled; the design is separate work.
16. **The payment block on the PDF is currently truncated** mid word by QuickBooks. Dan chose to keep the "available upon request" wording and fix the truncation rather than print his payment handles.

---

## 10. Later versions

Directional, not committed.

1. **A phone version.** Dan expects to want one. The chosen architecture makes it an iPhone app sharing data through iCloud rather than a rewrite. Reopens after the first filing.
2. **Statement reconciliation.** The only mechanism that could make expense capture provably complete. The reason to revisit it is a year end where the expense total looks wrong and nothing can say why.
3. **Retiring Downbeat's QuickBooks era tasks.** Pending Dan, see 9.11.
4. **Sales tax period reporting.** Worth revisiting if the accountant starts asking for quarterly totals.
5. **Line item extraction from receipts.** If the readers prove good enough, splitting a multi item purchase would make the asset threshold accurate on bulk buys, which it currently is not.
6. **Grouping a run onto one invoice.** Declined in section 7 item 8. The reason to revisit it is a client asking why they received three invoices for one engagement. It would need Downbeat to tag the bookings from a single pass with a shared run identifier, since consecutive dates alone are not proof they were one job.

---

## 11. Sign off

1. Sections 5, 6 and 7 need Dan's confirmation. Every decision in them is his, recorded from the interview, but recorded by me.
2. Items 9.3, 9.4 and 9.5 need Dan's accountant. 9.3 blocks relying on the first export.
3. Item 9.7 needs Dan to correct the two draft lists in this document.
4. Section 8 needs nothing. The Downbeat and Overture work it once asked for shipped on 2026-08-27, so the second success measure is no longer blocked by another repository.

---

## 12. Lessons audit

This document was checked against `~/.claude/LESSONS.md` on 2026-08-27, before any code was written.

One decision was reversed by it. Dan's original choice that only Ovation could set Sent is the shape L162 describes, and the same defect had already shipped in Overture (`replyHandledAt`, overture#2865), with the same mail client. Requirement 5.10a is the revised version: Sent is still never asserted by hand, but it is derived from the Gmail Sent folder as well as from Ovation's own sends.

Nine requirements exist only because a lesson demanded them, and they are marked in place: 5.16a (L104), 5.19a (L113), 5.29a (L2, L191), 5.31 (L39), 6.32 (L51), 6.35 (L98, L100), 6.36 (L512), 6.42 (L83), and the many-match refusal in the client identity part of section 6 (L521).

Already satisfied by decisions Dan made during the interview, with no change needed: L5 and L12 (the handoff saves the invoice before acknowledging the queue file), L7 (backups and a restore path from day one), L15 (matching keys on Downbeat's stable identifier), L47 (the import records its refused rows rather than skipping them), L74 (due dates anchor to the stored invoice date rather than being recomputed from today), and L1 with L48 (the receipt readers are measured against real receipts before being trusted, see 9.8).
