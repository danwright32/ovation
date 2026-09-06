# Port discipline

Ovation ports at least eleven files one line at a time from Downbeat and Overture. This document
is the rule those ports follow, and `scripts/check-ported-artifacts.sh` is the part of it a machine
can enforce.

Implementation plan 0.4.6.

## Why this exists

**A clone copies the pattern AS FIRST WRITTEN, including every value already corrected in the
original, and the clone's own note that it follows a proven pattern is what makes it read as safe**
(L501).

The plan caught one instance of exactly that inside itself before any code was written: an earlier
draft ported Downbeat's identity guard as it stood before lesson L217 corrected it. Its needles came
from a shipped seed roster, the machine local list did not exist on this Mac, so it reported
`noList`, examined nothing, and a real venue name sat in four test files the whole time. Copying it
would have shipped that defect into Ovation wearing the authority of a proven pattern.

## The header

Every ported file carries, at the START of a comment line, in its own comment syntax
(`#` for shell, yaml and gitignore, `//` for Swift):

```
<comment opener><space>Ported<dash>From: <owner>/<repo> <path in that repo> @ <commit>
```

Written out, a shell one looks like `# Ported` then `-From:` then the three fields.

**The marker is escaped as `<dash>` throughout this document on purpose.** The checker has to name
its own needle in order to search for it, so any file that writes the marker in header position
becomes an artifact in its own scan (L245). Measured on the checker's first real run: seven bogus
artifacts, every one of them the checker itself or its test. The remedy is the RULE and not a list
of exempt filenames (L362): a real header sits at the start of its comment, prose about one is
indented inside a block, and the match is anchored to allow at most one space after the comment
opener. Anything that must show the marker at column zero escapes it, as this file does.

**No exceptions, and no "ported from Downbeat" without the commit.** A source path without a commit
records where a file came from and says nothing about WHICH VERSION, which is the only part that
decides whether the port is current.

## What the porting issue must carry

Every port gets an issue, and that issue carries three things before the port is written.

**1. Every constant, threshold, path and exemption entry in the source file, with the rule it has to
satisfy FOR OVATION.** Re-checked at the moment of the port rather than inherited. Rotation counts,
lock paths, cap sizes, sample thresholds and exemption lists are each a place where the original's
current version and the version being copied can differ. An inherited exemption entry carrying no
written reason, sitting beside neighbours that have one, is evidence nobody reasoned about it
(L233), and it must be justified for Ovation or dropped.

**2. A behavioural DIFF against the sibling's current main, not only a table of values** (L501).
The correction most likely to be missed is not a value at all. The worked example, and the reason
this clause exists:

`scripts/test-pre-push-hook.sh` in Downbeat carries a fix dated 2026-08-27 whose entire content is
one line of shell. Its `hook()` helper runs

```
env -u SKIP_TEST_RUN -u FORCE_TEST_RUN -u SKIP_STYLE_CHECK -u SKIP_TEST_CHECK -u SKIP_EXPORT_CONSUMER_CHECK
```

before invoking the hook. Without it, under `SKIP_TEST_RUN=1` the harness went from 36 passed and 0
failed to **15 passed with 21 failed**, because the documented one push escape hatch was silently
switching off twenty one of the checks policing the very gate it escapes, at the exact moment
somebody had already decided to push past a refusal (downbeat#433, L259). A constants table would
not have carried that line across.

**3. The sibling's open issues against that file, named.** `mac/build-install.sh` has one, filed by
ovation#3. Porting a file with a known open defect and not recording it means the defect arrives
silently and the issue that describes it is attached to a repository nobody will look at.

## The check

`scripts/check-ported-artifacts.sh` asserts that every recorded source commit is still an ancestor
of that sibling's current `main`, so a port made from a stale checkout or an unmerged branch is
REPORTED rather than assumed. `scripts/test-check-ported-artifacts.sh` is its suite.

Five outcomes, each with its own wording, because distinct causes need distinct messages (L11):

| Outcome | Exit | Meaning |
| --- | --- | --- |
| `OK` | 0 | the commit is an ancestor of that sibling's main |
| `NOT ON MAIN` | 1 | the sibling was found, the commit is not on its main |
| `COMMIT NOT FOUND` | 2 | the sibling was found, the commit is not in it at all |
| `CANNOT MEASURE` | 2 | the sibling repository is not on this machine |
| `NO PORTED ARTIFACTS` | 3 | nothing carried a header, so nothing was verified |
| `UNREADABLE HEADER` | 4 | a marker line that cannot be parsed |

**Two of those are the whole point, and both are the same mistake wearing different clothes.**

`CANNOT MEASURE` IS NOT A PASS. A checker that goes green because it could not find the repository
it was meant to check is indistinguishable from one that checked everything, and the green is then
read as confirmation (L98).

`NO PORTED ARTIFACTS` IS NOT A PASS EITHER. Ovation has zero ported files on the day this is
written, which is exactly the state in which a naive check exits 0. It would report success for
months, be trusted by the time the first port landed, and then keep reporting success if a header
were ever lost (L98, L182).

**It resolves a sibling by asking each candidate checkout what its origin actually is**, never by
directory name. Overture's checkout is not called `overture`, and a directory that merely shares a
name is not the same repository (L15).

**Seams, so the suite never reads a real sibling** (L2): `OVATION_PORT_SCAN_ROOT` and
`OVATION_SIBLING_SEARCH_ROOTS`. One test case proves the seam is honoured by pointing a header at a
repository that IS on this machine and asserting it comes back `CANNOT MEASURE` rather than being
resolved from the real estate (L322). The real default roots are exercised separately, because a
seam that hides the real path from every test leaves the real path untested (L246).

**Seen to fail, all ten cases, before it was trusted** (L1): a commit on an unmerged branch is
reported; an absent sibling says `CANNOT MEASURE` with an exit code distinct from the not on main
one; an unknown commit says so rather than reporting not on main; an empty tree refuses naming the
emptiness; a malformed header is refused rather than skipped; a Swift `//` header is found; and
indented prose describing the convention is not counted at all.

## The list of things this plan ports

Kept here so a port that never happened is visible, rather than being absent from a list nobody
maintains.

| Source | Repo | Ovation issue |
| --- | --- | --- |
| `.gitignore` | downbeat | ovation#4 |
| `Downbeat/setup-signing.sh` | downbeat | ovation#9 |
| `Downbeat/build-install.sh` | downbeat | ovation#10 |
| `scripts/install-git-hooks.sh` | downbeat | ovation#11 |
| `scripts/git-hooks/pre-push` | downbeat | ovation#11 |
| `scripts/run-tests.sh` lock handling | downbeat | ovation#12 |
| `mac/project.yml` | overture | ovation#8 |
| `mac/Overture/App/StoreLocation.swift` | overture | Year end tax export, 1.1 (ovation#51) |
| `Downbeat/App/AppStoreConfiguration.swift`, the launch scope predicate only | downbeat | Year end tax export, 1.1 (ovation#51) |
| `Downbeat/Persistence/StoreSchemaGuard.swift` | downbeat | Year end tax export, 1.2 (ovation#52) |
| `CooperativePoolTests` | downbeat | Ungrouped |
| `scripts/test-export-consumer-version.sh` | downbeat | Downbeat booking queue consumer |
| `scripts/measure-questionnaire-ocr.sh` | downbeat | Expenses and receipt intake |
| `scripts/verify-questionnaire-samples.sh` | downbeat | Expenses and receipt intake |
| seven Gmail and OAuth files, plus the Sent predicate | overture | Invoicing and sending, 5.0 |
