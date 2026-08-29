# Ovation implementation plan

> **REVISED 2026-08-28.** The 2026-08-27 header correction about the accrual basis has been folded
> into the body: Phase 2, 1.5 and the guards table now describe an ACCRUAL export (PRD 24), one row
> per issued invoice dated by invoice date, and no longer say "cash basis" anywhere. A header
> correction standing over a body that contradicts it is read as the body by whoever builds from
> it, so the body was rewritten rather than annotated.
>
> Also on 2026-08-28: Phase 0.3 was corrected against `docs/CUSTODY.md` (a v2 snapshot already
> existed at a different path), probes 1 to 3 were dropped because PRD 42a and 42b already measured
> their answers, probe 5 was aligned with PRD 17a (the Logged move is required, not a fallback),
> the 4.2 attachment key was aligned with PRD 22a, and the PRD requirements that had no home in
> this plan (3a, 3b, 5.10b, 5.13, 18c, 22b, 29b, 38, 38a, 41a, 41b) were given one. Phases 0.2.0a,
> 0.2.0 and 0.2 are Dan's own steps now (his instruction, 2026-08-28); the agent measures before
> and after and never runs the installs.
>
> This plan was written against PRD 5.18, which specified two independent on-device receipt
> readers that had to agree. That design was impossible (the on-device language model takes no
> image input) and PRD 5.18a now replaces it with a single reader whose own alternative candidates
> provide the ambiguity signal. Phase 4.0 follows 18a for photographed receipts (Dan's decision, 2026-08-28), and logs
> arithmetic self-consistency beside every fill so a confident misread is countable.


## What decides this plan

Ovation is a seven year tax record, not a feature set. Its primary success measure (PRD 4) is a single event in January that cannot be retried, with no dry run (9.10). So the build spends its earliest work on the substrate that cannot be retrofitted, then runs Dan's settled build order (5b) on top of it unchanged.

Everything asserted below was measured on this Mac on 2026-08-27. Where a claim is unverified it says so. Repository paths are written relative to each repository's own root: Downbeat's root is `/Users/danielhankins-wright/Non-icloudDocuments/Apps/Downbeat`, and its app sources sit one level further down at `Downbeat/`, so the app file paths read `Downbeat/App/...` from that root. Overture's root is `/Users/danielhankins-wright/Photography Assets/.../Overture` with its app under `mac/`.

### Verified before writing this

**Every row below is a measurement dated 2026-08-27 or 2026-08-28, not a current fact.** Two rows had already gone stale within a day (Overture's branch state, and the custody folder). The step that depends on a row re-measures it before acting and never reads this table as current (L175, L244).

| Claim | How it was checked | Result |
| --- | --- | --- |
| **All 20 stored Downbeat bookings carry a real time of day** (2026-08-28) | read `ZBOOKING.ZSHOOTDATA` from a read-only open of Downbeat's store, decoded `startDate`, counted | **0 at local midnight, 20 with a time**, 0 undecodable. `OvertureExportBuilder.swift:103` maps `shoot.startDate` straight into `startsAt`, so the **v3 re-export WILL carry usable shoot times for the 19 old bookings**. `CUSTODY.md`'s earlier sentence that hours would have to come from Dan or QuickBooks was true only of the v2 file |
| **A v2 custody snapshot already exists** (2026-08-28) | `ls ~/Library/Application Support/Ovation/custody/` | `downbeat-export-2026-08-27.json` plus its `.sha256`, captured 2026-08-27 21:26, recorded in `docs/CUSTODY.md`. The `Apps/Ovation-custody` folder an earlier draft of 0.3 named **does not exist** |
| Installed Downbeat predates the handoff work | `strings /Applications/Downbeat.app/Contents/MacOS/Downbeat` | 0 hits `booking-queue`, 0 `startsAt`, 0 `endsAt`, **4 `blockedDates`** (control literal, so the zeroes are real absence, L70). **`isRerunOf` also shows 4 and is NOT usable evidence**: it predates v3 as a model property |
| **Installed Overture lacks the version gate fix** | `installed-build.json` commit `2ddd4bc6`, dated 2026-08-24; `git merge-base --is-ancestor bdd85404 2ddd4bc6` | **exit 1, NOT an ancestor.** `bdd85404` "Accept future downbeat-export versions instead of an exact set (#3197)", 2026-08-27, is on Overture's main and is **not in the installed app** |
| **Overture's checkout is NOT on main and its state moves** | `git rev-parse --abbrev-ref HEAD`, `git status --porcelain`, `git diff --name-only main..HEAD` | branch `one-shot-deep-link-channels-1927`, **HEAD commit `45ec26a4` is not on main**, 5 files differ from main (`mac/Overture.xcodeproj/project.pbxproj`, `mac/Overture/App/RootView.swift`, `mac/Overture/UI/QueueView.swift`, `mac/OvertureTests/LeadDeepLinkTests.swift`, `mac/OvertureTests/OneShotChannelGuardTests.swift`). The tree was **dirty earlier today and is clean now**, because that work was committed onto the branch in between. **This state is not knowable in advance and must be measured, never assumed** |
| **Overture's installed-build.json cannot vouch for a clean tree** | `mac/build-install.sh:118-140` | writes exactly `{version, commit, commitDate, repoPath, provenance}`. **No `dirtyFiles`, no `signingIdentity`.** A build installed from a dirty tree is recorded under a commit whose content it does not match |
| **Downbeat records what Overture does not** | `Downbeat/build-install.sh:71,85,92-101` | writes `{version, commit, commitDate, repoPath, signingIdentity?, dirtyFiles?}`, both optional and both explicitly meaning NOT RECORDED when absent. **No `provenance`.** Its comment cites downbeat#424: "On 2026-08-23 the sidebar fix was built and installed while still uncommitted: the record said 4a1cde0 while the bundle was 4a1cde0 plus changes". **Neither sibling writes the whole set** |
| The existing guard cannot see the deployed pair | `scripts/test-export-consumer-version.sh` (Downbeat root) | it resolves `<repo>/mac/Overture/Domain/DownbeatExport.swift`, a **source checkout**. It passes green while the deployed pair is broken (L3, L4). It already has the correct three-outcome shape and says CANNOT MEASURE when Overture is not on the machine |
| **A Debug Downbeat does NOT use an in-memory store** | `Downbeat/DownbeatApp.swift:39-44`; `grep -rn isDebugBuild --include=*.swift` | `isStoredInMemoryOnly: true` is gated on `AppStoreConfiguration.isRunningUnderTests()`, **never on `isDebugBuild`**. `isDebugBuild` appears in exactly two production places, both in `Downbeat/App/AppStoreConfiguration.swift`: `overtureExportURL` (line 85) and `bookingHandoffQueueURL` (line 121). **Debug isolates two file paths and nothing else** |
| **Downbeat's own comment asserts an isolation that does not exist** | `Downbeat/App/AppStoreConfiguration.swift`, doc comment on `bookingHandoffQueueURL` | "Under a Debug build: a sibling directory. `Downbeat/Downbeat` is launched from Xcode with a throwaway in-memory store, so anything it commits is fictional." **That sentence is false.** A Debug Run opens the real store and runs the real side effects |
| Queue directory | `ls ~/Library/Application Support/Ovation/` | `booking-queue/` does not exist. The `Ovation/` folder itself now exists because it holds `custody/` (2026-08-28), so a check for the queue must test the `booking-queue` path, never its parent |
| Live export | `~/Library/Application Support/Overture/downbeat-export.json` | `version 2`, `exportedAt 2026-08-23T19:18:44Z`, 20 bookings, **19 in the future**, 31 clients, earliest future 2026-10-25, latest 2027-06-13, **no `startsAt` on any booking** |
| **Tax status is absent on every booked client** | parsed the live export | 31 clients, **6 carry `isTaxExempt`** (5 true), so **25 do not**. The 20 bookings resolve to **3 distinct clientIds**; **2 of those have rows in `clients[]` and NEITHER carries `isTaxExempt`** |
| **One booking's clientId does not resolve** | same parse | **1 of 20** (`FF803523-...`, shoot 2026-08-18) carries a `clientId` with no matching row in `clients[]` |
| That booking is also the one retention removes | `BookingRetention.retentionDays = 7`, `BookingSweep.run` from `LaunchMigrations.swift:2987` | 2026-08-18 is 9 days past, so the post-relaunch v3 export holds **19**, not 20 |
| **`contractEmail` is a non-optional `String`** | `mac/Overture/Domain/DownbeatExport.swift:12` | `var contractEmail: String`. The 1 of 31 clients with none carries an **empty string**, not an absent key, so 5.38's refusal must test empty-after-trimming, never nil |
| Repo visibility | `gh repo view danwright32/ovation --json visibility` | **PUBLIC** |
| Ovation repo contents | `ls -la`, `cat .gitignore` | `PRD.md` (28,661 bytes), `icon/`, `.gitignore` (10 bytes, `.DS_Store` only), a stray `.DS_Store`. Nothing else |
| **Ovation has no git hooks** | `ls .git/hooks/` | samples only. The style and test gates do **not** apply to this repo yet |
| Queue is durable | `Downbeat/Integration/OvertureExport/CONTRACT.md` | "Downbeat never deletes from this directory, so an undrained record stays until its consumer removes it" |
| Commit side effects | `CommitOrchestrator.swift:14-27, 902-925` | `Phase` = `.folder`, `.omniFocus`, `.fantastical`, `.save`, plus `rosterUpdatePhase`, `deletePredecessorPhase` and `bookingHandoffPhase` |
| `@Attribute(.unique)` in Downbeat | `grep -rn "@Attribute" Downbeat/Domain/` | 9 uses, **every one on surrogate `id: UUID`**; `Downbeat/Domain/DuplicateNameCheck.swift:5` opens "Only `id` is unique on these models" |
| `externalStorage` in Downbeat | `grep -rn` | **0 hits anywhere** |
| Store path incidents | `mac/Overture/App/StoreLocation.swift` | two dated losses at `Application Support/default.store`: Downbeat 2026-07-08, `/usr/libexec/icloudmailagent` 2026-07-23 |
| **Downbeat's own store still uses SwiftData's default filename** | `Downbeat/App/AppStoreConfiguration.swift:44-46` | `Application Support/Downbeat/default.store`: a dedicated subfolder, but the **default filename**. Overture uses `Overture.store` |
| `StoreSchemaGuard` exists **twice** | `find` | `Downbeat/Persistence/StoreSchemaGuard.swift` and `mac/Overture/App/StoreSchemaGuard.swift`. Downbeat's verdicts are `noStoreFile`, `empty`, **`downbeat`** (not `ours`), `foreign(entityTables:)` |
| Gmail scopes in the estate | `mac/Overture/Integration/GoogleOAuth.swift:15-23` | `gmail.send`, `gmail.readonly`, `gmail.settings.basic`. **`gmail.modify` appears nowhere** |
| **Overture stores Gmail tokens in a file, not the Keychain** | `GmailCredentials.swift:1-8`, `ls -la` | 0600 `gmail-tokens.json` (verified `-rw-------`), "because the app is ad-hoc signed during development" |
| **The Gmail and OAuth code has no test refusal** | `grep -rln "isRunningUnderTests\|XCTestConfiguration"` over all 14 `Gmail*.swift` plus `GoogleOAuth.swift` plus `ReplyDetection.swift` | **0 of 15 files.** The full set is **2230 lines**; the seven files Ovation actually needs are **1114 lines** (see 5.0 for the names) |
| **The corrected Sent predicate already exists** | `mac/Overture/Domain/ReplyDetection.swift:114, 133-136` | `labelIds(of:)` returns **nil when the field is absent**, and `wasSentByUser` = `labels.contains("SENT") && !labels.contains("DRAFT")`, failing closed. Its comment: "A message wrongly accepted clears a row that is genuinely waiting on him, permanently and silently" (overture#2918) |
| FoundationModels image input | macOS 26.5 SDK, **`arm64e-apple-macos.swiftinterface`, 75,929 bytes** (the Mac Catalyst slice is 75,890; the plan quotes the slice Ovation builds against) | `Transcript.Segment` = `.text` \| `.structure` only; **0 hits** for `CGImage`/`NSImage`/`CVPixelBuffer` |
| Vision has a **second** document API | macOS 26.5 SDK `Vision.swiftinterface` | `topCandidates(_:)` at 1380; **`RecognizeDocumentsRequest` at 2219** with `textRecognitionOptions` (2260) and `barcodeDetectionOptions` (2261); `DocumentObservation` at 2454 exposing tables, rows, columns and cells |
| The two siblings disagree on test locking | `scripts/run-tests.sh:50` (Downbeat root), `mac/scripts/run-tests-locked.sh:22` | Downbeat: `LOCK_DIR="${TEST_LOCK_DIR:-/tmp/xcodebuild-tests.lock}"`, and its header claims the lock "is shared with Overture deliberately". Overture locks `/tmp/overture-mac-tests.lock`; `xcodebuild-tests.lock` returns **0 hits** anywhere in the Overture tree. **The sharing is not true today**, and Downbeat's lock path is overridable by `TEST_LOCK_DIR` |
| A running Debug app kills a test run | `mac/scripts/run-tests-locked.sh:91-95`, `:333-340` | a Debug app holding the single-instance lock (`LSMultipleInstancesProhibited`) makes the xctest host fail to launch; :333-340 records that a hardcoded hint naming that cause "sent hours of elimination in the wrong direction" |
| **The two siblings implement 5.37 differently** | `grep -rn LSMultipleInstancesProhibited` | the key appears **only** in `mac/Overture/Info.plist:21`. **Downbeat has 0 hits** and implements the refusal in application code: `Downbeat/App/RootView.swift:23-24`, `if case .secondCopy(let other) = secondInstance { SecondInstanceRefusalView(other: other) }`, downbeat#292 |
| **Overture's repo holds nested full checkouts** | `ls .claude/worktrees/` | agent worktrees `agent-*`, each a complete copy of the Overture sources. Any `git ls-files` guard or default test glob collects them (L234) |
| Scaffolding the siblings actually use | `ls`, `which xcodegen` | Overture: `mac/project.yml` + XcodeGen (`/opt/homebrew/bin/xcodegen`), `mac/build-install.sh`. Downbeat: checked-in `Downbeat.xcodeproj`, `Downbeat/setup-signing.sh`, `Downbeat/build-install.sh`, `scripts/install-git-hooks.sh` + `scripts/git-hooks/pre-push`, `scripts/measure-questionnaire-ocr.sh`, `scripts/verify-questionnaire-samples.sh`, `scripts/refresh-reserved-names.sh` |
| Downbeat is blocked on Ovation | `Downbeat/CLAUDE.md:178-180` | "#432: a crash between saving a booking and writing its queue file loses the handoff with nothing able to detect it, since Ovation deletes a file as it drains it, so absent means both consumed and never written (L258). **Needs Ovation PRD 36's consumed-id record first**" |

---

## Phase 0, day zero, before a line of Ovation code

Five actions, in this order. Order matters: **0.2.0 exists because the first draft of this plan would have broken Overture on its first command, and 0.2.0a exists because the second draft would have failed on its first line with a git error and no remedy.**

**Who does what (Dan, 2026-08-28: "don't worry about updating the apps. I'll do that").** 0.2.0a, 0.2.0 and 0.2 are Dan's steps. The agent does not run `build-install.sh` in either sibling, does not check out branches in Overture, and does not launch either app. What the agent still does: measure the installed state before Dan starts (so the starting point is recorded), hand him the numbered steps below with one command per block, and run the verdict checks after he says he is done. The one ordering rule that protects his data is unchanged and is the whole reason 0.2.0 sits before 0.2: **Overture is reinstalled from `main` first, and Downbeat only after the 0.2.0 verdict passes**, or Overture refuses the v3 export whole and loses its 31-client roster.

### 0.1 Make the repo private, write a real `.gitignore`, and set the privacy floor

Do this **first**, before anything reads a real receipt, a real mailbox, or the live export.

1. `gh repo edit danwright32/ovation --visibility private --accept-visibility-change-consequences`
2. Verify: `gh repo view danwright32/ovation --json visibility` must print `PRIVATE`. A command that ran is not a setting that changed.
3. Replace `.gitignore` (currently 10 bytes, `.DS_Store` alone) with Downbeat's, plus Ovation's own custody exclusions, each carrying a written reason (L155, and L233: an entry with no reason beside neighbours that have one is evidence nobody reasoned about it):
   - `build/`, `DerivedData/`, `xcuserdata/`, `.build/`, `.swiftpm/`, the standard Xcode set
   - `.receipt-samples`, the machine-local path to Dan's real receipts for the 18b measurement
   - `.quickbooks-samples`, the real QuickBooks CSV exports, which carry client names and amounts
4. **The identity guard's needles are derived, never typed, and the guard refuses when it has nothing to look for (L217, L214, L98, L41).** The earlier draft ported Downbeat's guard as it stood before L217 corrected it: its needles came from a shipped seed roster, the machine-local list did not exist on this Mac, so it reported `noList`, examined nothing, and a real venue sat in four test files the whole time. The draft before this one closed the **missing** case and left the **present but empty** case open, which is the same trap wearing different clothes: Ovation's own store holds no clients until Phase 3 or 6 and no vendors ever (vendor names come off receipts, not out of the store), and the handoff queue holds nothing until a real booking is committed. Through Phases 0b, 3 and 4, exactly when real receipts and real QuickBooks CSVs are on this disk, a store-derived needle set is near empty and the guard would report clean while examining almost nothing. So:
   - **The needle set is derived from every population that actually exists at that phase**, not from Ovation's store alone: (a) client display names, contract emails and venue names in Ovation's own store, (b) the Downbeat handoff records on this disk, (c) **the live `downbeat-export.json` client roster**, which is populated from day one and carries all 31 clients, and (d) vendor names Ovation has written from receipts. The issue states, per phase, which population supplies the needles, so nobody has to infer coverage from a passing run.
   - **An empty needle set is a refusal, naming the emptiness**, exactly as a missing or unreadable source is. "No list, said so" must never be able to become "a list, and everything is clean".
   - **It scans by directory walk, not `git ls-files`.** The highest-risk content on this disk is precisely what step 3 just gitignored, and overture#3161 records the shape: a `.gitignore` entry that meant "per machine" was read by a guard as "do not look" (L250, L234). The walk skips `.git/` and any nested checkout under `.claude/worktrees/`, by name, because Overture's repo proves those exist in this estate and a recursive walk otherwise scans a second full copy of everything.
   - **A separate check asserts no file under `.receipt-samples` or `.quickbooks-samples` has ever been staged**, using `git log --all --diff-filter=A -- <path>` plus the current index, because the walk's job is finding names and this one's job is finding that custody leaked into history.
   - The guard prints **counts and file paths only, never a name**.
   - **Seen to fail (L1):** plant a reserved name inside a file under `.receipt-samples` and watch the guard go red. Plant one in a tracked file and watch it go red. Point it at an unreadable store and watch it refuse. Point it at a store and export that between them yield zero needles and watch it refuse **naming the emptiness**, not report clean.
5. **Privacy floor for every script and probe in this plan (L222).** All the privacy work above points at files. None of it can see what a tool **prints**. Reading the live export, the handoff queue, or a mailbox puts real client, venue and vendor names into agent transcripts, terminal scrollback and the end of turn issue review, by a route no file scanner inspects. So: **every measurement script in this plan returns counts, ids, booleans and field names. None has a mode that prints a display name, a subject line, an email address or a message body.** The shape is absent, not discouraged. Anything that must be read by eye, Dan reads on his own screen.
6. Write `docs/BEFORE-MAKING-THIS-REPO-PUBLIC.md`, ported from Downbeat under the 0.4.6 port discipline.

### 0.2.0a Report Overture's checkout state and route it, before touching it

**This step exists because the previous draft's first command was `git checkout main && git pull && ./build-install.sh`, and that chain aborts on step one whenever Overture's tree is dirty.** It was dirty earlier today, with three modified tracked files that differ between the branch and main; it is clean now because that work was committed onto `one-shot-deep-link-channels-1927`. Neither state is knowable in advance. `git checkout main` refuses with "Your local changes to the following files would be overwritten by checkout", `&&` stops there, `build-install.sh` never runs, and Dan, who does not write code, is handed a git error on the first action of the plan with no numbered remedy.

So the agent **measures first and reports**, and Dan chooses.

1. Run this and read the output. It changes nothing:

```
cd "$HOME/Non-icloudDocuments/Photography Assets/Dan Wright Photography/Marketing/Outreach/Overture" && printf 'branch: %s\nhead:   %s\non main: %s\n' "$(git rev-parse --abbrev-ref HEAD)" "$(git rev-parse --short HEAD)" "$(git merge-base --is-ancestor HEAD main && echo yes || echo no)" && printf 'uncommitted files: %s\n' "$(git status --porcelain | wc -l | tr -d ' ')" && git status --porcelain
```

2. The agent routes on that output, and only one of these happens:
   - **Already on `main`, zero uncommitted files:** go straight to 0.2.0.
   - **On another branch, zero uncommitted files** (today's state): `git checkout main` is safe and loses nothing, because the branch's commits stay on the branch. The agent tells Dan, by name, which branch it is stepping off and that his work on it is untouched, then proceeds.
   - **Any uncommitted files:** **stop and ask Dan**, with an AskUserQuestion picker carrying the three real options and what each costs: commit them on the current branch, stash them (`git stash push -u`, and the agent restores the stash after the install), or build Overture from a separate clean clone and leave this checkout alone. **The agent never picks for him and never runs `git checkout -f`, `git stash` or `git clean` on its own initiative.** These are Dan's working files in a repository the plan is forbidden to disturb (hard constraint 4).
3. Whichever route ran, the agent prints the branch and uncommitted count again after it, so the state it acted on is recorded rather than assumed.

### 0.2.0 Reinstall Overture from main, and prove the INSTALLED BUNDLE, BEFORE any Downbeat install

**This step exists because without it, step one of this plan destroys a working app.** The installed Overture is commit `2ddd4bc6` (2026-08-24). The fix that widens its version gate to a minimum, `bdd85404` (2026-08-27), is on Overture's main and is **not** in that build. CONTRACT.md: Overture "decodes the WHOLE file or none of it, so a change it refuses costs it the client roster too, not just the part that changed." Installing a v3 Downbeat first would make Overture's scout stop suppressing nights Dan is already shooting and lose its 31-client roster, on the first action of the plan, against hard constraint 4.

> **CORRECTED 2026-08-27** after the lessons audit and reality check. The commands below replace an
> earlier pair that were wrong in three ways, each of which would have let the plan destroy Overture
> on its first action while reporting success. (a) The verdict ended `|| echo "STOP..."`, so it exited
> zero on both outcomes and could only be judged by reading a line of its output, which is exactly
> L184; any `&&` chain, `set -e` or agent treating it as a command would have read STOP as success.
> (b) It asserted a clean tree AFTER the install, but `mac/build-install.sh` runs `xcodegen generate`
> and rewrites the tracked `project.pbxproj`, so a perfectly good install dirties the tree and fails
> its own check. The tree that matters is the one the bundle was built FROM. (c) It compared
> `provenance` against `main` with `[ "$P" = "main" ]`, but `build-provenance.sh` prints one of `main`,
> `branch` or `unknown`, and its own header states `unknown` is a real answer covering a checkout with
> no origin or an unreachable remote. So a network outage read as a wrong build and got the same
> sentence, which is L11 and L119 in one line.

1. Capture the tree state **before** installing, because that is the tree the bundle is built from, then install:

```
cd "$HOME/Non-icloudDocuments/Photography Assets/Dan Wright Photography/Marketing/Outreach/Overture" && git checkout main && git pull && git status --porcelain > /tmp/overture-pre-install-tree.txt && test ! -s /tmp/overture-pre-install-tree.txt && ./mac/build-install.sh
```

If that stops before installing, the tree was dirty beforehand. Read `/tmp/overture-pre-install-tree.txt`, resolve it through 0.2.0a, and start this step again.

2. Judge the **installed bundle**, with three outcomes and three exit codes, so nothing downstream can read a refusal as a pass:

```
cd "$HOME/Non-icloudDocuments/Photography Assets/Dan Wright Photography/Marketing/Outreach/Overture" && python3 - <<'PY'
import json, os, subprocess, sys
GATE_FIX = "bdd85404"
rec = os.path.expanduser("~/Library/Application Support/Overture/installed-build.json")
def cannot(reason):
    print("CANNOT MEASURE: " + reason, file=sys.stderr); sys.exit(2)
try:
    d = json.load(open(rec))
except FileNotFoundError:
    cannot("no installed-build.json, so nothing records what is installed")
except Exception as e:
    cannot("installed-build.json is unreadable: %s" % e)
commit = d.get("commit")
if not commit: cannot("installed-build.json records no commit")
prov = d.get("provenance", "ABSENT")
pre = open("/tmp/overture-pre-install-tree.txt").read() if os.path.exists("/tmp/overture-pre-install-tree.txt") else None
if pre is None: cannot("no pre-install tree record from step 1, so tree cleanliness is unknown")
if prov == "ABSENT": cannot("installed-build.json records no provenance, which means NOT RECORDED, never main")
if prov == "unknown": cannot("provenance is 'unknown', a real answer meaning the remote could not be reached; retry when online")
if subprocess.run(["git","merge-base","--is-ancestor",GATE_FIX,commit]).returncode != 0:
    print("STOP: DO NOT INSTALL DOWNBEAT V3. Installed commit %s does not contain the version gate fix %s." % (commit[:8], GATE_FIX), file=sys.stderr); sys.exit(1)
if prov != "main":
    print("STOP: DO NOT INSTALL DOWNBEAT V3. Installed build came from '%s', not main." % prov, file=sys.stderr); sys.exit(1)
if pre.strip():
    print("STOP: DO NOT INSTALL DOWNBEAT V3. The tree was dirty before the install:\n" + pre, file=sys.stderr); sys.exit(1)
print("OVERTURE INSTALLED BUILD HAS THE GATE FIX, FROM MAIN, FROM A CLEAN TREE")
PY
```

3. Proceed to 0.2 only on **exit code 0**. Exit 1 means stop. Exit 2 means the check could not measure, which is not permission to continue: resolve what it names and run it again.

   **When Dan runs the install by hand** rather than through the step 1 block, `/tmp/overture-pre-install-tree.txt` does not exist and the check exits 2 for tree cleanliness. That is the honest answer, not a defect: nothing recorded the tree at the moment the bundle was built, and Overture's `installed-build.json` cannot say (see the follow-up below). The remedy is either to run the step 1 block as written, or for Dan to confirm the tree was clean at the moment he ran the install, which the agent records as his statement and not as a measurement. The commit ancestry and `provenance` halves of the check still measure normally.

4. Guard, added to the guards table and seen to fail before it is trusted (L1): run this against an `installed-build.json` whose commit predates the gate fix and assert a **non-zero exit**, not merely the printed word. Then run it with `provenance` set to `unknown` and assert exit **2**, distinct from the exit 1 a branch build produces.

**Why the check has three conditions and not one.** Reading only the recorded `commit` is the exact L70 self-consistent shape this plan warns about elsewhere. Overture's `mac/build-install.sh:118-140` builds `installed-build.json` from `git rev-parse HEAD` and records **nothing about uncommitted changes**. So in the case where the tree is dirty in files that happen not to differ between branches, the checkout succeeds, work in progress is installed, and a commit-only check reads the recorded field and **passes while vouching for a bundle it never inspected**. Downbeat records `dirtyFiles` for precisely this reason, citing downbeat#424 and the 2026-08-23 incident where "the record said 4a1cde0 while the bundle was 4a1cde0 plus changes that only became b51286a afterwards", and adds that "reading that silence as a clean tree would have an old record vouch for something nothing checked (L11, L98)". Ovation cannot read a field Overture does not write, so the check asserts the clean tree **in the same breath as the install**, when the two are adjacent in time, and asserts `provenance == "main"` because Overture does record that and a branch build is exactly what a commit-ancestry test cannot see.

**Two follow-ups, both filed in the same change as this step:**

- **`overture#`: `mac/build-install.sh` records no `dirtyFiles`.** File it against `danwright32/overture`, quoting Downbeat's `build-install.sh:71-101` and downbeat#424 as the pattern to match, including the optional-means-not-recorded convention. Until it lands, no Ovation guard may read Overture's `installed-build.json` alone as evidence about what is installed, and the plan says so rather than letting a future reader infer coverage.
- **Make the assertion permanent.** Clone Downbeat's `scripts/test-export-consumer-version.sh` as `scripts/test-installed-consumer-version.sh` under the 0.4.6 port discipline, so it reads the **installed** consumer's `installed-build.json` and asks whether the minimum-version commit is an ancestor of its commit **and** `provenance` is `main` **and** (once the issue above lands) `dirtyFiles` is `0`. It keeps the existing three-outcome shape and says **CANNOT MEASURE**, never pass, when there is no `installed-build.json`, no checkout to resolve the commit against, the file is unreadable, or a field it needs is absent (L98, L11). The existing guard measures source agreement; what breaks Dan is the deployed pair.

### 0.2 Reinstall Downbeat and prove the producer is live, without committing anything live

The installed binary cannot write the queue. Until it is replaced, every commit Dan makes is a shoot Ovation will never hear about.

1. Run `/Users/danielhankins-wright/Non-icloudDocuments/Apps/Downbeat/Downbeat/build-install.sh`.
2. Assert the **installed** binary, not the source tree: `booking-queue`, `startsAt` and `endsAt` must each be non-zero in `strings /Applications/Downbeat.app/Contents/MacOS/Downbeat`, with `blockedDates` still non-zero as the control. **Do not use `isRerunOf` as evidence**: it already shows 4 hits in the old binary because it predates v3 as a model property, so it proves nothing either way.
3. Launch Downbeat. Assert `~/Library/Application Support/Overture/downbeat-export.json` reads `"version": 3` and that its bookings carry `startsAt`/`endsAt`. Then relaunch Overture and assert its client roster and blocked dates are still populated, which is the acceptance test for 0.2.0.
4. **Prove the queue write from a test, NOT from a live commit, because Debug does not isolate what the previous draft assumed it did.** Two earlier drafts got this wrong in different ways. The first said "commit one throwaway booking" and cleaned up one of six side effects. The second moved the commit to a Debug build on the strength of Downbeat's own doc comment, which says a Debug launch runs "with a throwaway in-memory store, so anything it commits is fictional". **That sentence is false.** `Downbeat/DownbeatApp.swift:39-44` gates `isStoredInMemoryOnly: true` on `AppStoreConfiguration.isRunningUnderTests()`, never on `isDebugBuild`, and `isDebugBuild` has exactly two production uses, both in `AppStoreConfiguration`, controlling the export path and the queue path. A Debug Run from Xcode therefore opens the real store at `Application Support/Downbeat/default.store` and runs the real `.folder`, `.omniFocus`, `.fantastical` and `rosterUpdatePhase` side effects against Dan's real disk, his real OmniFocus and his real Fantastical Shoots calendar. Debug isolates two file paths and nothing else.

   The residual risk is worse than a mess to clean up. `BookingRetention` sweeps only bookings **7 days past** their shoot, so a throwaway dated in the future is never swept: it survives into the 0.3 custody snapshot taken minutes later, and reaches Phase 6's backfill as a real priced invoice consuming a number from the continuous sequence, which 5.6 says a cancelled invoice keeps. So:

   - **Write a Downbeat test** that drives the `bookingHandoffPhase` against an **injected** queue directory (the seam already exists: `bookingHandoffQueueURL` takes `applicationSupportDirectory`, `isDebugBuild` and `isRunningUnderTests` as parameters, and `Downbeat/DownbeatTests/BookingHandoffQueueTests.swift` already exercises all four combinations at lines 311-346). Assert the written file is named `<BOOKING-UUID>.json` and carries `version 3`, `committedAt`, `booking.startsAt`, `booking.endsAt` and a `client` object. This is a real test in the same commit as the change, so the push gate is satisfied honestly, and it touches no live path.
   - **Capture that test's output as Ovation's fixture**, ids and shapes preserved, every name and email replaced. It is synthetic by construction, so there is nothing to redact from a real client.
   - **The end-to-end proof comes from a booking Dan was making anyway.** Built is not wired, and wired is not proven (L3), and a test does not prove the installed Release binary writes to the real path. So the exit criterion is: **the next genuine booking Dan commits leaves a `<UUID>.json` in `~/Library/Application Support/Ovation/booking-queue/`**, which the agent asserts by count and filename only. That costs zero throwaway side effects, because the folder, tasks, calendar events and store row all belong to a shoot that is real. It is checked opportunistically and does not block Phase 1; **it does block Phase 6 opening**.
   - **No throwaway booking is committed, in Debug or Release.** If for some later reason one is unavoidable, it is **dated in the past** so `BookingRetention` sweeps it, and every side effect is enumerated and removed by name: the booking folder, the OmniFocus tasks, the Fantastical events, the store row, any roster edit.
5. **File `downbeat#`: the doc comment on `AppStoreConfiguration.bookingHandoffQueueURL` asserts an in-memory store under Debug that the code does not provide.** This is a comment that reads as a safety guarantee while the code provides none, in the file that decides where a record Ovation turns into a real invoice gets written. It has its own issue in `danwright32/downbeat`, milestone `Ungrouped`, `priority-p2`, category `correctness`, filed in the same change as this step, and it is fixed by correcting the sentence (Debug isolates the export path and the queue path, and nothing else), not by relying on it.

### 0.3 The two custody snapshots: one exists, one is taken after Dan's Downbeat reinstall

**This is the genuinely unrecoverable one.** `BookingHandoffQueue.write` is called from exactly one place, `CommitOrchestrator.swift:915`, at commit. There is no backfill. The already-committed future bookings running to 2027-06-13 were committed under the old binary and **will never emit a queue file**, no matter when the consumer ships. `BookingRetention.retentionDays` is 7, so the `Booking` row is deleted seven days after the shoot and the recovery window closes one shoot at a time from 2026-11-01.

> **CORRECTED 2026-08-28.** The earlier draft of this step created a folder at `Apps/Ovation-custody`
> and took one v3 snapshot. Two things were wrong. A snapshot had **already been taken** on
> 2026-08-27 21:26, at `~/Library/Application Support/Ovation/custody/`, and recorded with its hash
> in `docs/CUSTODY.md`; the plan and the custody note named different folders and only one existed.
> And that existing snapshot is **version 2**, so it carries `startDate`/`endDate` day strings and no
> `startsAt`/`endsAt` instants. **`docs/CUSTODY.md` is the record of where these files are.** This
> step is written against it, and any change to a path or a hash goes there first.

**Snapshot 1, already taken, is the record of WHICH bookings existed.** `downbeat-export-2026-08-27.json`, version 2, 20 bookings, 31 clients, hash in `CUSTODY.md`. It is verified by hash at every read. It is the only record of the 2026-08-18 booking (the one retention sweeps at Dan's next Downbeat launch, and the one whose `clientId` does not resolve), so the reconciliation in Phase 6 reads its **ids** from this file.

**Snapshot 2 is taken by the agent immediately after Dan reports 0.2 done, and is the record of the shoot TIMES.** The v3 export rewrites in full on launch, and it will carry real instants: measured 2026-08-28, all 20 stored bookings hold a non-midnight `startDate`, and `OvertureExportBuilder.swift:103` maps that value into `startsAt` unrounded. It goes in the **same** custody folder, so there is one place and one note:

```
cp "$HOME/Library/Application Support/Overture/downbeat-export.json" "$HOME/Library/Application Support/Ovation/custody/downbeat-export-v3-$(date +%F).json" && shasum -a 256 "$HOME/Library/Application Support/Ovation/custody/downbeat-export-v3-$(date +%F).json" | tee "$HOME/Library/Application Support/Ovation/custody/downbeat-export-v3-$(date +%F).json.sha256"
```

Verify it landed. This must print the file size and the same hash:

```
ls -l "$HOME/Library/Application Support/Ovation/custody/"downbeat-export-v3-*.json && shasum -a 256 -c "$HOME/Library/Application Support/Ovation/custody/"downbeat-export-v3-*.json.sha256
```

Then the agent adds a second table to `docs/CUSTODY.md` for it, in the same change, with the version, the hash, and the counts below.

**Assert 19, not 20, on snapshot 2.** `BookingSweep.run` fires on launch from `LaunchMigrations.swift:2987`, and the 2026-08-18 booking is 9 days past a 7 day window, so it is gone before the v3 export is written. The assertion is: **version 3, 19 bookings, every one carrying `startsAt` and `endsAt`, earliest 2026-10-25, latest 2027-06-13.** An agent following the old "all 20 bookings" wording would have stopped on a failed assertion for a correct system. Snapshot 1 keeps 20.

**Where the custody folder sits, and what that decides.** `Application Support/Ovation/custody/` is inside Ovation's own Application Support directory, beside where the queue and the store will live. Three consequences, each decided here rather than discovered:
- **It is inside the backup set** (1.8, PRD 29b). These files are the only record that 19 shoots existed and how long they ran, and a backup that omits them is not self-contained.
- **It is a needle source for the 0.1 identity guard**, alongside the live export, because it carries the same 31 client names and 5 venue names.
- **It is outside the 1.9 test floor's writable set**: no test may create, modify or delete a file under `custody/`, and the resolver returns nil under tests exactly as the queue resolver does.
- **Ovation never writes here itself.** The folder is written by the agent at custody time and read by Phase 6. `Ovation deletes nothing automatically` (5.30) covers it, and a Debug Ovation reads the same folder as Release because the files are facts about Dan's bookings, not app state.

**The backfill source lacks the guarantee the queue has, and the plan says so rather than assuming it (L214, L521).** A handoff record is self-contained by design, so a later roster edit cannot change what an unconsumed record resolves to. The export is not: `bookings` and `clients` are separate arrays joined by `clientId`. The live file already contains an instance of the failure, 1 of 20 bookings pointing at a client with no row. So Phase 6's backfill carries an explicit refusal: **a snapshot row whose `clientId` does not resolve in that same snapshot's `clients[]` is named and refused. It is never turned into a shell client and never silently priced.** That the one live instance happens to be the booking retention removes is luck, not a guarantee, and the refusal is what makes it not matter.

To be explicit about what this does **not** change: the queue consumer stays at position 5 of Dan's order. Downbeat never sweeps the queue, so bookings committed **after** 0.2 wait safely. The snapshot covers only the ones committed **before** it, which no consumer ordering could reach.

### 0.4 Project scaffolding, signing and the install path

The earlier draft assumed all of this existed. None of it does, and Phase 1.1's `.debug` bundle suffix is a `project.yml` concept Ovation has no equivalent of.

1. **XcodeGen, not a checked-in `.xcodeproj`.** Port Overture's `mac/project.yml` shape. `xcodegen` is installed at `/opt/homebrew/bin/xcodegen`. Chosen over Downbeat's checked-in project because Overture's file is where the Debug bundle suffix, the URL scheme split and the unhosted pure-test target are all expressed declaratively, and Phase 1.1 depends on the first of those.
2. **A stable self-signed identity, before the first folder grant is requested.** Port `Downbeat/setup-signing.sh`. Its own header records why: ad-hoc signing mints a new code identity on every install, and folder permission grants are keyed to that identity, so an ad-hoc build re-prompts for access already granted after every rebuild. PRD 5.29's "folder Dan chooses" for backups walks straight into this. Run it once, before Phase 1.8 ever asks for a folder.
3. **`build-install.sh`, writing `installed-build.json` with the UNION of what the two siblings record**, after the bundle verifiably lands. **Neither sibling writes the set Ovation needs**, so this is not "exactly as both siblings do": Overture writes `{version, commit, commitDate, repoPath, provenance}` and Downbeat writes `{version, commit, commitDate, repoPath, signingIdentity?, dirtyFiles?}`. Ovation writes `{version, commit, commitDate, repoPath, signingIdentity, dirtyFiles, provenance}`, because its own installed-consumer guard needs all three kinds of information: **which commit**, **whether the tree was clean**, and **whether it came from main**. Optional fields keep Downbeat's convention that absent means NOT RECORDED, never "clean" or "main", and any reader treats an absent field as CANNOT MEASURE (L11, L98). That record is the only reason 0.2.0's check was possible at all.
4. **`scripts/install-git-hooks.sh` and `scripts/git-hooks/pre-push`,** ported from Downbeat, run once. Until this lands the style gate and the test gate do not apply to this repository, whatever the plan says about them.
5. **The test lock, decided rather than left open.** Downbeat's `scripts/run-tests.sh:50` reads `LOCK_DIR="${TEST_LOCK_DIR:-/tmp/xcodebuild-tests.lock}"` and its header asserts the lock "is shared with Overture deliberately... A lock only one project takes is not a lock." Overture locks `/tmp/overture-mac-tests.lock`, and `xcodebuild-tests.lock` appears nowhere in its tree, so the sharing is not true today. A third macOS app running `xcodebuild` on this Mac with no lock decision corrupts the other suites' runs and teaches Dan to distrust a red suite, which is the failure Downbeat's script says it exists to prevent. > **CORRECTED 2026-08-27.** The recommendation and the fallback below were both mechanically
> impossible as originally written, and the reason is worth stating because it is the whole
> difficulty: **the two siblings do not merely lock different paths, they use different mechanisms.**
> Verified in both scripts today. Downbeat acquires by `mkdir "$LOCK_DIR"` on `/tmp/xcodebuild-tests.lock`
> (`scripts/run-tests.sh:59`), a DIRECTORY used as a mutex because `mkdir` is atomic everywhere.
> Overture acquires by `flock "${LOCK_FILE}"` on `/tmp/overture-mac-tests.lock`
> (`mac/scripts/run-tests-locked.sh:547` and `:753`), a regular FILE, using
> `/opt/homebrew/bin/flock`, whose absence the script checks for at `:470` and tells you to
> `brew install flock`. The two cannot coexist at one path: `flock` opens with `O_CREAT` and cannot
> open an existing directory that way, while `mkdir` on a path already holding a regular file
> returns `EEXIST`, which Downbeat's loop reads as "lock held" and then waits out
> `TEST_LOCK_TIMEOUT`, thirty minutes by default, before calling `claim-stale-lock.sh`. So
> "point Overture's runner at the same directory" is a mechanism rewrite, not a path edit, and
> "take both existing lock directories" is wrong because only one of the two is a directory.

**The real options, all of which are achievable:**

- **A. Ovation takes both, by the mechanism each one uses**, in a fixed order: `mkdir` on `/tmp/xcodebuild-tests.lock` first, then `flock` on `/tmp/overture-mac-tests.lock`. Ovation then genuinely excludes both siblings, touches neither repository, and cannot deadlock because neither sibling takes two locks. It does not fix the pre-existing defect that Downbeat and Overture still do not exclude each other, which is filed as its own issue. It also inherits Overture's Homebrew `flock` dependency, so Ovation's runner must check for it and say so rather than failing obscurely.
- **B. Convert Overture's runner to `mkdir` on the shared directory**, making Downbeat's header comment true and removing the `flock` dependency from the estate entirely. One mechanism, one path, all three apps excluding each other. It changes a script in a repository being actively worked on, and Overture's runner is 700 lines with the lock taken at two separate sites.
- **C. Ovation takes only Downbeat's directory lock**, and the full reconciliation is filed as a tracked issue for later. Simplest, and Ovation excludes Downbeat but not Overture, so an Overture suite and an Ovation suite can still collide.

**Two things any change to Overture's runner must respect:** it must keep the existing environment override seam rather than hardcoding a second path, and it must not assume one source tree per repository, because `.claude/worktrees/agent-*` holds full copies of the Overture sources and a runner or linter finding its inputs by a default recursive glob collects them (L234). **Whichever is chosen, do not ship a third app that locks a fourth file.**
6. **The port discipline, applied to every ported artifact and not only to the Gmail files (L501).** This plan ports at least eleven things one line at a time: Downbeat's `.gitignore`, `Downbeat/setup-signing.sh`, `Downbeat/build-install.sh`, `scripts/install-git-hooks.sh`, `scripts/git-hooks/pre-push`, `scripts/test-export-consumer-version.sh`, `Downbeat/Persistence/StoreSchemaGuard.swift`, `CooperativePoolTests`, `scripts/measure-questionnaire-ocr.sh` and `scripts/verify-questionnaire-samples.sh`, plus Overture's `mac/project.yml` and `mac/Overture/App/StoreLocation.swift`, and in 5.0 the seven Gmail and OAuth files plus `ReplyDetection.swift`'s Sent predicate. A clone copies the pattern **as first written**, including every value already corrected in the original, and the clone's own note that it follows a proven pattern is what makes it read as safe. This plan has already caught one instance of exactly that in itself: the earlier draft "ported Downbeat's identity guard as it stood before L217 corrected it". So the remedy is generalised rather than left on the one case that was noticed:
   - **Every ported file carries a header naming its source repository, path and commit.** No exceptions, and no "ported from Downbeat" without the commit.
   - **The porting issue lists every constant, threshold, path and exemption entry in the ported file, with the rule it has to satisfy for Ovation**, re-checked at the moment of the port rather than inherited. Rotation counts, lock paths, cap sizes, sample thresholds and exemption lists are each a place where the original's current version and the version being copied can differ.
   - **Where the sibling has an open correction against that file, the issue is named in the header.** `mac/build-install.sh` has one as of 0.2.0.
   - **A check asserts each ported artifact's recorded source commit is an ancestor of that sibling's current `main`**, so a port made from a stale checkout or an unmerged branch is reported rather than assumed. It says CANNOT MEASURE when the sibling repository is not on the machine, never pass.

---

## Phase 0b, four probes, in parallel with the foundation work

Each probe is one day at most, has its **kill condition written down before the run**, and a named plan B. They are on a different critical path from the build (probe 4 is gated on Dan gathering receipts, which no amount of build work accelerates). **Every probe obeys the 0.1 privacy floor: counts, ids and booleans out, never content.**

**Probes 1, 2 and 3 are dropped (2026-08-28), because two are already measured and one decided nothing.** Probe 1 asked whether a SwiftData `.unique` collision refuses or destroys. **PRD 42a measured it on 2026-08-28, Swift 6.3.3 on macOS 26.5.1: the save did not throw and the fetch returned one row holding the SECOND value.** So every place that would lean on uniqueness checks for the existing record in Ovation's own code and refuses before writing, and 1.10's allocator keeps its full defence. One consequence that goes into Phase 2 rather than being left here: **even the surrogate `id: UUID` is a silent overwrite on collision, so no invoice, expense or ledger row id may ever be DERIVED from a booking id, a message id or any other external identifier.** A re-run or a re-intake carrying the same external id would otherwise replace the original with no error anywhere. Probe 2 asked where `.externalStorage` puts its bytes. **PRD 42b measured it: a hidden folder beside the database, which Downbeat's backup does not copy while its verification passes.** 1.7 stands on that measurement. Probe 3 had no kill condition and changed nothing: money is `Int64` minor units regardless. The numbering of the remaining probes is kept so cross-references elsewhere in this plan still resolve.

**Probe 4a, digital receipts, genuine two-reader agreement.** See Phase 4.0. 20 to 30 of Dan's real digital receipts (PDF and HTML email bodies). Two independent readers: text-layer extraction and Vision OCR over the rasterized page. Per field agreement rate.

**Probe 4b, image-only receipts, is there an independent second reader at all (L248).** This probe exists because the earlier draft closed a door without measuring it. Ruling the second reader out for photographed receipts rested entirely on FoundationModels taking no image input. That finding is real and I confirmed it in the **`arm64e-apple-macos` slice** of the macOS 26.5 SDK interface (75,929 bytes; the Mac Catalyst slice is 75,890, and the plan quotes the slice Ovation builds against because it uses byte counts as evidence). But it closes the whole category, and nothing downstream ever re-tests a closed door, because the work that would have exercised it is the work the finding stopped anyone writing. So, one day, against the same sample set and **under the same control as the finding that ruled FoundationModels out**, measure each candidate and **record the result whichever way it lands**:
   - a second Vision recognition level or revision over a differently preprocessed raster (**same OCR family, so it can only be logged as corroboration of the same reader, never counted as independent**)
   - `RecognizeDocumentsRequest`'s structure output (**also same OCR family, same caveat**)
   - **arithmetic self-consistency**: subtotal plus tax against the separately-read total. An independent *constraint*, not an independent reader, and the one candidate that actually catches the failure mode that matters, since a misread `88.20` for `38.20` fails the sum while a self-sourced confidence score does not
   - **barcode or QR payload** where the receipt carries one, via `barcodeDetectionOptions`. Genuinely independent of OCR where present; measure how often it is present at all

**Probe 5, `gmail.modify` grant.** One day. Attempt the OAuth consent flow requesting `gmail.modify` against Dan's account. No app in this estate has ever held this scope.

> **CORRECTED 2026-08-28 against PRD 17a.** The earlier draft named a plan B ("do not write to the
> mailbox at all, keep a consumed-message ledger instead") and called it arguably better. Dan
> decided the opposite on 2026-08-27: **moving the message to Logged is required**, because an
> empty Receipts folder is how he knows a receipt was filed, and a refused permission is "a
> blocker to solve rather than a fallback to accept". So the ledger route is **not a shipping
> design** and 4.2 no longer branches on it. The consumed-message ledger is still written
> (belt and braces, and the reason in 4.2 step 8 stands), but it is never the only acknowledgement.

- *Kill condition:* the grant is refused, or the token it yields cannot perform a label modify on a message in Dan's own mailbox. Either result **goes to Dan as a blocker**, with what Google said, and does not switch the plan to a fallback.
- **Reuse Overture's existing OAuth client and Google Cloud project, and verify that rather than assume it.** Overture already holds `gmail.readonly` and `gmail.send`, both in the same restricted tier as `gmail.modify` (PRD 17a), with refresh tokens that have stayed valid for weeks. A **new** client on a consent screen left in "Testing" publishing status gets refresh tokens that **expire after seven days**, which would surface months later as Ovation randomly logging Dan out of Gmail. The probe records which project and client id it used and the consent screen's publishing status, so the token lifetime Ovation depends on is a measured fact and not an inherited one (L82, L25).
- Adding a scope to an existing client forces a fresh consent. The probe confirms the re-consent does not disturb Overture's existing token (different app, separate token file), and says so by count of Overture sends that still succeed afterwards, never by content.

**Probe 6, derived-Sent match against a real mailbox (PRD 5.10a, risk 9.14), judging by Gmail's own committed state marker (L181).** Half a day, read-only, `gmail.readonly` only. **The probe has no mode that returns message content.**

**The correction this probe needed.** The earlier draft matched on the invoice number appearing in the Sent folder, with "does it carry a PDF attachment, is a recipient on the invoice" as its only refinements, and never mentioned Gmail's `DRAFT` label. That is overture#2918 reproduced in the same mailbox. **Gmail returns unsent drafts in the same collections as real mail**, and every attribute the draft proposed to match on (the invoice number, a PDF attachment, a recipient on the invoice) is carried identically by a draft Dan started in Spark and abandoned. Because 5.10a forbids Dan from asserting or retracting Sent by hand, an abandoned draft would stamp the invoice Sent permanently and silently, which is worse than the L162 gap the requirement exists to close: a draft stuck as a draft is visible, while an invoice wrongly marked sent leaves the list and is never chased.

The corrected, fail-closed predicate already exists one repository away, in exactly the code Phase 5.0 touches. `mac/Overture/Domain/ReplyDetection.swift:133-136`: `wasSentByUser` is `labels.contains("SENT") && !labels.contains("DRAFT")`, and `labelIds(of:)` at line 114 returns **nil when the field is absent** rather than an empty array, so a missing field is a refusal and not an implicit "not a draft" (L506, L215). Its own comment names the asymmetry: a message wrongly accepted clears a row permanently and silently, one wrongly refused costs a glance. Writing a second, weaker detection beside it would be L30 and L195 as well as L181.

So:
- **The probe and 5.10a both use that predicate**, ported into the shared Google package at 5.0 so all three apps share one definition rather than Ovation becoming a third copy.
- **Ovation requests a Gmail message format that returns `labelIds`**, and refuses the match **by name** if a response does not carry it, rather than treating the absence as not-a-draft.
- The probe takes an invoice number and returns, per candidate message, an id and a boolean per named field: `SENT` present, `DRAFT` present, carries a PDF attachment, a recipient is on the invoice. Plus a match count over the last 12 months of Sent. Nothing else. **Draft-carrying candidates are counted as their own outcome**, never folded into matches or into non-matches.
- *Kill condition:* if the predicate returns the invoice reliably with zero false positives **and zero draft-carrying candidates admitted**, 5.10a ships as written. If it produces false positives among non-drafts, the derived route additionally requires a PDF attachment and a recipient on the invoice. If it produces false negatives, 5.10a goes back to Dan rather than quietly leaving the L162 gap.
- **Seen to fail (L1):** a fixture draft message carrying the invoice number, a PDF attachment and the right recipient, which **must NOT establish Sent**; and a fixture response with `labelIds` omitted entirely, which must produce a named refusal, not a match.

---

## Phase 1, the foundation work, tracked on the feature milestones

A foundation milestone with no forcing function expands, and PRD 9.10 already names zero deadline pressure as a live risk. The enumerate-and-freeze discipline is the answer and it is kept. But a `Durable foundation` milestone violates hard constraint 5c, which requires a milestone per **feature**, and it is exactly the theme title `~/.claude/skills/milestone/NAMING.md` exists to stop (its own bad list from 2026-07-30 includes "One store, one truth" and "Trustworthy local verification: tests, guards, and the build"). It would pass the mechanical gate on punctuation and length while being the shape the gate was written to catch.

So: **the build order below is unchanged, and the foundation is still built first. What changes is where each issue is tracked.** Each issue is filed against the feature milestone that cannot ship without it, and each of those milestones carries a written scope note naming its foundation issues, so the freeze survives the redistribution. **Nothing joins a milestone's enumerated list after it opens.** A later candidate goes to a later milestone or to `Ungrouped`.

| Foundation issue | Milestone |
| --- | --- |
| 1.1 Store location, filename, Debug isolation | `Year end tax export` |
| 1.2 Store schema guard | `Year end tax export` |
| 1.4 `Money`, Int64 minor units | `Year end tax export` |
| 1.5 `BusinessCalendar` | `Year end tax export` |
| 1.6 Day-keys stamped at write | `Year end tax export` |
| 1.7 Blob storage, files plus SHA-256 | `Year end tax export` |
| 1.8 Backup and restore | `Year end tax export` |
| 1.9 Test isolation floor | `Year end tax export`, extended in every later milestone |
| 1.13 Problems store and the one launch presenter | `Year end tax export` (the first milestone to ship) |
| 1.10 Invoice number allocator | `Invoicing and sending` |
| 1.12 Referral ledger | `Invoicing and sending` |
| 1.11 Consumed-booking ledger | `Downbeat booking queue consumer` |
| 1.3 Single-instance guard | `Ungrouped` |
| `CooperativePoolTests` | `Ungrouped` |
| Gmail token store and its off-main guard | `Expenses and receipt intake` |

**1.1 Store location, filename and Debug isolation.** Port `mac/Overture/App/StoreLocation.swift` under the 0.4.6 discipline. Release store at `~/Library/Application Support/Ovation/Ovation.store`.
   - **`Ovation.store`, not `default.store`, is a deliberate departure from Downbeat and it is stated here because an agent porting "the Downbeat pattern" literally would undo it.** Downbeat's own store is at `Application Support/Downbeat/default.store` (`Downbeat/App/AppStoreConfiguration.swift:44-46`): a dedicated subfolder, but SwiftData's **default filename**. Overture uses `Overture.store`. `StoreLocation.swift` records two data losses at `Application Support/default.store` on this Mac (Downbeat 2026-07-08, `/usr/libexec/icloudmailagent` 2026-07-23), so reintroducing the default filename puts Ovation's name on the exact filename those incidents are about. Ovation follows Overture here.
   - Debug at `Ovation-Debug/Ovation.store` with a `.debug` bundle suffix declared in `project.yml` (Phase 0.4), so a dev run can never share a store, WAL, TCC grant, Gmail login or backup folder with the resident copy.
   - The wiring detail that will bite otherwise: Downbeat writes the queue to `Application Support/Ovation/booking-queue/` and its Debug build to `Application Support/Ovation/booking-queue.debug/`, a **sibling inside `Ovation/`**, not inside `Ovation-Debug/` (`AppStoreConfiguration.swift:114-127`). So Ovation Debug's store lives in `Ovation-Debug/` while its queue source lives in `Ovation/booking-queue.debug/`. Assert both paths in a test that fails if either resolver is changed to match the other.

**1.2 Store schema guard.** `StoreSchemaGuard` exists in **both** siblings: `Downbeat/Persistence/StoreSchemaGuard.swift` and `mac/Overture/App/StoreSchemaGuard.swift`. **Port Downbeat's**, because it is the one whose verdict set is already named for the owning app (`noStoreFile`, `empty`, `downbeat`, `foreign(entityTables:)`) rather than a generic `ours`, which is the distinction Ovation needs when the file it finds may belong to either sibling. Under the 0.4.6 discipline, the port diffs the two current versions first and records which behaviours differ and why Ovation takes each one, because this is a pattern already written twice and L501 says clone the current version rather than the first.
   - Read-only inspection of the file at the store path before anything opens it for writing. The "this is mine" verdict is named `ovation`. Core Data does not throw on a foreign file; it creates its tables inside whatever it is handed and reports success. Ordering, ported from `StoreLaunchSequence`: identify, checkpoint, back up, *then* open.
   - **Seen to fail:** plant a foreign SQLite file at the path and assert a `foreign` refusal naming the tables it found, not a generic throw (L140).

**1.3 Single-instance guard (5.37), implemented the way the sibling that gets it right does.** A second running copy refuses and **names the copy it stood aside for**. Identify by PID resolved from the executable path, never by bundle id or app name.
   - **Do not implement this with `LSMultipleInstancesProhibited`.** That key appears **only** in `mac/Overture/Info.plist:21` and **nowhere in Downbeat**. Overture's `mac/scripts/run-tests-locked.sh:91-95` records that a running Debug app holding that lock makes the xctest host fail to launch and the run dies after a full build, and `:333-340` records what the misdiagnosis cost: a hardcoded hint naming that cause "sent hours of elimination in the wrong direction".
   - **Downbeat already implements the refusal in application code**, at `Downbeat/App/RootView.swift:23-24`: `if case .secondCopy(let other) = secondInstance { SecondInstanceRefusalView(other: other) }`, downbeat#292, "A second running copy stands aside rather than competing for the one OmniFocus reply channel and the one clipboard". So the app-code route is **the sibling pattern, not a workaround**, and Overture's plist route is the one that costs the test runs. Cite `RootView.swift:23-24` alongside `run-tests-locked.sh:91-95` and `:333-340` in the issue body.
   - Implement the refusal as a PID check at launch against the executable path, and surface it through the one launch presenter (1.13), not as an independent alert.
   - **Seen to fail:** a test asserting that a running Debug Ovation does **not** prevent the suite launching. That is the failure mode, not the guard itself.

**1.4 `Money`, Int64 minor units.** One type, no `Double` and no `Decimal` anywhere in the store or in arithmetic. Explicit rounding rule at exactly one place: the tax computation. 8.875% of a subtotal in cents, rounded half-up, applied to the **whole subtotal** matching invoice 1057 (5.5), with 9.5 unresolved, so the rate and its base are stored on the invoice, not read from settings at render time. **Rates are frozen onto the invoice at creation**, so a settings change never silently rewrites a sent document. Property tests: no sequence of line items can make the sum of parts disagree with the stored total (5.42).

**1.5 `BusinessCalendar`.** One helper, `America/New_York` pinned, used for every business date (5.31). Never the host clock's zone. Tests at month, year and midnight boundaries with a **pinned clock**, including the case that decides everything under the accrual basis (PRD 24): an **invoice whose date instant is 2026-12-31 23:30 America/New_York**, which is 2027-01-01 UTC, must key to 2026. The same instant as a payment date exercises the payment columns and the sales tax period, which still matter for 25 even though they no longer decide the year. **Seen to fail:** the same assertions re-run with `TZ=Pacific/Auckland` **set by the test itself**, not inherited (L504).

**1.6 Day-keys stamped at write.** Every record carries an immutable `businessDayKey` string computed by `BusinessCalendar` at the moment of writing, alongside its instant. Derived-at-read dates drift when the host zone changes; a stamped key does not (L37). The export groups on the stamped key.

**1.7 Blob storage, files plus SHA-256.** Receipt images and invoice PDFs are files under `Application Support/Ovation/documents/`, referenced by relative path and content hash. Not `@Attribute(.externalStorage)`. The reason is not the probe result: the **backup must enumerate every referenced blob**, and a hidden sibling directory the backup does not copy while `verify()` still passes is the shape of L98.

**1.8 Backup and restore (5.29, L7).** Dated, self-contained backups to a folder Dan chooses, requested **after** Phase 0.4's stable signing identity exists so the grant is not re-prompted on every rebuild. Rolling set. **Verification enumerates every referenced document and checks its hash**, not merely that the database opens. A backup that cannot be read back is reported as a failure, never as silence, and it reaches Dan through the one launch presenter (1.13). Restore is offered in the app and **backs up the current state before overwriting it** (L5). Rotation evicts the oldest only after the new one verifies.
   - **What a backup contains is enumerated here, not left to whoever writes it (PRD 29b):** the store and its write ahead log, the documents directory addressed by hash, both consumed-identifier ledgers, the referral ledger, the Problems store, the export run records, and the `custody/` folder from 0.3. **It EXCLUDES the credential store.** A backup that lands in a folder Dan chooses, which on this Mac may sync to a Synology, must never carry a long lived refresh token granting send and modify on his mailbox. **A guard asserts no backup archive contains the token file**, by name and by content hash, and it is seen to fail by planting the token file in the staging set before it is trusted (L1, L19). A restore that does not require re-authorising Gmail is its own decision with its own sign off, never a side effect of being thorough.

**1.9 Test isolation floor (5.29a, L2, L191, L196, L201, L215).** The earlier draft listed paths only, which covers the way in and not the way out. Two facts drive the size of this: **Overture's Gmail, OAuth and reply-detection sources contain zero occurrences of `isRunningUnderTests` or any equivalent refusal across all 15 files and 2230 lines**, and Phase 5.0 vendors seven of them whole-file into Ovation. So a test exercising the 4.2 intake path with Dan's real token on disk talks to his real mailbox, and under the `gmail.modify` route relabels his real receipts. A test write into either consumed-identifier ledger is equally unrecoverable: it permanently suppresses that booking's invoice or that message's receipt.

The floor covers, structurally, and **the list below is the complete enumeration, extended explicitly in each later milestone rather than by whoever notices**:
   - the backup folder, the receipts folder, the documents folder, the handoff queue and the agreement log, whose resolvers return `nil` under tests exactly as `AppStoreConfiguration.isRunningUnderTests()` does in Downbeat (`guard !isRunningUnderTests else { return nil }`)
   - **the Gmail client itself**, with the refusal inside the vendored client, not only in a path resolver, so a caller that constructs its own client is still refused (L196). It **returns a named refusal, never an empty result** (L215)
   - **the OAuth credential read** (the 0600 token file, see the token store issue below)
   - **the consumed-booking ledger (1.11) and the consumed-message ledger (4.2)**
   - **the Problems store (1.13)**
   - **the export run record (Phase 2)**, added here explicitly and not left to Phase 2 to remember. Phase 2 is the first milestone and deliberately carries the heaviest test coverage in the plan: the completeness reconciliation, the two boundary fixtures, the zero-row fixture and the throwing fixture **all run the export**, so each of them writes a run record. A test-written successful run record makes the 35-day staleness problem permanently unraisable, and the plan's claim that the rehearsals are "something the system can substantiate from its own records" would then be substantiated by the suite rather than by Dan. This is the Downbeat agreement-log defect (198 of 200 lines were test writes) applied to the record the January success measure depends on.
   - **the export output directory**, for the same reason on the way out (L201): a test that names the real output folder writes real CSVs over whatever is there.
   
   Every one of these is **received as a dependency, never constructed at the call site**, and the refusal lives inside the writer rather than only in a path resolver. **The refusal ships in the shared package (5.0), not only in Ovation's copy**, or Downbeat and Overture inherit a client with no refusal at migration.
   - **Seen to fail (L140):** a test that attempts a real mailbox move; a test that attempts a real ledger append; a test that attempts to append an export run record; a test that attempts to write a CSV to the real output folder. **Each asserts the specific named refusal, not merely that something threw.**
   - **And the quantity itself is asserted, not a proxy for it (L63):** a guard test runs after a full suite pass and asserts the count of export run records written by the suite is **zero**, and the same for consumed-identifier ledger entries and agreement-log lines.

**1.10 Invoice number allocator (5.6), with its floor derived from the store and a destination check on BOTH writers (L55, L145, L521).** One serialized allocator, sequence starting at **1123**, continuous, a cancelled invoice keeps its number. **No `@Attribute(.unique)` on it or on any other business key**, following `Downbeat/Domain/DuplicateNameCheck.swift:5`.
   - **Phase 3 makes the QuickBooks importer a second writer of the invoice number field, two milestones before the allocator ever issues one.** Imported 2026 invoices carry QuickBooks numbers (probe 6 uses 1057, a real one). A read-modify-write over Ovation-allocated numbers only cannot see them, so an allocated number can land on an imported one, and the allocator's own tests pass throughout because no fixture contains an imported row.
   - So: **the allocator's floor is derived, not asserted. It allocates above the maximum invoice number present in the store, imported rows included, and it refuses to write a number that is already taken rather than writing it** (L145). Allocation is a read-modify-write inside one critical section with a **post-save read-back** (L127).
   - **The same destination-is-free check binds the importer, and this issue settles that rather than deferring it.** The earlier draft gave the refusal to the allocator alone and left the importer with a report plus an open question, "decide later whether an imported and an allocated invoice may ever share a number". The plan's own revert design opens the window that leaves unguarded: its seen-to-fail test is "import, revert, re-import with the importer version bumped", and it **expects** re-imports, because the QuickBooks format is unverified and "the likeliest outcome is an import that succeeds and is wrong". A revert lowers the maximum number in the store, the allocator legitimately issues a number a reverted batch held, and the re-import writes that number back with no destination check. A report naming the collision **after** the write is a detection that labels rather than blocks (L67). The consequence is not cosmetic: 5.10a's derived Sent match refuses when more than one invoice matches a number (L521), so a single duplicated number **permanently disables Sent detection for that invoice**, and the refusal reads as the guard working.
   - **The decision, made here and not recorded for later: an imported invoice and an allocated invoice may never share a number.** An imported row whose invoice number is already held by any invoice in the store is **named and refused with its own reason in the 5.27 refusal report, never written**. Phase 3's report still carries the reconciliation (numbers imported, highest imported number, next number the allocator will issue), but as information, not as the control.
   - **Seen to fail:** allocate 1130, then import a fixture row carrying 1130, and assert the **importer** refuses by name. Import a fixture carrying 1130, then allocate, and assert the **allocator** refuses to reuse it. Run the full import, revert, allocate, re-import sequence and assert **no two invoices share a number at any point**. And hold two allocators at the decision point simultaneously and assert they receive different numbers (L157, prove it by holding two callers there, not by hoping an interleaving reproduces).

**1.11 Consumed-booking ledger (6.36, L512), and the cross-repo deliverable it closes.** Ovation's own durable append-only record of every booking id it has consumed, independent of the queue files it deletes, so a booking whose invoice is later lost is recoverable after Downbeat's copy is swept. A forward-only drain's first gap is permanent and the redo path is invisible until a gap exists. Same shape reused for consumed Gmail message ids in Phase 4.
   - **This is not an internal Ovation concern. `downbeat#432` is parked waiting on it**, per `Downbeat/CLAUDE.md:178-180`: a crash between saving a booking and writing its queue file loses the handoff with nothing able to detect it, because Ovation acknowledges by deleting, so absent means both "consumed" and "never written" (L258).
   - Exit criteria are cross-repo and written into the issue: **(a)** Ovation publishes the consumed-booking ledger in a documented, machine-readable shape at a stated path, added to `Downbeat/Integration/OvertureExport/CONTRACT.md` in the same change; **(b)** Downbeat writes a **durable per-booking handoff-intended mark in the same save transaction as the `Booking` row**, which is the producer-side half L258 requires and which no Ovation-side record can substitute for; **(c)** `downbeat#432` closes in the same milestone. Without (b), an absent record still means two things and the reconciliation in Phase 6 has nothing independent to compare against.

**1.12 Referral ledger with a per-booking idempotency key (5.8, 6.42, L83).** The balance is a **sum over an append-only ledger**, never a stored field. One declared home: the client who earned it. One writer, from both the earning and the spending side.
   - An append-only ledger protects the **sum**, never the **writer**. Credit fires when the first invoice is marked paid, "paid" is itself derived from summed payments (5.14), and both 5.11 (edit and resend) and 5.13 (cancel with refund) can re-cross that transition. So the credit entry is **keyed on the earning booking id** and a second append for that key is refused. **Seen to fail:** drive the paid transition twice, via cancel-refund-repay, and assert exactly one credit entry exists (L1, L159).

**1.13 The failure surface: a Problems store, and ONE launch presenter (L242, L243, L126, L11).** Ported from Downbeat's "raises a problem naming that shoot, and deliberately never retracts" pattern. Every failure path in the app lands here, loudly, with a distinct sentence per cause (L11). No catch block returns a blank result or a fake success. It never retracts, because a later success says nothing about the earlier failure. It must exist before the first error path is written, and it is inside the 1.9 isolation floor.

   **The presentation route is decided in this issue, before the first error path exists, because the plan raises at least six independent conditions at launch and had said nothing about how any of them reaches Dan.** They are: 1.2's `foreign` store refusal, 1.3's single-instance refusal, 1.8's backup verification failure, Phase 2's export staleness report, Phase 2's zero-row notice, 6.32's queue and label state, and every Problems entry. postroll#846 and #855, measured in this estate on 2026-08-22 and 2026-08-23, are exactly this failure: several independent presenters attached to one surface, where a surface that can show one thing at a time silently ignores every request past the first, and where a boolean-driven alert cannot notice that **which** condition is showing has changed, so one heading landed over another's buttons. Every model-level test passed while it was happening, and their own provenance names launch checks that run on every launch as the everyday case. Ovation raises more launch-time conditions than PostRoll did, several of them refusals whose whole purpose is to be seen.
   - **Every launch-time condition routes through one presenter holding the identity of what is showing**, never a set of independent booleans. A second condition arriving is then a **decision** the code makes (queue it, refuse it, replace it) rather than whichever one SwiftUI happens to honour.
   - **The durable Problems surface is the home for all of them**, and any modal is a shortcut into it, never the only place a condition is visible (L126). A condition that persists in the data must not be reachable only from a notice that clears.
   - **Seen to fail:** raise two launch conditions in one launch and assert **both** are reachable and correctly identified; and replace one with another while it is showing and assert the content changes with it (L243).
   - **Ovation is single window on purpose, and asserts it (PRD 41b, L238).** A flag on shared application state is presented once per surface bound to it, so a menu bar item or a deep link that opened a second window would put up a second copy of every notice above, and dismissing one would leave the other. The single running copy guard in 1.3 cannot see this, because a second window is the same process. So the app declares one window, the menu bar item (6.32) and any URL handler bring that window forward rather than opening another, and a test asserts that a second open request results in one window. This lives in the same issue as the presenter because they are one design.

**Two guards carried alongside 1.13, an hour each, because their whole value is existing before the code they judge:**
   - **`CooperativePoolTests`**, Downbeat's source-level detector for `Task.detached` doing blocking work on the cooperative pool, ported under the 0.4.6 discipline with **an empty exemption list**, and **seen to fail on a planted use before being trusted** (L241, L233: an inherited exemption entry with no reason is evidence nobody reasoned about it). Ovation runs Vision on every receipt, so this defect is otherwise pre-ordained.
   - **An off-main-thread entry point under a deadline for blocking platform work.** The earlier draft justified this as "Ovation reads the keychain for Google tokens on every launch". **That is false for Ovation.** Porting Overture means porting `GmailCredentials`, which deliberately does **not** use the Keychain: it stores tokens in a 0600 file (`gmail-tokens.json`, verified `-rw-------`) "because the app is ad-hoc signed during development (its code signature changes every build, which makes Keychain item ACLs churn and prompt)". So Ovation reads a **file**. The guard is still worth having, justified from **Downbeat's own `KeychainWork.swift` precedent** (Downbeat lost every window to `SecItemCopyMatching` blocking the drawing thread, L236), and applied to Vision and to any platform call that can need authorization. **Open in the same issue, now that Phase 0.4 mints a stable signing identity:** does a stably-signed Ovation change the token store decision back to the Keychain? Overture's own comment calls Keychain hardening "a tracked follow-up for a stably-signed build". Decide it in the open rather than inheriting a workaround whose reason Ovation may not share. Either way, the store is under Ovation's **own** Application Support directory, Debug-isolated per 1.1, and inside the 1.9 refusal.

---

## Phase 2, data model and year-end export (Dan's step 1)

Milestone: `Year end tax export`. Dan's order, unchanged, and the reason it is first: the export is what the primary success measure depends on.

- The full domain model on top of Phase 1's types: `Client`, `Invoice`, `LineItem`, `Payment`, `Refund`, `Expense`, `ExpenseCategory`, `ReferralLedgerEntry`, `ServiceType`. `@Attribute(.unique)` on surrogate `id: UUID` only.
- `income.csv` and `expenses.csv` for any date range, defaulting to the calendar year (5.23). **Income on an ACCRUAL basis: one row per ISSUED invoice, dated by the invoice date, whether or not it has been paid** (PRD 24, Dan 2026-08-27). Every row carries the payment state (unpaid, partly paid, paid, cleared, cancelled, refunded) and the payment dates and amounts as columns (24a), so an invoice billed and never collected is findable rather than indistinguishable from a paid one. Payment dates no longer decide the year. Sales tax as its own column (5.25). Single-receipt export in one action (5.26).
- **A draft is not income, and that makes 5.10a tax-critical.** Accrual counts income when an invoice is issued, and Sent is only ever observed (5.10a), never asserted by hand. So the set of invoices on the return is exactly the set whose Sent was established, by Ovation's own send or by the derived Gmail match, and an invoice sent from Spark that the match misses is **missing income**. Three things follow: (a) the export selects on Sent established, never on creation; (b) **drafts whose shoot has passed and were never issued are counted and named in the export manifest**, as their own line, never silently excluded; (c) probe 6 and the 5.10a match are on the tax path, not only the daily friction path, and their false negative rate is measured before this milestone closes (PRD 9.14).
- **Two questions for the accountant that this export cannot answer for itself, recorded in PRD 9.3 and asked in the same conversation as the accrual confirmation.** Which date is the issue date for the year: the invoice date (the shoot date, 5.7) or the day it was sent, since a December 30 shoot invoiced January 3 lands in different years under each. And how a refund made in a later year is reported under accrual. Until answered, the export keys on the **invoice date** and marks the choice in the manifest, and no refund fixture asserts a year.
- **No invoice, expense or ledger row id is derived from an external identifier** (booking id, message id, QuickBooks row). PRD 42a measured that a colliding surrogate id silently replaces the original with no error, so a re-run or a re-intake carrying the same external id must create a fresh id and find the existing row through Ovation's own lookup, never land on it by construction.
- Category to Schedule C mapping, **completeness enforced by a test over the enum, not by a default branch** (5.19a, L113). **Seen to fail:** add a category in the test, assert the suite goes red naming it.
- Expenses with no receipt carry the mark into the CSV (5.21). Imported 2026 expenses likewise (5.28).

**The export proves it is complete, not merely that it totals (L517).** The Schedule C map test plus 5.42 check a total against its own parts and therefore cannot see a row that never entered the export at all. The failure that ruins January is silent: an invoice whose stamped day key sits on a range boundary, an invoice whose Sent was never established, or an expense that falls out of both files, leaves a CSV that is well formed, totals cleanly against itself, and is short. So:
- The export emits a **manifest produced by the same predicate that selects the rows**: rows out and sum out, per file, plus the count of unissued past-shoot drafts it did NOT include (L16).
- A reconciliation asserts that **every issued invoice and every expense in the store whose stamped day key falls in the range appears in exactly ONE output row**, that no row appears twice, and that every payment and refund in the store is attached to exactly one exported invoice row or is named in the manifest as belonging to an invoice outside the range, looped over the boundary combinations.
- **Seen to fail:** a fixture invoice dated 2026-12-31 23:30 America/New_York asserted **into** the 2026 file and **out of** the 2027 one; an invoice issued 2026-12-30 and paid 2027-01-15 asserted into the 2026 file **only**, with its payment shown in that row; and a draft whose shoot passed 2026-12-10 and was never sent asserted **out of** the file and **into** the manifest's unissued count.

**The monthly rehearsal is made real, not asserted, and its alarm does not cry wolf (L27, L98, L514, L36, L11).** The earlier draft said the export "runs monthly from this phase onward" and then claimed the credit. Nothing made it happen and nothing noticed when it did not. Ovation does nothing while closed (6.32), Dan is the only user, there is no scheduler, and a missed month looks identical to a healthy one. So the rehearsal is built as a mechanism, with the alarm keyed correctly:
- Every export writes a **durable dated run record** carrying rows out and sums out per file, **written on every exit path including failure, in a `finally`** (L514). The run record is **inside the 1.9 isolation floor** (see 1.9), so the suite cannot write one.
- A run that produced zero rows records **zero rows as its own outcome**, never as success (L98).
- **The staleness alarm keys on the last export RUN THAT COMPLETED, whatever its outcome, not on the last successful one.** The earlier draft had these two sentences contradicting each other in the direction that costs: Phase 2 is the first milestone and ships against an **empty store**, so every rehearsal from then until the Phase 3 import produces zero rows, which the plan has deliberately defined as not-success. The alarm would be raised on the first day and stand for months with nothing Dan could do to clear it, training him to ignore the one surface carrying the plan's forcing function against PRD 9.10 (L36). Keyed on completion, a legitimately empty period clears it.
- **A zero-row run gets its own, differently worded notice**, naming the range it looked at and that it found nothing in it. "Nobody has run an export in 35 days" and "the export ran and correctly found nothing" are different situations and need different messages (L11).
- **The staleness problem is suppressed entirely until the store first holds an issued invoice or an expense**, and the issue says so rather than leaving it to be discovered. Before then there is nothing an export could be stale about.
- Both notices reach Dan through the **one launch presenter** (1.13), never as independent alerts.
- **Seen to fail:** a fixture with no completed run in 40 days, staleness problem **raised**; a fixture with a completed zero-row run yesterday, staleness problem **NOT raised** and the zero-row notice **raised**; an empty store, **neither raised**; and a run that threw, which must still write a record.
- The rehearsal count is then something the system can substantiate from its own records, and the plan claims only what the run record shows.

**This milestone cannot close on its own, and the plan says so rather than letting the dependency be discovered at the end.** PRD 26a requires a real partial year export in front of Dan's accountant before `Year end tax export` closes, and it has to be a partial year that includes the QuickBooks import, which is Phase 3, the next milestone. So the closing criterion is: **every issue in this milestone done, then Phase 3's import run, then the export sent to the accountant with their reply recorded and dated, then this milestone closes.** Phase 3 can open while this one is waiting. That accountant conversation also carries PRD 9.3 (the accrual basis rests on Dan's recall, line F of any past Schedule C settles it in two minutes), the issue date rule and the refund rule from the bullets above, 9.4 (asset threshold) and 9.5 (tax on rush and preview). One conversation, all of them, written into the milestone description so nobody has to remember the list.

---

## Phase 3, QuickBooks CSV import (Dan's step 2)

Milestone: `QuickBooks migration import`. Kept at position 2, per Dan. Gated on a real sample file existing, because 9.6 records the format as unverified and 5.27 requires the import to **name and refuse** every unparseable row with a reason, a contract you cannot write against a format you have not seen.

- Reports rows read, rows written, rows refused **with the reason for each**, and the totals, so they can be checked against QuickBooks before the import counts as done (5.27). A row it cannot parse is named and refused, never skipped quietly (L47).
- **The importer refuses an invoice number already held by any invoice in the store** (1.10), with its own reason in the refusal report. The report additionally carries the reconciliation as information: numbers imported, highest imported number, next number the allocator will issue.
- **Idempotency that does not suppress its own repair (L121).** Keying the import on a content hash per row plus the source file identity also blocks re-running a **corrected** parser over the same CSV forever. The format is unverified and this is the first pass at parsing it, so the likeliest outcome is an import that succeeds and is wrong: a sign flipped, a date read in the host locale, a category mapped badly. Fixing the parser and re-running would then write nothing and report success. Since 5.30 says Ovation deletes nothing automatically, there is no other exit. So:
   - the idempotency key is **source file plus row hash plus importer version**, so a corrected parser is a different key and can legitimately re-run
   - **every row records the import batch id that wrote it**, so a batch is reachable and revertible in one action
- **The revert is guarded at the moment it runs, not only at the moment of the import (L5, L38, L95, L180).** The earlier draft's only protection was "a verified backup is taken before the import runs". That backup protects the wrong moment. The revert is a destructive action taken later, potentially months later, over rows Dan has since worked on: an imported 2026 expense he has categorised, marked asset-flagged or attached a receipt to, or an imported invoice that now carries payments, a refund or a referral ledger entry. Deleting the batch takes those with it and enumerates none of them, and the pre-import backup cannot restore anything done since. That is a revert that reads as a safe undo of an import while being a delete of live work. So:
   - **a fresh backup is taken and verified at the moment of the revert**, not only before the import
   - **the revert refuses when any row in the batch has been edited since import or carries a dependent record**: payments, refunds, referral ledger entries, attached receipt blobs. The revert issue **enumerates those derived resources by name** (L38).
   - where a revert is still wanted over rows with dependents, the confirmation **lists what will actually be lost, derived from the real state** (L180), never a fixed warning sentence that reads identically whether it is taking one row or a subtree of ten
   - **Seen to fail:** import a batch, record a payment against one imported invoice, then revert, and assert the revert **refuses and names that invoice** rather than deleting it. And: import, revert (clean batch), re-import with the importer version bumped, and assert the rows come back **once**, not zero times and not twice.
- Partial failure records the attempt on the rows it failed, not only on the ones it completed (L47).
- Nothing is deleted from QuickBooks. The CSVs are kept in custody, in `.quickbooks-samples`, outside the tree and covered by 0.1's never-staged check.
- **Seen to fail:** a fixture with a malformed row in the **middle** of the file, not at the end (L165).

**What the sample request has to ask for, under accrual (PRD 24, 9.6).** The 2026 return filed from Ovation is the imported QuickBooks invoices (January to the cutover) plus Ovation's own. So one CSV is not enough. The request names three things: **the invoice list** with invoice number, date, client, lines, tax and total; **the payments or transactions export** so every imported invoice carries its payment state (24a) and payment dates; and **the invoices open at the end of 2025**, because an invoice issued in 2025 and paid in 2026 is 2025 income under accrual and must be imported as a prior year invoice carrying a 2026 payment, never as 2026 income. The importer refuses by name a payment whose invoice it cannot find, and the report counts prior year invoices separately.

If Dan has not produced a sample when this milestone opens, it **pauses** rather than being reordered around, and the pause is reported.

---

## Phase 4, expenses and receipt intake (Dan's step 3)

Milestone: `Expenses and receipt intake`.

### 4.0 First: the 18b measurement, and the honest reader architecture

**The finding that changes this half.** Verified in the macOS 26.5 SDK, `arm64e-apple-macos` slice: FoundationModels takes **no image input** (`Transcript.Segment` is `.text` or `.structure`; zero image symbols in 75,929 bytes of interface). So a FoundationModels pass over Vision's OCR text is an **interpreter of one reading**, not a second reader. When Vision reads `$38.20` as `$88.20`, the model is handed `88.20`, agrees, and the field fills with full confidence and no flag.

Requirement 5.18 is Dan's and is not being re-litigated. What follows delivers its **safety property**, never guess, leave the field empty on doubt, given a capability the PRD could not have known about. It splits by input shape, which is what 18b was written to measure.

- **Digital receipt with a text layer (PDF, HTML email body): two genuinely independent readers.** Text-layer extraction reads the embedded text; Vision OCR reads the **rasterized page pixels**. Different error profiles, real corroboration. Fill only where both agree (5.18 as written).
- **`RecognizeDocumentsRequest` is added as the structure reader** (verified at `Vision.swiftinterface:2219`, with `textRecognitionOptions` at 2260, `barcodeDetectionOptions` at 2261, and a `DocumentObservation` result at 2454 exposing tables, rows, columns and cells). It reads layout, tables and barcodes, which is directly what pulling a total out of a receipt needs, and it is the enabling API for PRD 10.5 line-item extraction if the readers prove good enough. **It is explicitly labelled NOT independent corroboration for a numeric field**: it is the same OCR family as the `topCandidates` path, so it cannot vote against it.
- **Photographed receipt, image only: filled whenever Vision is clear, exactly as PRD 18a says (Dan's decision, 2026-08-28).** Vision's own alternative candidates and per observation confidence are the ambiguity signal: a clear top candidate fills the field, a close second candidate (for instance `$88.20` against `$38.20`) leaves it empty with both shown. The cost is stated so nobody rediscovers it: those candidates come from the recognizer whose reading they judge (L70), so a confidently wrong read fills the field with no flag. Two things soften that without changing the rule:
   - **Arithmetic self-consistency is computed and logged on every receipt where the three numbers are readable** (subtotal, tax, total). It does not gate the fill. A fill whose arithmetic fails is logged as its own outcome, `filledButArithmeticFailed`, and shown on the filing screen as a warning beside the field, so the 18b measurement and the running 18b record can say how often a clear read was also a wrong one. Probe 4b still runs, and if it shows that rate is material it goes back to Dan as a change to this decision.
   - `singleReaderDecisive` means what its name says again: **one reader, clear, field filled.**
   - A FoundationModels pass may still run to **label** which text span is the amount, vendor or date, and is recorded as a labeller, never counted as corroboration on a numeric value.

**The agreement log records four outcomes, never two** (L11, L98):
1. `corroborated`, two independent readers agreed, field filled.
2. `singleReaderDecisive`, one reader only, clear, **field filled** (photographed receipts, PRD 18a).
2a. `filledButArithmeticFailed`, filled, but subtotal plus tax did not equal the total read, warning shown.
3. `disagreed` / `ambiguous`, field left empty, both readings shown.
4. `secondReaderUnavailable`, no second reader existed for this input shape, or the labeller failed. **Never folded into "disagreed."** Folding an unavailable reader into a disagreement is the L11 failure, and it is how a systemic reader outage disguises itself as ordinary noise (18a, L77).

The log records **counts and field names only, never receipt contents** (18a), and it is inside the 1.9 isolation floor. **Every entry also records the reader's identity: the Vision request revision and the OS build it ran on (PRD 18c, L25).** Vision changes under a system update with no build and no code change, and the regression it would produce reads as caution (more fields left empty), so a rate that cannot be pinned to the reader that produced it cannot show a regression at all. The 18b measurement records the same pair in its result.

**Decided 2026-08-28:** the disagreement between this section and PRD 18a about photographed receipts is closed in favour of 18a as written; see the bullet above.

**The measurement, with its pass marks written before the run (L246, L1, L249).** A number whose pass mark is set after it arrives gets rationalized. So the numbers below go in the issue body now, and **Dan's agreement or correction is recorded in that issue, quoted from what he actually said and carrying its own date**, before the run starts. They are two different measurements with two different meanings, and calling both "18b" would hide that:

| Measurement | What it is | Proposed pass mark |
| --- | --- | --- |
| **4a, digital** | genuine two-reader agreement rate, per field, over 20 to 30 real digital receipts | amount at least 90%, date at least 90%, vendor at least 80% agreement |
| **4b, photographed** | whether an independent second check exists at all, per candidate, over the same count of real photographed receipts | arithmetic self-consistency resolvable on at least 70% of receipts; barcode presence measured with no prior; any candidate that fills a field must produce **zero** confidently-wrong fills in the sample |

Tooling: port `scripts/measure-questionnaire-ocr.sh` and `scripts/verify-questionnaire-samples.sh` from Downbeat under the 0.4.6 discipline, which for these two means re-checking every sample-count threshold and confidence constant against what a receipt needs rather than what a questionnaire needed. Samples live in the machine-local `.receipt-samples` custody folder, never in the repository, and 0.1's never-staged check covers them. The script **refuses to measure until the samples verify by hash**, because a number taken from a file that has changed describes something else. Fixtures are measured from real receipts, never shaped so the rule fires (L48). **Output is counts and field names only** (0.1 privacy floor).

### 4.1 Thinnest vertical slice, one receipt from the Gmail label to a filed expense

Before the queue UI, duplicate flagging or the asset threshold exist. It crosses every layer that can fail: network, mailbox query, attachment decode, Vision, the blob write, the store write, and it is what makes the 18b number actionable against a real filing screen rather than a design document. **It runs under the 0.1 privacy floor: the slice reports ids, field names and outcomes, never a vendor, subject or body.**

### 4.2 Intake, in order, with the multi-step write made safe and the unit of work made honest

Who may call it and whose data it touches, stated explicitly: intake runs only from Ovation on Dan's Mac, authenticated as Dan, reading **only** the configured receipts label in **his** mailbox, and writing **only** to that label's messages (or to nothing at all under the ledger fallback). No other mailbox, no other label, no other account. The Gmail surface is confined to **one chokepoint type** with the scope required by each operation declared at that call site, and that type carries the 1.9 test refusal.

1. **Assert the label exists by id.** A missing, renamed or IMAP-hidden label returns zero messages, otherwise indistinguishable from a week in which Dan filed nothing (6.35, L98). A label that cannot be resolved is a named refusal, never a zero.
2. Attachments file as receipts; a body-only email has its body rendered and captured (5.16). Several real attachments become several unfiled receipts.
3. The signature-and-tracking-pixel filter (5.16a) is tested against the receipts it must **preserve**, not only the junk it must catch (L104). **Seen to fail:** a fixture of real small receipt images that must all survive the filter.
4. **Save each expense record and its blob, and verify each blob's SHA-256 reads back** (5.17). Order is the whole design, same as the booking queue.
5. **The unit of work is the ATTACHMENT and so is the unit of acknowledgement (L47, L66).** The earlier draft acknowledged the **message** whole: it saved "the expense record and its blob" (singular), moved the email, and appended the message id to a ledger keyed on that id. A message carrying three receipts where the second blob write fails would then be acknowledged whole: the ledger records the message id as consumed, the move takes it out of the Receipts label, and **the two receipts that never saved have no record that they were ever attempted**. It is unrecoverable in the way that matters: 5.30 forbids automatic deletion but nothing puts the message back into scope, and the intake query now excludes that message id for ever. The 5.16a signature filter makes it likelier rather than rarer, since a small real receipt image wrongly filtered is silently one of the members that never lands. So:
   - **the move and the ledger append happen only after EVERY attachment the message yielded has saved and read back by hash**
   - **on a partial failure, the attempt is recorded against each failed attachment**, in the Problems store with its own reason, under the same key the next bullet defines
   - **the attachment key is one Ovation can recompute, never one Gmail mints (PRD 22a, L186, L127):** message id **plus the receipt file's own SHA-256 plus the part index** (to separate two byte-identical attachments in one message). Gmail's attachment id is stored for fetching and is **never** part of the key, because its stability across separate fetches of the same message is not guaranteed, and a key that changes makes the record unfindable, which files a duplicate expense into a seven year tax record. **Proved before it is trusted:** fetch the same message twice and assert the key is identical, then assert the second run finds the record.
   - **the message stays in Receipts**, and re-intake is **idempotent per attachment**, not per message, so a re-run completes the members that failed without duplicating the ones that succeeded
   - **Seen to fail:** a three-attachment fixture where the second blob write throws, asserting **no ledger entry, no label move, and three named per-attachment records, two saved and one failed**
6. **Capture what a reversal would need, BEFORE the move (L97, hard constraint 5d).** The move is what removes the message from the Receipts label, so afterwards the information needed to put it back no longer exists anywhere unless it was captured first. Recording that a move happened and recording the message id is not the same as recording what to restore. So: **read and store the message's full label id set immediately before the move, in the same durable record that logs the move, and make the reversal restore that exact set** rather than reconstructing it. **Seen to fail:** a fixture where a message carries Receipts plus one unrelated user label, asserting the reversal restores **both**.
7. **Re-check scope at the moment of the write, not at the moment of the query (L157, hard constraint 5d).** Asserting the label exists at query time checks the **label**; the constraint asks that the **message** is in scope. Dan works in Spark on the same mailbox while Ovation runs, so a message can lose the Receipts label, or be moved by him, in the gap between listing and writing. So: **re-read the target message's current label set immediately before the move and refuse the move, loudly and by message id, if it no longer carries the Receipts label.** Use a conditional modify where the Gmail API offers one. **Seen to fail:** a double that strips the label between list and move, asserting the move is refused **by name**, not silently skipped.
8. Mark the message consumed, once step 5's condition is met: **move it to the Logged sublabel, nothing deleted, nothing archived** (PRD 17, 17a). This is the required route, not one of two. **The consumed-message ledger is written as well**, because the mailbox is an external system whose state is a request and not a fact (L127), and because a message moved by hand in Spark must not re-file. Assume it runs twice: intake is idempotent on the attachment key. The ledger is inside the 1.9 refusal. If the move fails after the expense saved, that is a Problems entry naming the message id and the ledger still holds the id, so the receipt is filed once and the empty-folder signal Dan relies on is reported as broken rather than faked.

### 4.3 The rest of the expense half

Categories with the enforced Schedule C map (built in Phase 2). Asset-threshold flag, configurable, **visible and overridable, a suggestion and not a determination** (5.20), with the per-item versus receipt-total caveat from 9.4 stated in the UI itself rather than only in the PRD. Duplicate flag on same vendor plus amount plus date, **flagged, never blocked or merged** (5.22). Expenses with no receipt allowed and marked (5.21).

**Every expense state is reachable from a surface, and a property test proves each lands in exactly one (PRD 22b, L45, L517).** The same discipline as the invoice list in 5.2, applied here because the states multiply faster: waiting in the unfiled queue, filed, no receipt, duplicate flagged, asset flagged, imported from QuickBooks with no image, read confidently, left empty for doubt, and **a per-attachment failure that has no expense row at all**. That last one is the dangerous case, because a record with no row and no screen exists only in the data, and filtered views are the only way Dan reaches any of these. **Seen to fail:** construct the per-attachment failure record with no expense row and assert the suite goes red naming it before the surface exists.

---

## Phase 5, invoicing, payments and sending (Dan's step 4)

Milestone: `Invoicing and sending`, plus `Shared Google sign in package` in the new package repo.

### 5.0 Extract the shared Google package (hard constraint 5a)

Sequencing, locked: Ovation's Phase 4 intake is written against **whole-file vendored copies** of Overture's proven Gmail and OAuth files, each carrying a header naming its origin repository, path and commit per 0.4.6, with the extraction issue filed **in the same commit as the copy**.

**The seven files are named, because "the `Gmail*.swift` set" drags in machinery Ovation has no use for.** `wc -l` over all `Gmail*.swift` plus `GoogleOAuth.swift` is **2230 lines across 14 files**. Ovation vendors **exactly these seven, 1114 lines**:

| File | Lines |
| --- | --- |
| `mac/Overture/Integration/GmailAuthManager.swift` | 424 |
| `mac/Overture/Integration/GmailMessage.swift` | 240 |
| `mac/Overture/Integration/GmailSender.swift` | 197 |
| `mac/Overture/Integration/GoogleOAuth.swift` | 136 |
| `mac/Overture/Integration/GmailCredentials.swift` | 57 |
| `mac/Overture/Integration/GmailConnection.swift` | 45 |
| `mac/Overture/Integration/GmailNetworking.swift` | 15 |

**Plus one predicate, not a whole file:** `wasSentByUser` and `labelIds(of:)` from `mac/Overture/Domain/ReplyDetection.swift:114, 133-136`, which is the fail-closed Sent test probe 6 and 5.10a both require (L181). It moves into the package as a shared definition so Ovation does not become a third implementation of it, and so Overture inherits the shared one at migration rather than keeping a fork.

**Explicitly NOT vendored**, because they are Overture's reply-classification and signature machinery: `GmailReplySearch.swift` (338), `GmailReplyChecker.swift` (178), `GmailThreadingRepair.swift` (178), `GmailSignatureHealth.swift` (174), `GmailSignatureService.swift` (111), `GmailSignatureStore.swift` (82), `GmailThreadHeaders.swift` (55), and the rest of `ReplyDetection.swift`.

The extraction happens here, at the start of Phase 5, because the scope set is now known (probe 5 and the 4.2 decision have both landed) and because Phase 5's sending is then written against the package from its first line. One extraction, not two, and the intake code moves rather than merges.

**The package makes the scope set an explicit per-consumer choice** (L503, L124). Overture today requests `gmail.send`, `gmail.readonly`, `gmail.settings.basic` and has never held `gmail.modify`. If the package carries a default scope list, Downbeat and Overture silently inherit mailbox-modify on their next migration, and an over-broad permission is invisible because the code never attempts what it is not meant to do, while a missing one fails loudly on the first run. So the package has **no default**: each consumer names its scopes, and a consumer that names none fails to compile.

**The package strips line breaks from every value that reaches a header (PRD 5.10b).** Overture's message builder writes the subject, the recipient and the sender name straight into the headers with no such stripping, and encodes the subject only when it contains non ASCII, so a plain ASCII subject carrying a line break becomes an additional header, for instance a second recipient. Harmless in Overture today, not in Ovation, whose subjects carry the client name and shoot name. The fix lives in the package so both apps get it. **Seen to fail:** a subject and a display name each carrying `\r\n` followed by a header line, asserting the built message has exactly the headers the reviewed screen showed and the injected line arrives as body text or is refused (L64).

**The package carries the test refusal (1.9), not just Ovation's copy.** The vendored originals have none: **zero of the 15 files carry `isRunningUnderTests` or any equivalent**. Putting the refusal only in Ovation would hand Downbeat and Overture an unrefusing client at migration.

Downbeat and Overture migrate later, behind tracked issues, per 5a. Do not refactor them now.

### 5.0a Settle the roster before the first send

**This is not an edge case, it is every invoice Ovation drafts in its first months.** Measured against the live export: the 20 bookings resolve to 3 distinct clientIds; of the 2 that have rows in `clients[]`, **neither carries `isTaxExempt` at all**; across the whole roster only 6 of 31 clients carry the key. PRD 5.5 requires a visible warning where the client's status was never recorded, and that warning is a detection that a required value is absent, so it must block the send it appears in (L67). Both halves are right, and together they make **all 19 backfilled invoices unsendable** unless something clears the condition.

So, before the first send: **a bulk roster pass.** One screen listing every client with no recorded tax status, cleared in one sitting rather than one invoice at a time. It reports the count it started with, so Dan can see it is 25 of 31 rather than an occasional nag. The L67 block stays exactly as written; what changes is that there is now a route out of it that is not per-invoice typing. Phase 6's backfill reports **how many of the 19 invoices it is holding and why**, by count, never by client name.

While there: **1 of 31 clients has no contract email**. **`contractEmail` is a non-optional `String` in the export model** (`mac/Overture/Domain/DownbeatExport.swift:12`), so that client carries an **empty string, not an absent key**. Both this roster pass and 5.38's refusal test for **empty after trimming whitespace**, never for nil. A nil check would find nothing and report the roster clean.

**Empty is not the only bad shape, and the roster pass lists all of them (PRD 38, 38a, 5a, L150, L257).** Measured 2026-08-27 against the live export, of 30 non empty contract email values **two cannot be parsed as a single address**: one is 22 characters containing a space and no `@` at all (human text sitting in an address field), and one is 70 characters carrying two comma separated addresses. Both pass "not empty after trimming". And **two clients share a single contract email**, which is what makes Phase 6's "unknown id matching exactly one contract email" refuse as a many-match (L521). So the validator is written against what the send path can consume, exactly one address (one `@`, no whitespace, no comma or semicolon, a dot in the domain), and each failure has its own named reason distinct from the empty case. The roster screen lists every client that is empty, unparseable, or **in conflict with another client**, with the count it started from. Ovation never splits a multi address value and never sends to both. Both measured values go in as fixtures, redacted to shape (L155). **Seen to fail:** the two fixture shapes are each refused by their own reason; the shared-email pair produces a conflict row on the roster screen and a many-match refusal in the Phase 6 matcher.

### 5.1 Thinnest vertical slice, one booking to one PDF in one client's inbox

Before the invoice list, the eight-way sort, filters, reminders or referral credits exist. This is the only thing in the plan that addresses the daily-friction criterion early.

### 5.2 The rest of half one

- Pricing at $250/hour from the record's real `startsAt`/`endsAt`, exact to one decimal, one hour minimum (5.3). One booking is one show is one invoice (7.8). **A duration that is zero, negative, or implausibly long is refused by name rather than priced** (PRD 3b, L50, L23): the two instants are parsed, checked, and only then reach arithmetic, so a nonsense pair can never become a well formed invoice. The plausibility ceiling is a named constant with its reason (a shoot does not run 24 hours), not a guess buried in a comparison. **And one comparison against reality (PRD 3a):** once real bookings carry times, the priced hours for two or three shoots Dan already invoiced through QuickBooks are compared against those invoices, because a wrong reading of what the instants mean would be invisible in every other test.
- Service types from a fixed list, extensible from inside an invoice (5.4).
- Tax: exempt clients skipped; a client whose status was never recorded gets a visible warning that **blocks the send** (5.5, L67), with 5.0a's bulk pass as the route out.
- Dated the shoot date, due 14 days later, overridable per client and per invoice, anchored to the stored invoice date and never recomputed from today (5.7, L74). Warn at send time when the due date is already close or past.
- The PDF (5.9) and the review screen showing **the exact PDF and the exact recipients** (5.10), so what Dan reviews is exactly what ships, including who it goes to (L64). Rendered and checked on both light and dark backgrounds (L69).
- **No usable contract email is a refusal naming the client and the field, tested as empty-after-trimming rather than nil. It never falls back to the other address** (5.38, L75).
- **Sent is only ever observed, and it is judged by Gmail's own committed state marker (5.10a, L181).** Two routes, each recorded on the invoice by name: Ovation sent it, or Ovation found a message establishing it in the Gmail Sent folder. Dan cannot assert it by hand.
   - **The derived route uses the shared `wasSentByUser` predicate from 5.0**: `SENT` present **and** `DRAFT` absent, **failing closed when `labelIds` is missing entirely** rather than treating absence as not-a-draft (L506). Ovation requests a message format that returns `labelIds` and refuses the match by name if a response does not carry it.
   - This is not optional caution. Gmail returns unsent drafts in the same collections as real mail, and every other attribute the match could use (the invoice number, a PDF attachment, a recipient on the invoice) is carried identically by a draft Dan started in Spark and abandoned. Since 5.10a forbids him from retracting Sent by hand, an abandoned draft would stamp the invoice Sent permanently and silently. overture#2918 is the same defect in the same mailbox.
   - **More than one invoice matching a number is a refusal, never a pick** (L521, and see 1.10 for why the importer is now blocked from creating that situation at all).
- Edit and resend keeps the history and the PDF of every version sent (5.11). Reminders are drafted for review; nothing is ever sent without Dan seeing it (5.12).
- Cancelling an invoice carrying payments asks what happened to the money and records a refund with its own date (5.13). **Under accrual, cancelling an invoice issued in a PRIOR tax year removes income from a return already filed, so Ovation refuses to cancel it silently**: it names the filed year the invoice belongs to and leaves the invoice standing until Dan has raised it with his accountant. **A "filed year" is any calendar year before the current one, decided by `BusinessCalendar` in America/New_York** (Dan's choice, 2026-08-28, over marking a year filed by hand). The known cost, stated so it is not rediscovered: between 1 January and the day the return actually goes in, a previous year invoice is refused even though nothing has been filed yet, and the refusal message says so ("this invoice belongs to 2026, which Ovation treats as filed; if the 2026 return has not gone in yet, cancel it with your accountant's agreement"). The refusal is a hard stop with no override control, because an override that is always available is a warning, which is the option Dan declined. **Seen to fail:** an invoice dated in the previous year, cancel attempted on 2 January with a pinned clock, assert the refusal names that year; the same invoice in the current year, assert the cancel proceeds; and the boundary, an invoice dated 31 December 23:30 New York cancelled on 1 January, refused.
- **Every outbound sentence gets a cold read, rendered, in the state that produces it, before this milestone closes (PRD 41a, L21).** The payment block on the PDF, the note to customer, the covering note on a send, and the reminder body are the only writing in the product with no reader on Dan's side, and Overture paid for exactly this omission. **The check that the rendered PDF's payment block is not truncated is derived from the rendered artifact**, never from the settings string it came from, since the current QuickBooks invoice truncates it mid word (PRD 9.16). Seen to fail: a payment block long enough to overflow its box, asserting the check goes red on the rendered page.
- Payments: any number per invoice, date, amount and method, **paid in full calculated and never typed** (5.14). Check gains a Cleared step; Zelle, Venmo and PayPal do not (5.15).
- **Assume it runs twice:** the send is PDF render, then Gmail send, then record what was sent. The Gmail send is the external side effect. Record the intent before sending, reconcile after, and never let a crash between the two produce either a sent-but-unrecorded invoice (invisible) or a recorded-but-unsent one (a lie). The reconciliation uses the same fail-closed derived-Sent predicate as 5.10a.

**The one list, and a proof that it holds everything (L45, L517).** The list is the only way to reach an invoice, and section 6's eight groups have not been shown to partition the state space. Two gaps are visible from the PRD itself. Groups 1, 3 and 6 are all keyed on the shoot date, but 5.2 allows an invoice created from scratch with **no booking behind it**, so a draft with no shoot date matches none of the eight: it is in the data and absent from the product. In the other direction, an overdue invoice carrying an uncleared check payment satisfies both group 2 and group 4, so it appears twice if the groups are filters rather than a first-match chain, and a count over the groups disagrees with the list. So:
- **Enumerate the invoice state space** (draft, sent, paid, cleared, cancelled, refunded, with and without a shoot date, with and without payments, before and after the due date) and add a **property test looping over every combination asserting each invoice lands in exactly ONE group**.
- **Add the group the enumeration shows is missing: drafts with no shoot date.** Placed with group 3 (should have been sent), since that is what needs Dan.
- Oldest first within each group.
- **Seen to fail:** construct a draft with no shoot date and assert the suite goes red naming it **before** the group exists.
- Search and filters (5.39), delete confirmation or undo (5.40), accessibility built into each control (5.41).

---

## Phase 6, the Downbeat queue consumer (Dan's step 5) and the one-time backfill

Milestone: `Downbeat booking queue consumer`. **Entry criterion: 0.2 step 4's end-to-end proof has landed**, that is, a genuine booking Dan committed has been observed to leave a file in the real `booking-queue/` directory.

- Drain: read a file, create the invoice, **save it, verify it reads back, and only then delete the file** (section 6). Saving first means a crash loses nothing.
- Append to the consumed-booking ledger from 1.11 in the same transaction as the invoice, so the redo path exists from the first drained record.
- **Version gate accepts any version at or above a minimum**, never an exact set (contract item 7, overture#3193). Refusing a payload whole because its version is unfamiliar produces empty data indistinguishable from the data being gone.
- **The minimum is DECLARED in a committed file, and a behaviour test ties that file to the real decoder, both in the same commit as the decoder itself** (downbeat#437, overture#3203, L27, L70). Downbeat's push gate `scripts/test-export-consumer-version.sh` refuses a push whose export version has outrun a consumer, and it is blind to Ovation today: `Integration/OvertureExport/CONTRACT.md` names Ovation as a second consumer and nothing enforces its floor. The file is `integration/downbeat-handoff-accepted-versions.json`, in the shape overture#3203 asks Overture to adopt (`{ "minimumVersion": N, "maximumVersion": null }`), so Downbeat ends up with **one** reader for both consumers rather than a second pattern matcher over Swift source. **The filename is a shared convention across three repositories, not Ovation's to pick alone**, and it was raised on overture#3203 (now p0) rather than left implicit: both consumers declare at `integration/downbeat-<surface>-accepted-versions.json`, `export` for Overture and `handoff` for Ovation, same keys, `maximumVersion: null` meaning no ceiling. If Overture settles on a different name or shape, this one follows it, because two names put Downbeat back to two readers and lose the entire point. **The declaration is worth nothing without the test**, which is the entire finding of overture#3203: a declared value nothing enforces is the prose problem moved one step along, and a test that reads the constant only confirms the file agrees with a number. So it is judged by BEHAVIOUR: take a committed fixture, rewrite its `version`, and assert the declared minimum decodes, one below it is refused by name, and a far higher version decodes.
- **Until that ships, Downbeat's gate reporting CANNOT MEASURE for Ovation is the correct answer, not a gap to paper over.** Declaring a minimum here before a decoder exists would turn that into a green pass comparing a hand typed number against no code at all, which is the failure the gate's three outcome design exists to prevent (L98, L11, L182). Ovation has no decoder, so no Downbeat version bump can break it; the risk begins at the moment this phase's decoder first reads a queue file, which is why the arm lands with the decoder and not before. Exit criteria, written into the Phase 6 issue the way 1.11's are: **(a)** the declaration file and its behaviour test land in the same commit as the decoder; **(b)** Downbeat's `DOWNBEAT_OVATION_REPO` arm lands against that file, keeps the same three outcomes, and is seen to fail on a real disagreement (L1); **(c)** `downbeat#437` closes in this milestone.
- **A malformed file, or one from a version Ovation does not understand, is refused loudly and named. It is never read as an empty file** (5.34). **A queue directory that does not exist is different from one that is empty, and both are different from a quiet week** (6.35).
- `isRerunOf` adds a note to the invoice that already exists rather than drafting a second one (contract item 3).
- Client identity matching on Downbeat's stable identifier. Unknown id matching exactly one contract email links automatically; a single name-only match asks once; no match creates a new client. **More than one match is its own refusal, never treated as no match** (section 6, L521), because the create-new path manufactures a duplicate identity that every later invoice, payment and referral credit then feeds. **An empty contract email is not a match candidate at all**, per 5.0a, since matching on empty string would link every such client to every other.
- Where Downbeat later sends a differing client detail, show both and ask, **once per differing value**, never repeatedly for the same one.

### The one-time backfill, priced from current data (L175)

The earlier draft read the Phase 0.3 snapshot and priced 19 invoices from it. That snapshot is a value read once, on 2026-08-27, describing bookings that run to 2027-06-13 and that live outside Ovation in Downbeat, where Dan edits them. Phase 6 is the last milestone, so those instants will be months stale when they are used, and they would be used to price real invoices at $250 per hour from `startsAt` and `endsAt` and send them to clients. A shoot whose time or venue changed in Downbeat after the snapshot re-exports correctly, so Downbeat is right and Ovation invoices from the old values, with nothing reporting it. Recording the snapshot as the source (L192) documents where the value came from; it does nothing about the value being wrong.

So:
1. **Read the CURRENT export first.** For a booking id present in it, **price from the current export**. The snapshot is used **only** for booking ids no longer present, the ones retention has swept.
2. Where the two disagree on times, venue or client, **surface both and ask**, which is the mechanism section 6 already specifies for differing client details.
3. **Assert the snapshot is never the source for a booking the current export still carries.**
4. **Refuse a snapshot row whose `clientId` does not resolve in that snapshot's own `clients[]`** (Phase 0.3). Named, refused, never a shell client, never silently priced.
5. Drain through the **same** consumer path with the same consumed-booking ledger, so a booking that later arrives via the queue is refused as already consumed.
6. Record the source on each invoice: current export, snapshot, or queue.
7. Report **counts only** (how many priced from current, how many from snapshot, how many held for tax status, how many refused and why). No client names.
8. **Seen to fail:** a fixture where the snapshot and the current export give different `startsAt` for the same id, asserting the invoice prices from the **current** one and the disagreement is named.

### Reconciliation, with the two sides genuinely independent (L70, L258)

The earlier draft's final bullet, "Ovation reports bookings received against invoices created and names any difference", is the plan's single most consequential guard **and it could not fail**. "Bookings received" could only be Ovation's consumed-booking ledger, and 1.11 writes that ledger in the same transaction as the invoice, so the two counts are equal by construction and the difference is arithmetically always zero. It would prove the ledger is self-consistent, never that every booking Downbeat committed was received. PRD success measure 1, "No shoot goes unbilled", would rest on a number that reads as proof.

So the "bookings received" side is derived independently of the ledger:

- **Side A (Ovation's own):** the consumed-booking ledger and the invoices.
- **Side B (independent of Ovation):** the booking ids present in Downbeat's **current v3 export**, plus the Phase 0.3 custody snapshot for ids retention has swept, plus **Downbeat's durable handoff-intended mark** from 1.11's cross-repo deliverable (b).
- **A booking committed BEFORE that mark shipped is its own outcome, never "never queued" (L223).** The mark cannot be backfilled, so every booking already committed is permanently outside it: measured 2026-08-29, the live export carries **19 bookings, every one with a future shoot date**, and none of them will ever carry a mark. A check that finds records by a marker they carry cannot see anything written before that marker existed, which is exactly the population this reconciliation has to account for. So the unmarked backlog is told apart by evidence the store already holds, the booking's own creation date against the date the mark shipped, and reported as **unmarkable, predates the mark** rather than folded in with genuine gaps. Downbeat records the shipping commit or date in the same change as the mark, per 1.11's deliverable (b), or the boundary is unknowable and every one of the 19 reads as a lost booking for ever.
- **A booking id present in side B with no Ovation invoice is named as a difference**, by id, never by client name.
- **Seen to fail:** plant a booking id in the export snapshot with no ledger entry and assert the reconciliation names it.

**And state what this cannot detect, in the same issue.** Until Downbeat's producer-side durable mark exists, a booking lost to a crash between Downbeat's `Booking` save and its queue write is invisible from both sides: Ovation acknowledges by deleting, so absent means both "consumed" and "never written" (L258, downbeat#432). That is precisely why 1.11's exit criterion (b) is a Downbeat deliverable filed in the same commit, and why the gap is recorded here rather than implied to be covered. Downbeat's never-retracting Problems entries for bookings it could not queue (CONTRACT item 5) are a second channel, but they live in the running app and Ovation cannot query them, so the reconciliation names them as a check Dan performs in Downbeat rather than pretending to cover them.

---

## Cross-cutting, throughout

- **6.32:** both queues checked on launch and every few minutes while running; a menu bar item shows what is waiting. **Nothing runs while the app is closed**, so Ovation says when it last looked rather than implying it is always watching (L51). The same surface carries Phase 2's staleness and zero-row notices, and every one of these conditions goes through the single launch presenter from 1.13.
- **5.33:** every time-taking action shows working, still alive, and failed as **visibly different states**. No bare indefinite spinner. A timeout converts an in-progress state into an actionable error.
- **5.30:** Ovation deletes nothing automatically, ever.
- **5.42:** stored totals are checked against the parts they are made of rather than trusted because they were written.
- **The 0.1 privacy floor applies to every script, probe and report in every phase.** Counts, ids, field names and booleans. Never a client, venue or vendor name, an email address, a subject or a body.
- **The 0.4.6 port discipline applies to every ported artifact**, not only the Gmail files: a header naming source repository, path and commit; a per-constant re-check in the porting issue; the sibling's open issues named; and an ancestry check that the recorded source commit is on the sibling's current main.
- **CORRECTED 2026-08-27: the porting issue carries a behavioural DIFF, not only a table of constants** (L501). The original discipline enumerated "every constant, threshold, path and exemption entry", which is scoped entirely to values, and the correction most likely to be missed is not a value at all. Verified today in `scripts/test-pre-push-hook.sh`, one of the artifacts this plan ports: it carries a fix dated 2026-08-27 whose whole content is a line of shell. Its `hook()` helper runs `env -u SKIP_TEST_RUN -u FORCE_TEST_RUN -u SKIP_STYLE_CHECK -u SKIP_TEST_CHECK -u SKIP_EXPORT_CONSUMER_CHECK` before invoking the hook, and its own comment records why: without it, under `SKIP_TEST_RUN=1` the harness went from 36 passed and 0 failed to 15 passed with 21 failed, because the documented one push escape hatch was silently switching off twenty one of the checks policing the very gate it escapes, at the exact moment somebody had already decided to push past a refusal (downbeat#433, L259). A constants table would not have carried that line across.
- So: the porting issue diffs the ported file against the sibling's current main and explains every behavioural difference, not only the numeric ones. `env -u SKIP_TEST_RUN -u FORCE_TEST_RUN -u SKIP_STYLE_CHECK -u SKIP_TEST_CHECK` is named as a required carry over for the pre-push harness specifically. Guard, seen to fail before it is trusted: run Ovation's ported harness under `SKIP_TEST_RUN=1` and assert its own passed and failed counts are unchanged from a clean environment.
- **Nested checkouts are excluded from every guard and every test glob, by name** (L234). Overture's `.claude/worktrees/agent-*` proves they exist in this estate, and a default recursive glob collects a second full copy of every source file.
- Every milestone ends with a `/production-ready` self-check scoped to the files it touched: error paths, data scoping, a failure-path test.
- **Milestones, per hard constraint 5c: one per feature, from the start.** `Year end tax export`, `QuickBooks migration import`, `Expenses and receipt intake`, `Invoicing and sending`, `Downbeat booking queue consumer`, `Shared Google sign in package` (in the new package repo), and `Ungrouped` for the genuinely standalone. Each names a feature, carries no punctuation, and is at most 8 words, per `~/.claude/skills/milestone/NAMING.md`. Every issue carries a priority label (`priority-p0` to `priority-p4`) and at least one category label. Each milestone's description carries its **frozen scope note**, listing the foundation issues assigned to it, so the enumerate-and-freeze discipline survives without a theme milestone.

---

## Cross-repository issues this plan files

Filed in the same change as the step that found each one, never left as a note in this plan.

| Issue | Repository | Why |
| --- | --- | --- |
| `mac/build-install.sh` records no `dirtyFiles`, so `installed-build.json` cannot say whether the installed bundle came from a clean tree | `danwright32/overture` | 0.2.0. Downbeat already records it, citing downbeat#424 |
| The doc comment on `AppStoreConfiguration.bookingHandoffQueueURL` asserts a throwaway in-memory store under Debug that the code does not provide | `danwright32/downbeat` | 0.2 step 5. `DownbeatApp.swift:39-44` gates in-memory on tests, never on Debug |
| Point `mac/scripts/run-tests-locked.sh` at `/tmp/xcodebuild-tests.lock` so the shared lock Downbeat's header claims is real | `danwright32/overture` | 0.4.5, subject to Dan's decision below |
| Downbeat writes a durable per-booking handoff-intended mark in the same save transaction as the `Booking` row | `danwright32/downbeat` | 1.11 exit criterion (b), the producer-side half of downbeat#432 |
| Gmail and OAuth migration onto the shared package | `danwright32/downbeat`, `danwright32/overture` | hard constraint 5a, tracked, not worked now |

---

## Guards that must be seen to fail before they are trusted (L1)

Every one has a planted defect written in the same commit as the guard.

| Guard | Planted defect that must turn it red |
| --- | --- |
| Overture checkout state report | a dirty tree (must route to Dan, never `checkout -f`); a non-main branch (must name it before stepping off) |
| Installed-consumer version check | an `installed-build.json` whose commit predates the gate fix (must BLOCK); one whose `provenance` is not `main` (must BLOCK); a missing one, and one missing a field it needs (must say CANNOT MEASURE, never pass) |
| Ported-artifact ancestry check | a port whose recorded source commit is on an unmerged branch (must report); a sibling repo not on the machine (CANNOT MEASURE, never pass) |
| Store schema guard | a foreign SQLite file at the store path |
| Test isolation floor | a test attempting a write to the real backup folder; a real mailbox move; a real ledger append; **an export run record append; a CSV write to the real output folder**. Each asserts the specific named refusal. Plus: zero run records, zero ledger entries and zero agreement-log lines after a full suite pass |
| Single-instance guard | a Debug Ovation running while the suite launches (the suite must still run) |
| Launch presenter | two launch conditions raised in one launch (both reachable and correctly identified); one condition replaced by another while showing (content changes with it) |
| Schedule C map completeness | a category added with no mapping |
| Export completeness (accrual) | an invoice dated 2026-12-31 23:30 America/New_York (in 2026, out of 2027); an invoice issued 2026-12-30 and paid 2027-01-15 (in the 2026 file only, payment shown on the row); a never-sent draft whose shoot has passed (out of the file, counted in the manifest) |
| Prior year cancel refusal | an invoice dated in a year marked filed, cancel attempted (refused, names the year); the same in an unfiled year (proceeds) |
| Backup credential exclusion | the Gmail token file planted in the staging set (archive refused or the guard goes red) |
| Backup set completeness | a backup missing the `custody/` folder or a ledger (verification fails naming it) |
| Single window | a second open request via the menu bar item and via a URL (one window results) |
| Header line break stripping | a subject and a display name each carrying `\r\n` plus a header line (headers unchanged from the reviewed screen) |
| Contract email validation | the 22 character no `@` shape and the 70 character two address shape (each refused by its own reason); two clients sharing one email (conflict row, and a many-match refusal in the matcher) |
| Duration refusal | zero, negative and 30 hour durations (each refused by name, never priced) |
| Attachment key stability | the same message fetched twice (identical key, second run finds the record) |
| Expense state partition | a per-attachment failure record with no expense row, red before the surface exists; every state combination lands in exactly one view |
| Rendered payment block | a payment block long enough to overflow its box (check goes red on the rendered page, not the settings string) |
| Reader identity | an agreement log entry with the Vision revision or OS build missing (refused, never written) |
| Export run record | a run that produced zero rows (records zero rows, not success); a run that threw (still writes a record) |
| Export staleness alarm | no completed run in 40 days (raised); a completed zero-row run yesterday (NOT raised, zero-row notice raised instead); an empty store (neither raised) |
| Invoice number allocator | an imported fixture carrying 1130, then an allocation (allocator refuses); an allocation of 1130, then an import of 1130 (**importer** refuses by name); two allocators held at the decision point |
| Importer revert | a payment recorded against an imported invoice, then a revert (refuses, names that invoice); import, revert, re-import at a bumped importer version (rows come back once) |
| Referral credit idempotency | cancel, refund, repay, asserting exactly one credit entry |
| Signature and pixel filter | a set of real small receipt images that must all survive |
| Attachment-level acknowledgement | a three-attachment message where the second blob write throws: no ledger entry, no label move, three named per-attachment records |
| Mailbox move reversal | a message carrying Receipts plus one unrelated user label, reversal restores both |
| Mailbox scope re-check | a double that strips the Receipts label between list and move, move refused by name |
| Derived Sent predicate | a **draft** carrying the invoice number, a PDF and the right recipient (must NOT establish Sent); a response with `labelIds` absent (named refusal, not a match) |
| Identity guard | a reserved name planted in a **gitignored** file under `.receipt-samples`; one planted in a tracked file; an unreadable store (refuses); a store and export yielding **zero needles** (refuses naming the emptiness, never reports clean) |
| Custody staging check | a `.quickbooks-samples` file added to the index |
| Business calendar | the whole suite re-run with `TZ` set by the test |
| Invoice list partition | a draft with no shoot date, red before the group exists; every state combination lands in exactly one group |
| Queue version gate | a v4 file (accepted), a v1 file (refused by name), a truncated file (refused, never read as empty); **the declared minimum edited to disagree with the decoder** (the behaviour test must go red, or the declaration is a number nothing enforces, L70) |
| Backfill freshness | snapshot and current export disagree on `startsAt`, prices from current and names the disagreement |
| Backfill client refusal | a snapshot row whose `clientId` is absent from that snapshot's `clients[]` |
| Queue reconciliation | a booking id in the export snapshot with no ledger entry, named as a difference |
| Cooperative pool detector | a planted `Task.detached` doing blocking work |
| Backup verification | a backup whose database opens but whose referenced blob is missing |
