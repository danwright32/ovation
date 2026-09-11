#!/bin/bash
# The directory lock every xcodebuild run in this repository takes, and the ONE
# place its owner line is written and read.
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
# Sourced, never run on its own.

# What is holding the lock, in words, or that it is free.
dir_lock_describe() {
    local lock="$1"
    if [ -f "${lock}/owner" ]; then
        printf 'held by %s' "$(head -1 "${lock}/owner" 2>/dev/null)"
    elif [ -d "${lock}" ]; then
        printf 'held by a run that left no owner file'
    else
        printf 'free'
    fi
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
