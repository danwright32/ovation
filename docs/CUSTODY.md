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

## What this folder is to Ovation

Decided 2026-08-28, recorded here so the app and its guards agree:

- It is inside the backup set (plan 1.8, PRD 29b). These files are the only record that 19 shoots
  existed and how long they ran.
- It is a needle source for the identity guard (plan 0.1), because it carries the same client and
  venue names as the live export.
- No test may create, modify or delete anything under it (plan 1.9), and its resolver returns nil
  under tests.
- Ovation itself never writes here. The agent writes at custody time; Phase 6 reads.
