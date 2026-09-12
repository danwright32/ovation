# Proving the backup folder still works after a relaunch

ovation#232. Ten minutes, done once, and then recorded so nobody has to wonder
again.

## Why this needs a person

Ovation copies everything it holds into a folder you choose. Outside the Mac
sandbox, which Ovation deliberately runs outside of, permission to write into a
folder you picked is granted by macOS to the **app's identity**, not to anything
Ovation stores. That is the whole reason ovation#9 made the signing identity
stable before any of this was built: an app whose identity changes on every
rebuild gets asked for permission again every time, which is a feature you stop
trusting.

No test here can prove that. A test can prove Ovation says the right thing when
a write is refused, and it does. What it cannot do is install a signed build,
quit it, open it again, and see that the backup still lands. That needs you.

## What you do

**1. Install the current build.**

```
bash scripts/build-install.sh
```

**2. Open Ovation, and open Settings with Command and comma.**

Choose a backup folder in the Backups section. Pick somewhere ordinary for this
first check, not the Synology: the network share has its own failure modes and
this check is about the permission, not the network.

**3. Quit Ovation completely, with Command and Q.**

Not just closing the window. The point is a fresh launch.

**4. Open Ovation again, and look at the folder you chose.**

There should be a folder inside it whose name starts with `Ovation-backup-`
and carries today's date. If you opened Ovation twice in one day, there will
still be only one: it backs up once a day.

**5. Tell the repository what happened.**

If the backup is there:

```
bash scripts/record-backup-grant-check.sh survived
```

If it is not, or Ovation says it could not write:

```
bash scripts/record-backup-grant-check.sh lapsed
```

## What the record is for

`scripts/check-backup-grant.sh` reads it, and `scripts/check-preconditions.sh`
runs that on demand. Until you have run step 5, it answers CANNOT MEASURE and
says so out loud, because "he checked and it survived" and "nobody has ever run
it" are otherwise the same state to every later session.

The record holds a date and a verdict and nothing else. It does not record which
folder you chose: this repository is public on purpose, and where your records
are copied to is your business.

## If it says the grant lapsed

That is the failure the stable signing identity exists to prevent, and it means
backups would stop silently. Say so and it gets its own issue: the likely causes
are the build being signed differently from the one that was granted, or the app
having been moved, and both are answerable.
