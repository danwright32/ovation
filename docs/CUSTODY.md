# Custody records

Files Ovation depends on that live OUTSIDE this repository, recorded here so their location
survives the folder being moved. Five projects were moved out of iCloud Drive on 2026-08-16 and
broke exactly this kind of home relative path, so the path below is a record to be checked, not
an assumption to be trusted.

Nothing here is the file itself. These files carry real client names and must never be committed.

## downbeat-export-2026-08-27.json

The live Downbeat export, captured before the version 3 build was installed.

| Field | Value |
| --- | --- |
| Path | `~/Library/Application Support/Ovation/custody/downbeat-export-2026-08-27.json` |
| SHA-256 | `26b32a64564be937fa510ceef993c1727b62e77877059f7e5028e7cace889276` |
| Captured | 2026-08-27 |
| Export version | 2 |
| exportedAt | 2026-08-23T19:18:44Z |
| Contents | 20 bookings (19 future), 31 clients, 5 venues |
| Future range | 2026-10-25 to 2027-06-13 |

**Why it exists.** Those 19 future bookings were committed under the pre version 3 Downbeat
binary. `BookingHandoffQueue.write` fires only at commit and there is no backfill, so no queue
file was ever written for any of them. `BookingRetention` deletes a booking row seven days after
its shoot, so without this snapshot the first became unrecoverable around 2026-11-01 and the rest
follow one at a time. This file is the only record that they existed.

**How it must be read.** Verify the SHA-256 above at read time, not only when it was written.
Absent, unreadable, or a hash mismatch is its own named outcome that BLOCKS the backfill and makes
the reconciliation report itself incomplete, naming how many ids it could not consult. It must
never quietly proceed with a smaller population, because the reconciliation would then find zero
differences, which is exactly what a healthy run reports (L98).

**It does not carry shoot times, but the v3 re-export will.** The export is version 2, so those 19
bookings have day strings but no `startsAt` or `endsAt`. An earlier version of this note said the
hours would have to come from Dan or from QuickBooks. **That was wrong, measured 2026-08-28:** all
20 stored Downbeat bookings hold a `startDate` with a real time of day (0 at local midnight), and
`OvertureExportBuilder.swift:103` maps that instant unrounded into `startsAt`. That prediction held: the
version 3 re-export carries usable times for every booking still in the store, and the second
snapshot below captured them on 2026-09-05. This file remains the only record of
WHICH bookings existed, including the one retention sweeps at that launch.

## downbeat-export-v3-2026-09-05.json

Snapshot 2, the record of the shoot TIMES. **Captured 2026-09-05.** No reinstall was needed: the
Downbeat installed on 2026-08-29 was already writing a version 3 export, and the Overture installed
on 2026-09-04 already carried the widened version gate, so the ordering hazard plan 0.2.0 exists to
prevent had already passed. See the correction at the end of this section.

| Field | Value |
| --- | --- |
| Path | `~/Library/Application Support/Ovation/custody/downbeat-export-v3-2026-09-05.json` |
| SHA-256 | `14a5b3ef98b69b2a6d7da387dd215415b7fcf844d2bbd4e7c144855947a719b6` |
| Captured | 2026-09-05 |
| Export version | 3 |
| exportedAt | 2026-08-29T15:07:27Z |
| Contents | 19 bookings, every one carrying `startsAt` and `endsAt`, 31 clients, 5 venues |
| Future range | 2026-10-25 to 2027-06-13 |
| Size | 20,220 bytes |

**Every assertion the plan wrote in advance was checked against this file after capture, and all
ten passed:** version 3; 19 bookings; 31 clients; 5 venues; every booking carrying both `startsAt`
and `endsAt`; earliest 2026-10-25; latest 2027-06-13; **zero bookings at local midnight in
America/New_York**, which is what makes the times real rather than date placeholders; and **zero
bookings whose `clientId` fails to resolve in this snapshot's own `clients[]`**.

**Why `exportedAt` is a week older than the capture date, and why that is correct.** Downbeat
rewrites this file on launch, and Downbeat was last launched on 2026-08-29 (its store and this
export both stop there), so nothing in it has changed since. The file is current with respect to
what Downbeat holds; it is not a stale read of a moving target. Snapshot 1 has the same shape:
captured 2026-08-27, exported 2026-08-23.

**The 20th booking is gone, exactly as predicted.** Snapshot 1 holds 20; this holds 19. Retention
swept the 2026-08-18 booking at a Downbeat launch, and that booking was also the one whose
`clientId` did not resolve. Snapshot 1 remains the only record that it existed, which is the reason
that file is kept rather than superseded.

**How it must be read.** Same as the file above: hash verified at every read, and absent,
unreadable or mismatched is a named outcome that blocks the backfill. Phase 6 prices from the
CURRENT export wherever a booking id is still present there, and from this snapshot only for ids
retention has since swept; it never prices from the version 2 file, which has no times.

> **CORRECTED 2026-09-05.** The section above previously said this snapshot would be taken "after
> Dan reports the version 3 Downbeat installed and launched", and the paragraph before it said "once
> Dan installs the version 3 Downbeat and launches it". Both were written on 2026-08-28 against
> installed builds that had already been replaced by the time anyone acted on them: Overture was
> reinstalled 2026-09-04 from `main` at `f78a3def`, which already contains the version gate fix
> `bdd85404`, and Downbeat was reinstalled 2026-08-29 at `1f5b470a` and was already emitting version
> 3. A recorded fact about something living OUTSIDE this repository is only true on the day it is
> written, and nothing here re-read it (L175). The wording is corrected in place rather than
> annotated on top, because a correction standing over a contradicting body is read as the body.

