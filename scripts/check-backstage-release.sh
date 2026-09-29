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
#                                   scripts/configure-private-package-access.sh
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
listing=""
attempt=1
while [ "$attempt" -le "$FETCH_TRIES" ]; do
    if [ -n "$TAGS_COMMAND" ]; then
        listing="$("$TAGS_COMMAND" 2>/dev/null)"; fetched=$?
    else
        listing="$(git ls-remote --tags "$REMOTE" 2>/dev/null)"; fetched=$?
    fi
    [ "$fetched" -eq 0 ] && [ -n "$listing" ] && break
    listing=""
    [ "$attempt" -lt "$FETCH_TRIES" ] && "$FETCH_SLEEP" $((attempt * 10))
    attempt=$((attempt + 1))
done

if [ -z "$listing" ]; then
    echo "CANNOT MEASURE: could not list backstage's tags, after ${FETCH_TRIES} attempts."
    echo "    Nothing was compared. A listing that failed is not backstage having"
    echo "    published nothing (L98). In CI the repository is read with"
    echo "    BACKSTAGE_READ_TOKEN, so a refused listing there usually means that"
    echo "    token has expired or lost access to danwright32/backstage."
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
