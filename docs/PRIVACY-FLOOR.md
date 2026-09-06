# Privacy floor

Ovation's subject matter is real people and real businesses: Dan's clients, the venues he
shoots in, the vendors he pays. **The repository is PUBLIC for the whole build**, on purpose,
because Actions is unlimited on a public repo while a private one gets 2,000 minutes a month
with macOS runners billing at ten times the rate. Making it private again is ovation#15.

So the privacy rules here are load bearing rather than formalities, and each one names the
thing that enforces it. A rule that lives only in prose is a hope (L27).

This replaces the `BEFORE-MAKING-THIS-REPO-PUBLIC.md` the plan originally called for. A
checklist to run before opening a repository that is already open enforces nothing; what is
needed is a rule that holds continuously. The pre private steps survive as the last section.

## The three halves

Privacy fails in three different places, and until 2026-09-06 only two of them had anything
watching.

### 1. What is COMMITTED

Real receipts, QuickBooks exports and custody snapshots must never enter git history.

Enforced by `.gitignore` plus `scripts/check-custody-not-staged.sh`, which runs in the pre push
hook. It asks whether custody data has ever entered history, not merely whether it is staged
now, because an ignore entry added after a file was committed hides it from `git status` while
leaving it in every clone.

### 2. What SITS IN A FILE

No real client, venue or vendor name may appear anywhere in the tree, including in files
`.gitignore` excludes.

Enforced by `scripts/check-identity-leaks.sh`, in the pre push hook. Its needles are DERIVED
from the populations that exist at this phase rather than read from a hand kept list, and an
empty derivation is a refusal, because a guard with nothing to look for examines everything and
finds nothing, which is indistinguishable from a clean tree (L98, L217).

It walks the directory rather than `git ls-files`, since the highest risk content on this disk
is exactly what `.gitignore` excludes (L250).

### 3. What is PRINTED

**This is the half that had no enforcement at all, and it is the one that actually bit.**

Every measurement script, probe and report returns counts, ids, booleans, paths and field
names. **None has a mode that prints a display name, a subject line, an email address or a
message body.** The shape is absent, not discouraged. Anything that has to be read by eye, Dan
reads on his own screen.

A file scanner cannot see what a tool prints. Printed output reaches agent transcripts,
terminal scrollback and the end of turn review by a route no `.gitignore` and no identity guard
inspects, and from there it goes wherever somebody pastes it (L222).

Enforced by `scripts/test-output-privacy.sh`, which seeds a throwaway export carrying
fabricated names in every field the guard derives identities from, points each check script at
that fixture through the script's own seams, and asserts none of those names appears in what
the script prints. It drives each script into the branch that actually SPEAKS, because a script
that printed nothing would pass while proving nothing (L98).

Its needles come from the identity guard's own derivation, imported rather than rewritten, so
teaching the guard a new field extends the output test on its own (L70). Its list of covered
scripts is asserted against what is on disk, so a new `check-*.sh` fails that suite until
somebody points it at the fixture (L96).

## Why the third half is written down at all

On 2026-09-06, during this project's own work, a full screen capture put roughly twenty real
client names and their email addresses into a transcript in a single action. Every file scanner
in this repository was green throughout, correctly, because nothing had been written to a file.

The lesson is not that screenshots are bad. It is that the two guards which existed both
answered a question about FILES, and everybody involved read their green as meaning the
privacy floor held.

**What the enforcement still does not cover**, stated rather than left to be assumed from the
suite's name (L400):

1. **Screenshots and screen captures.** Nothing can inspect an image. The rule is that a
   capture of an app showing real data does not get taken; where one is unavoidable, it is
   cropped to the control in question rather than the window.
2. **Anything a person pastes** into an issue, a commit message or a chat.
3. **Scripts outside the `check-*` family.** `build-install.sh` and `setup-signing.sh` read no
   name bearing data today. If one ever does, it joins the covered list, and the completeness
   assertion will not notice on its own because it only watches `check-*.sh`.

## Writing about real data

Issues, plans and commit messages describe measurements without naming their subjects. Say
"nineteen future bookings", "a six character single word client name", "a real venue name in
four test files". Redact at the point the evidence is RECORDED rather than trusting whoever
implements it later to anonymise it, because an issue written with real evidence becomes the
source the implementer copies into fixtures (L155).

Test fixtures use invented names that are obviously invented.

Dan can waive this for a specific value, and has done so once.

## Before the repository is made private

Kept here so the steps are not lost, and closed by ovation#15.

1. Confirm the build no longer needs unlimited Actions minutes, which is what public buys.
2. Re-run `scripts/check-custody-not-staged.sh` over the whole history, not just the tip.
3. Re-run `scripts/check-identity-leaks.sh` with the needle set derived from every population
   that exists by then, not only the ones that existed at Phase 0.
4. Going private does not undo disclosure. Anything already pushed to a public repo is assumed
   to have been fetched, so a name found at that point is a rotation and a notification
   question, never merely a deletion.
