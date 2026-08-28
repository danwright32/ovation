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

**It does not carry shoot times.** The export is version 2, so those 19 bookings have dates but no
`startsAt` or `endsAt`. Hours for them have to come from Dan or from the QuickBooks invoices he
already sent.
