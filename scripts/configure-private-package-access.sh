#!/bin/bash
# Let SwiftPM resolve the private backstage package, and REFUSE BY NAME when it
# cannot.
#
# ovation#424, ovation#427. `danwright32/backstage` is private, and every fresh
# checkout, CI run and project regeneration performs a live SPM resolution
# against github.com, because `.gitignore` excludes `Ovation.xcodeproj/` and the
# resolved file lives inside it (ovation#421). Ovation's own repository token has
# no access to backstage, so without a credential the resolve fails.
#
# WHY IT IS A SCRIPT AND NOT THREE LINES IN THE WORKFLOW. The failure it exists
# to prevent is not "the resolve failed", it is "the resolve failed and the
# message was about a module". A missing credential surfaces from xcodebuild as
# `no such module` or a generic resolution error, which names the code rather
# than the thing that is actually absent, and sends whoever reads it to the wrong
# place (L11, L111). This refuses first, by name, before anything tries.
#
# IT NEVER PRINTS THE TOKEN, and that is structural rather than careful: the
# value is read from the environment and written straight into git's config, and
# nothing in this file interpolates it into a message, a command echo or an
# error. Its output goes into CI logs by a route no file scanner inspects (L222).
#
# IT REFUSES TO TOUCH A DEVELOPER MACHINE. Run outside CI it does nothing and
# says so, because configuring a credential into a person's global git config is
# a change to their machine that nobody asked for, and Dan's Mac already resolves
# backstage through the credentials he signed in with. `OVATION_ALLOW_LOCAL_GIT_AUTH=1`
# is the deliberate override, for a machine that genuinely needs it.
#
# WHAT IT REWRITES, said exactly: it maps `https://github.com/` to an
# authenticated form for the duration of the job. That covers every github.com
# fetch, ViewInspector's included, which is intended: a public fetch over an
# authenticated URL is the same fetch.
set -euo pipefail

TOKEN="${BACKSTAGE_READ_TOKEN:-}"

if [ -z "${CI:-}" ] && [ -z "${OVATION_ALLOW_LOCAL_GIT_AUTH:-}" ]; then
    echo "SKIPPED: not running in CI, so nothing was written to this machine's git config."
    echo "         Dan's Mac resolves backstage through the credentials he is signed in"
    echo "         with. Set OVATION_ALLOW_LOCAL_GIT_AUTH=1 to override deliberately."
    exit 0
fi

if [ -z "$TOKEN" ]; then
    echo "REFUSED: BACKSTAGE_READ_TOKEN is not set, so SwiftPM cannot resolve" >&2
    echo "         https://github.com/danwright32/backstage, which is PRIVATE." >&2
    echo "" >&2
    echo "         This is a MISSING CREDENTIAL, not a missing module. Without this" >&2
    echo "         the build fails later with an error naming BackstageGoogle, which" >&2
    echo "         sends you to the code rather than to the secret." >&2
    echo "" >&2
    echo "         Fix: add a fine grained token with contents:read on" >&2
    echo "         danwright32/backstage as the repository secret BACKSTAGE_READ_TOKEN," >&2
    echo "         and give the job that needs it" >&2
    echo "           env:" >&2
    echo "             BACKSTAGE_READ_TOKEN: \${{ secrets.BACKSTAGE_READ_TOKEN }}" >&2
    exit 1
fi

# WRITTEN WITH `git config`, never by echoing a URL into a file, so the value is
# passed as an argument to one command and appears in no log, no heredoc and no
# shell trace.
git config --global \
    "url.https://x-access-token:${TOKEN}@github.com/.insteadOf" \
    "https://github.com/"

echo "OK: github.com fetches are authenticated for this job, so the private"
echo "    backstage package can resolve. The token itself was never printed."
