#!/bin/bash
# Whether backstage has published a release newer than the one project.yml pins.
#
# ovation#576. Ovation pins the shared backstage package to ONE exact version,
# and an exact pin never looks for a newer one. 0.4.0 and 0.5.0 were both
# published while this app went on building 0.3.0, and nothing here said so.
# Moving the pin stays a person's decision, because a new version must arrive
# with this app's own suite run against it; noticing that one EXISTS should not
# depend on somebody remembering to look.
#
# WHY A SCHEDULED CHECK, AND NOT THE TWO THINGS THE ISSUE ASKED TO BE MEASURED
# FIRST. Measured 2026-09-29:
#
#   swift package    `swift package show-dependencies` in this repository says
#                    "Could not find Package.swift", and every other outdated
#                    report it has needs the same manifest. Ovation has none: the
#                    pin lives in project.yml and reaches SwiftPM only through the
#                    generated Xcode project. xcodebuild -resolvePackageDependencies
#                    resolves the pin; it never reports what is newer than it.
#   Dependabot       its Swift fetcher DOES read an Xcode project's
#                    Package.resolved (dependabot-core swift/file_fetcher.rb, read
#                    that day), so it could see the pin. But its answer is a pull
#                    request editing the GENERATED project, which xcodegen
#                    overwrites from project.yml on the next regeneration, so
#                    every one would be a change to the wrong file; and backstage
#                    is private, so it needs access to that repository granted
#                    separately. Not enabled on this repository to measure it
#                    further, because the first objection alone decides it.
#
# So this compares project.yml's pin with backstage's tags, and the workflow
# opens or updates ONE issue when they differ. Free: one short Linux job a day.
#
# RELEASES ARE TAGS OF THE FORM X.Y.Z, because a tag is what an exact pin
# resolves and backstage's release step cuts one per release. A pre-release or
# any other tag is not a version to move to and is ignored, never counted.
#
# IT READS AND PRINTS, AND CHANGES NOTHING: the name says it inspects (L206).
# What it prints is version numbers and tag names, which project.yml already
# publishes, never a line of any listing and never a credential (L222).
#
# WHEN THE LISTING FAILS, WHAT IT SAID IS PRINTED, MASKED (ovation#660). Its
# error stream was discarded, and the watcher failed every run from 2026-09-29
# saying only that it could not list, so the cause had to be inferred. The last
# attempt's error stream is printed now with every credential shape masked: the
# user part of a URL, the value of an Authorization or extraheader line, a
# GitHub token's shape, and the literal value of each token variable the job
# might carry. The log is public, so masking is done here, not left to GitHub's
# own secret masking, which knows only the secrets the step was handed.
#
# THE LISTING SENDS NO HEADER A CHECKOUT PERSISTED (ovation#660). actions/checkout
# leaves the workflow's own GITHUB_TOKEN in the checkout's git config as
# http.https://github.com/.extraheader, and git sends that header in place of
# the BACKSTAGE_READ_TOKEN that configure-private-package-access.sh puts in the
# URL. The workflow's token cannot see the private backstage repository, so the
# listing, run from inside the checkout, was refused on every run. Reproduced on
# Dan's Mac on 2026-10-08: a repository holding such a header was refused the
# listing that succeeded outside it, and an empty value for the key, which git
# documents as resetting the header list, made it succeed again. The workflow
# also checks out with persist-credentials: false; the reset here keeps the
# script right from any directory, whoever runs it.
#
# FOUR OUTCOMES, one per exit code, each with its own sentence (L11, L184):
#
#   0  the pin is the newest release backstage has published. Nothing to do
#   1  REFUSED: the pinned version is not a published tag at all, so a fresh
#      checkout cannot resolve it. Takes precedence over 3
#   2  CANNOT MEASURE: the pin or the tag listing could not be read, or the
#      listing held no release version. Never reported as current (L98)
#   3  backstage has published a release NEWER than the pin
#
# Seams, so its suite reaches no network and no real project (L2, L291):
#
#   OVATION_PROJECT_SPEC            the project.yml the pin is read from
#   OVATION_BACKSTAGE_TAGS_COMMAND  a command printing what `git ls-remote --tags`
#                                   prints. Defaults to asking github.com, which
#                                   in CI is authenticated by
#                                   scripts/configure-private-package-access.sh.
#                                   Its error stream is printed, masked, when
#                                   every attempt fails
#   OVATION_BACKSTAGE_FETCH_SLEEP   what waits between attempts, given the seconds
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="${OVATION_PROJECT_SPEC:-$REPO_ROOT/project.yml}"
TAGS_COMMAND="${OVATION_BACKSTAGE_TAGS_COMMAND:-}"
FETCH_SLEEP="${OVATION_BACKSTAGE_FETCH_SLEEP:-sleep}"
REMOTE="https://github.com/danwright32/backstage"
RELEASES="https://github.com/danwright32/backstage/releases/tag"