**How it must be read.** Same as the file above: hash verified at every read, and absent,
unreadable or mismatched is a named outcome that blocks the backfill. Phase 6 prices from the
CURRENT export wherever a booking id is still present there, and from this snapshot only for ids
retention has since swept; it never prices from the version 2 file, which has no times.

## handoff-record-sample-2026-09-06.json

The first real `BookingHandoffRecord` that has ever existed, written by the installed Downbeat
through its own commit path on 2026-09-06 while proving plan 0.2 step 4 (ovation#3).

| Field | Value |
| --- | --- |
| Path | `~/Library/Application Support/Ovation/custody/handoff-record-sample-2026-09-06.json` |
| SHA-256 | `b83af4f2b77f71145dd0b6ad9d770ebc1c8ea0c330832e3e0aab021141bd34ef` |
| Captured | 2026-09-06 |
| Record version | 3 |
| Size | 749 bytes |
| Contents | one booking, `venue` absent, client and shoot entirely fabricated |

**This one is unlike the two above: it holds no real client.** The booking was a throwaway committed
deliberately, with a fabricated client, a fabricated shoot and a one-off venue, so that the proof
would never touch a real customer. It is kept because it is the only measured example of the record
shape Ovation must consume, and recreating it costs another throwaway booking with an OmniFocus
project, a calendar event and a folder that only Dan can remove.

**One field still has to be scrubbed before it can enter this repository.** `client.hostingSite`
carries a real vendor name from Downbeat's Settings; everything else in the file is invented. The
repository is public, so that single value is the difference between a safe fixture and a leak.
ovation#29 is where the scrubbed copy lands, and this file stays here as the unscrubbed original so
the scrub can be checked against what was actually produced.

**What it settled.** `venue` is ABSENT on an ad hoc venue rather than present and empty, which is the
part of the contract a source reading is most likely to get wrong, and it confirmed the record
carries both the day strings and the instants. `scripts/check-booking-queue.sh` was written against
the source before any record existed and passed this one unchanged, which is the only evidence that
reading was right (L52).

**How it must be read.** Same as the two above: hash verified at every read, and absent, unreadable
or mismatched is its own named outcome. Unlike them, nothing depends on it at runtime; losing it
costs a throwaway booking, not a record of work that happened.

**A SCRUBBED COPY IS NOW IN THE REPOSITORY** at
`OvationTests/Fixtures/handoff-record-v3-2026-09-06.json`, as the consumer's fixture (ovation#29).
This file stays here as the unscrubbed original, so the scrub can be re-checked against what
Downbeat actually produced.

**Seven readable values were replaced, not one.** ovation#29 expected only `client.hostingSite` to
be real. The identity guard disagreed: `booking.clientDisplayName`, `booking.shootName`,
`booking.venueName` and `client.displayName` all matched Dan's LIVE Downbeat export, because the
client, shoot and venue fabricated for the throwaway booking became real rows in his data the
moment the booking was committed. A guard cannot tell a fabricated row from a customer, and the
repository is public. The two email addresses were replaced for the same reason without waiting to
be told. Every identifier, date, instant, boolean and the empty list are untouched, and the SHAPE
is identical: same paths, same types, `venue` still absent.

## Freshbooks Photography Invoices 2015-2024.csv

Dan's own invoicing history from before QuickBooks, and the only record on this machine of how
long his shoots actually run. Confirmed by Dan on 2026-09-07 as his file and usable.

| Field | Value |
| --- | --- |
| Path | `~/Non-icloudDocuments/Photography Assets/Documents/Freshbooks Photography Invoices 2015-2024.csv` |
| SHA-256 | `c39dd5d1fc96b48344219b88affe64b51f34da58ce3956e3dab548c0b7e88e65` |
| Exported | 2025-01-18 |
| Contents | 203 line items, 171 invoices, 41 clients, all USD |
| Issued range | 2019-01-06 to 2024-12-20 |

**Its filename says 2015 and its earliest issued date is 2019-01-06.** Recorded here because the
name is the first thing anybody will trust and it is wrong by four years.

**Why it is custody rather than a convenience.** PRD 5.3a and 5.3c both cite numbers derived from
it, and those numbers decided that a drafted invoice carries no duration at all. A requirement
resting on a measurement whose source nobody can find again is a requirement resting on somebody's
memory (L316). Recording it here also brings it under `check-custody-files.sh`, so the file moving
or changing is reported rather than discovered by a later reader getting different figures.

**How it must be read.** Verify the SHA-256 at read time, not only when it was written. **Exclude
draft invoices**: 41 of the 203 lines sit on invoices that were never issued, and a duration
nobody finalised is not evidence of what a shoot ran to. The figures in the PRD are for the 133
photography lines on ISSUED invoices priced at one of Dan's hourly rates.

**It carries real client names in its `Client Name` column and real event names in
`Item Name`, so it must never be committed**, and anything derived from it reports counts and
distributions rather than rows. **It is NOT yet a needle source for the identity
guard, and that is stated rather than implied**: `check-identity-leaks.sh` reads only `.json`
files under `~/Library/Application Support/Ovation/custody`, and this is a `.csv` somewhere else,
so its 41 clients are invisible to the guard while the live export's 31 are not. Making it one is
ovation#23, which exists for exactly this, and it is not free: the guard's own note warns that
needles derived from real business names WILL over match, and this file's `Item Name` column holds
event titles that are ordinary English words.

## What this folder is to Ovation

Decided 2026-08-28, recorded here so the app and its guards agree:

- It is inside the backup set (plan 1.8, PRD 29b). These files are the only record that 19 shoots
  existed and how long they ran.
- It is a needle source for the identity guard (plan 0.1), because it carries the same client and
  venue names as the live export.
- No test may create, modify or delete anything under it (plan 1.9), and its resolver returns nil
  under tests.
- Ovation itself never writes here. The agent writes at custody time; Phase 6 reads.
