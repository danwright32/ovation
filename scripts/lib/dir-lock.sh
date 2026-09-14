#!/bin/bash
# The directory lock the hosted suite and the regenerator take, and the ONE place
# its owner line is written and read. The pure suite has not taken it since
# ovation#271; lib/ensure-xcode-project.sh is how a regeneration sees one
# (ovation#299).
#
# ovation#202. Two things take it now. `run-tests.sh`, whose Xcode phase READS
# the generated project, has always taken it. `regenerate-xcode-project.sh`
# REWRITES that project, and took nothing: the operation that regenerates a
# shared artifact is routinely the one outside the locking every reader takes,
# because regenerating reads as a rare setup step rather than as work (L453).
#
# IT HAPPENED. On 2026-09-10 `rm -rf Ovation.xcodeproj && xcodegen generate` ran
# while `run-tests.sh` was in its Xcode phase. It survived, and survival is the
# evidence of luck rather than of safety.
#
# THE OWNER LINE IS THE REASON THIS IS SHARED CODE rather than two copies. Both
# sides write it and both sides read it, and a format that drifts leaves a
# refusal naming nobody. Sharing the data while copying the logic beside it is
# not consolidation (L370).
#
# A MKDIR LOCK AND NOT `flock`, because that is what the runner already uses and
# what Downbeat's runner uses, and a lock must be the one the READERS take or it
# protects nothing. The cost, stated because it is real: the kernel does not
# release a mkdir lock when its holder dies, which is why the runner carries a
# timeout and why the regenerator REFUSES rather than waits.
#
# A THIRD USER TAKES A DIFFERENT LOCK THROUGH THE SAME TWO FUNCTIONS.
# `ensure-xcode-project.sh` takes a create lock scoped to the project path
# (ovation#207), and it writes and reads its owner line here for the same reason
# the other two do: a waiting run claims a lock whose owner pid is no longer
# running, so the format is load bearing rather than descriptive.
#
# Sourced, never run on its own.

# The owner line, read ONCE, or nothing when there is none to read.
#
# ONE READ, NOT A CHECK AND THEN A READ (ovation#303). This asked whether the
# owner file existed and then read it in a second process, so a holder letting go
# between the two was described as `held by ` with nothing after it: a holder
# nobody ever was. The runner counts changes of holder, and counted that one.
dir_lock_owner() {
    head -1 "$1/owner" 2>/dev/null
}

# The lock's identity: the directory a holder MADE, as its inode number, or
# nothing when the lock is free.
#
# NOT ITS OWNER LINE (ovation#303). The line is written AFTER the mkdir and
# removed with the directory, so a holder is unnamed for a moment at both ends of
# its hold, and Downbeat's own runner never names itself at all. The directory is
# the one thing that exists for exactly as long as the hold. `ls -di` rather than
# stat, whose flags differ between macOS and Linux (L434).
dir_lock_identity() {
    ls -di "$1" 2>/dev/null | awk '{ print $1 }'
}

# What is holding the lock, in words, or that it is free, from an owner line
# already read. The runner reads the line once per look and both counts and
# describes from that one read, so the words and the count cannot disagree.
dir_lock_words() {
    local lock="$1" owner="$2"
    if [ -n "${owner}" ]; then
        printf 'held by %s' "${owner}"
    elif [ -d "${lock}" ]; then
        printf 'held by a run that left no owner file'
    else
        printf 'free'
    fi
}

# What is holding the lock, in words, or that it is free.
dir_lock_describe() {
    dir_lock_words "$1" "$(dir_lock_owner "$1")"
}

# Takes it, non blocking. 0 when taken, 1 when somebody else has it.
#
# THE OWNER LINE IS BEST EFFORT and its failure is not a reason to give the lock
# back: the lock IS the mkdir, and a holder that could not name itself still
# holds it. `dir_lock_describe` has its own words for that case rather than
# reporting the lock free, which would be the one answer that matters being
# indistinguishable from the safe one (L98).
dir_lock_take() {
    local lock="$1" who="$2" pid="$3"
    mkdir "${lock}" 2>/dev/null || return 1
    printf '%s:%s\n' "${who}" "${pid}" > "${lock}/owner" 2>/dev/null || true
    return 0
}
