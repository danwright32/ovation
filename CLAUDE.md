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

## What to know before editing

- Needs xcodegen and flock (`brew install xcodegen flock`) and the Xcode named in `.xcode-version`,
  which `scripts/select-xcode.sh` selects.
- Do not call xcodebuild directly. Three macOS apps share this Mac and two xcodebuild suites
  running at once corrupt both runs, so `run-tests.sh` takes both siblings' locks, by the mechanism
  each one uses, in a fixed order. A raw xcodebuild takes neither.
- Every script under `scripts/` carries the decision behind it in its own header, usually with the
  measurement and the failure it was written against. Read that header before changing what the
  script does, because the reason is normally the part that decides the change.
