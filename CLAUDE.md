# Ovation

A native macOS SwiftUI app for invoicing, for Dan Wright Photography. The full product spec is
`PRD.md`.

## Where things are

- `Ovation/` is the app. `OvationTests/` and `OvationHostedTests/` are its two test targets.
- `project.yml` is the source of truth for the Xcode project, which xcodegen generates from it.
  Edit the yml and regenerate; an edit to `Ovation.xcodeproj` is overwritten by the next run.
- `scripts/` holds every build, test and check entry point, one file each.
- `docs/` holds the project record and `integration/` the integration fixtures.

## Build and test

One command, and it is the same one CI runs:

    bash scripts/build-products.sh && bash scripts/run-tests.sh

`build-products.sh` builds Debug and Release, because the shipping build's bundle assertions are
the ones that caught a real security defect and they must run somewhere other than one Mac.
`run-tests.sh` runs everything.

To re-verify a branch just before merging it, run it as
`OVATION_TEST_LOCK_PRIORITY=merge bash scripts/run-tests.sh`, which queues it ahead of routine runs
for the lock the three apps share (ovation#598). Nothing sets that for you, because nothing local
runs before `gh pr merge` here.

## Merging from a worktree

Remove the worktree before merging, then merge (ovation#396). `gh pr merge
--delete-branch` cannot delete a branch a worktree has checked out, and then
leaves the remote branch as well. If a branch survives anyway, delete it on GitHub
with `gh api -X DELETE repos/danwright32/ovation/git/refs/heads/<branch>`.
`bash scripts/report-branches.sh` lists every branch beside its pull request's
state and deletes nothing, because this repository squash merges and no local git
question can tell a shipped branch from an unshipped one.

## After a merge

Run `bash scripts/check-installed-build.sh`. It compares the Ovation installed in
/Applications with main and says how far behind it is (ovation#389). When it says
BEHIND, tell Dan the installed app is missing that work and that
`bash scripts/build-install.sh` reinstalls it; installing is his to run. Exit 2
means there is no install record, which is its own answer, not a current install.

Then run `bash scripts/check-scheduled-runs.sh`, which asks GitHub whether each
scheduled workflow is still running (ovation#387). It is asked here as well as in
CI because GitHub switching schedules off for inactivity switches off whatever in
CI would notice. STOPPED names the workflow and, where GitHub disabled it, the
command that re-enables it.

## Scoring a screen against its settled design

A screen settled with the design rounds skill is done when the build matches its settled
design at 100% on both halves (ovation#760; the skill's "Scoring the build against the settled
design" is the full reference). One command draws both sides and scores them:

    bash scripts/design-score.sh <screen> [--design <settled file>] [--pr <number>]

It exits with the score's own code: 0 matched, 1 not matched yet, 2 no score. With `--pr` it
posts the score on that pull request, which every pull request in a design milestone does. Its
header says what it runs in what order and why each stop is a 2.

- Each screen needs its settled file (`docs/design/<screen>.html` by default), its round's
  materials in `OvationHostedTests/DesignScore/<Screen>/` (the spec, builder, fixture and chrome
  picture, kept out of the test bundle by `project.yml`), and a hosted suite named
  `<Screen>DesignScoreTests` that draws each frame through `DesignScoreSpec`. The proof screen,
  `ProofDesignScoreTests`, is the worked example.
- `vendor/design-score/DesignScoreCapture.swift` is claude-config's file verbatim,
  and the runner refuses while it differs, naming the `cp` that refreshes it.
- The design side needs the shared Playwright, once per Mac:
  `bash ~/.claude/skills/design-rounds/score/install-playwright.sh`.
- Text does not match across engines: one line drawn by Chrome and by SwiftUI matched 96.9%
  (measured 2026-10-20), so the first real screen scored will meet that.
- A Match issue filed by hand carries the design score issue mark naming the design file; its
  form is at the top of `~/.claude/skills/design-rounds/score/score_github.py`.

## What to know before editing

- Needs xcodegen and flock (`brew install xcodegen flock`) and the Xcode named in `.xcode-version`,
  which `scripts/select-xcode.sh` selects.
- Do not call xcodebuild directly. Three macOS apps share this Mac and two xcodebuild suites
  running at once corrupt both runs, so `run-tests.sh` takes both siblings' locks, by the mechanism
  each one uses, in a fixed order. A raw xcodebuild takes neither.
- Every script under `scripts/` carries the decision behind it in its own header, usually with the
  measurement and the failure it was written against. Read that header before changing what the
  script does, because the reason is normally the part that decides the change.