# NUMERIC, PER COMPONENT, for check-runner-xcode.sh's reason: 0.10.0 is newer
# than 0.9.0 and sorts earlier as text. Not `sort -V`, a GNU extension (L434).
version_gt() {
    local i ac bc
    local -a A B
    IFS=. read -r -a A <<< "$1"
    IFS=. read -r -a B <<< "$2"
    for (( i = 0; i < ${#A[@]} || i < ${#B[@]}; i++ )); do
        ac=$(( 10#${A[i]:-0} ))
        bc=$(( 10#${B[i]:-0} ))
        [ "$ac" -gt "$bc" ] && return 0
        [ "$ac" -lt "$bc" ] && return 1
    done
    return 1
}

if [ ! -f "$SPEC" ]; then
    echo "CANNOT MEASURE: there is no project.yml at $SPEC, so there is no pin to compare."
    exit 2
fi

# THE BackstageGoogle ENTRY ONLY. The first exactVersion in the file is
# ViewInspector's, so reading "the pin" as the first match would report the wrong
# package with complete confidence (L237). The entry ends at the next line
# indented no deeper than its own name; comments inside it are skipped.
entry="$(awk '
    /^  BackstageGoogle:[[:space:]]*$/ { inside = 1; next }
    inside && /^[[:space:]]*#/ { next }
    inside && /^ {0,2}[^[:space:]]/ { exit }
    inside { print }
' "$SPEC")"

if [ -z "$entry" ]; then
    echo "CANNOT MEASURE: $(basename "$SPEC") has no BackstageGoogle package entry, so"
    echo "    there is no backstage pin to compare. If the entry was renamed, this"
    echo "    check has to be told the new name rather than guessing one."
    exit 2
fi

pin="$(printf '%s\n' "$entry" | sed -nE 's/^[[:space:]]*exactVersion:[[:space:]]*"?([^"[:space:]]+)"?[[:space:]]*$/\1/p' | head -n 1)"
if ! [[ "$pin" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "CANNOT MEASURE: the BackstageGoogle entry in $(basename "$SPEC") carries no"
    echo "    exactVersion of the form 0.5.0, so there is no single pinned version to"
    echo "    compare. A range is not a pin (ovation#437), and none is guessed from one."
    exit 2
fi

# A FEW ATTEMPTS, NOT ONE, for check-runner-xcode.sh's reason (ovation#380): a
# single dropped request would otherwise read exactly like backstage being gone.
FETCH_TRIES=3
FETCH_ERR="$(mktemp "${TMPDIR:-/tmp}/backstage-ls-remote.XXXXXX")" || {
    echo "CANNOT MEASURE: could not create a temporary file for the listing's error stream."
    exit 2
}
trap 'rm -f "$FETCH_ERR"' EXIT

# EVERY CREDENTIAL SHAPE MASKED, read from standard input. The token variables'
# literal values go first, by bash's own substitution, so a value holding a
# character sed treats specially is still masked whole.
mask_credentials() {
    local text var value
    text="$(cat)"
    for var in BACKSTAGE_READ_TOKEN GITHUB_TOKEN GH_TOKEN; do
        value="${!var:-}"
        [ -n "$value" ] && text="${text//"$value"/***}"
    done
    printf '%s\n' "$text" | sed -E \
        -e 's#(://)[^/@[:space:]]+@#\1***@#g' \
        -e 's#([Aa][Uu][Tt][Hh][Oo][Rr][Ii][Zz][Aa][Tt][Ii][Oo][Nn]|[Ee][Xx][Tt][Rr][Aa][Hh][Ee][Aa][Dd][Ee][Rr])([^[:alnum:]]).*#\1\2***#' \
        -e 's#(gh[pousr]_|github_pat_)[A-Za-z0-9_]+#\1***#g'
}

listing=""
attempt=1
while [ "$attempt" -le "$FETCH_TRIES" ]; do
    if [ -n "$TAGS_COMMAND" ]; then
        listing="$("$TAGS_COMMAND" 2>"$FETCH_ERR")"; fetched=$?
    else
        # An empty extraheader resets any header a checkout persisted, and no
        # prompt is allowed to wait for a person who is not there (L110).
        listing="$(GIT_TERMINAL_PROMPT=0 git -c http.https://github.com/.extraheader= \
            ls-remote --tags "$REMOTE" 2>"$FETCH_ERR")"; fetched=$?
    fi
    [ "$fetched" -eq 0 ] && [ -n "$listing" ] && break
    listing=""
    [ "$attempt" -lt "$FETCH_TRIES" ] && "$FETCH_SLEEP" $((attempt * 10))
    attempt=$((attempt + 1))
done

if [ -z "$listing" ]; then
    echo "CANNOT MEASURE: could not list backstage's tags, after ${FETCH_TRIES} attempts."
    echo "    Nothing was compared. A listing that failed is not backstage having"
    echo "    published nothing (L98)."
    if [ -s "$FETCH_ERR" ]; then
        echo "    The last attempt said, with any credential masked:"
        tail -n 20 "$FETCH_ERR" | mask_credentials | sed 's/^/        /'
    else
        echo "    The last attempt printed nothing on its error stream."
    fi
    echo "    In CI the repository is read with BACKSTAGE_READ_TOKEN, so a refused"
    echo "    listing there means that token has expired or lost access to"
    echo "    danwright32/backstage, or another credential was sent in its place."
    exit 2
fi

# refs/tags/<name>, with an annotated tag's peeled ^{} line folded onto its name,
# and only X.Y.Z kept.
releases="$(printf '%s\n' "$listing" \
    | sed -nE 's#^[0-9a-fA-F]+[[:space:]]+refs/tags/([^[:space:]^]+)(\^\{\})?[[:space:]]*$#\1#p' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -u)"

if [ -z "$releases" ]; then
    echo "CANNOT MEASURE: backstage's tags were listed and none is a release version"
    echo "    like 0.5.0, so there is no newest release to compare the pin with."
    exit 2
fi

newer=""
holds_pin="no"
while read -r candidate; do
    [ "$candidate" = "$pin" ] && holds_pin="yes"
    version_gt "$candidate" "$pin" && newer="${newer}${candidate}
"
done <<< "$releases"

if [ "$holds_pin" = "no" ]; then
    echo "REFUSED: project.yml pins backstage ${pin}, and backstage has published no tag ${pin}."
    echo "    A fresh checkout cannot resolve it, so CI's next build fails to fetch the"
    echo "    package. Either the tag was removed or the pin was mistyped."
    echo "    backstage's releases are:"
    printf '%s\n' "$releases" | sed 's/^/        /'
    exit 1
fi

if [ -z "$newer" ]; then
    echo "backstage ${pin} is the newest release published, so the pin is current."
    exit 0
fi

# ORDERED NUMERICALLY, oldest first, so they read in the order to review them.
ordered=""
while [ -n "$newer" ]; do
    lowest=""
    while read -r v; do
        [ -n "$v" ] || continue
        if [ -z "$lowest" ] || version_gt "$lowest" "$v"; then lowest="$v"; fi
    done <<< "$newer"
    ordered="${ordered}${lowest}
"
    newer="$(printf '%s' "$newer" | grep -vxF -- "$lowest")"
    [ -z "$newer" ] || newer="${newer}
"
done
newest="$(printf '%s' "$ordered" | tail -n 1)"

echo "backstage has published ${newest}, newer than the ${pin} project.yml pins."
echo "    Releases since the pin, each with notes to read before moving:"
printf '%s' "$ordered" | while read -r v; do echo "        ${v}  ${RELEASES}/${v}"; done
echo "    Moving is a person's decision: change exactVersion in project.yml,"
echo "    regenerate the project, and commit the Package.resolved the build writes,"
echo "    with the full suite run against the new version."
exit 3
