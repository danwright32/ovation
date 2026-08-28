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
`OvertureExportBuilder.swift:103` maps that instant unrounded into `startsAt`. So once Dan installs
the version 3 Downbeat and launches it, the re-export carries usable times for every booking still
in the store, and the second snapshot below captures them. This file remains the only record of
WHICH bookings existed, including the one retention sweeps at that launch.

## downbeat-export-v3-<date>.json (to be captured)

Taken by the agent immediately after Dan reports the version 3 Downbeat installed and launched
(implementation plan 0.3, snapshot 2). Same folder as the file above. Fill this table in the same
change as the capture; a blank row here after the capture is a defect.

| Field | Value |
| --- | --- |
| Path | `~/Library/Application Support/Ovation/custody/downbeat-export-v3-<date>.json` |
| SHA-256 | not yet captured |
| Captured | not yet captured |
| Export version | expected 3 |
| Contents | expected 19 bookings, every one carrying `startsAt` and `endsAt`, 31 clients |
| Future range | expected 2026-10-25 to 2027-06-13 |

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
