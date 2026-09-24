#!/bin/bash
# The review sheet's samples must not be in the app Dan runs.
#
# ovation#318 B5. The sheet is judged over invented invoices, because not one of the
# 31 real clients has a genuine override and nothing in the store is past its due
# date on purpose. Those samples are `#if DEBUG`, and that is a claim nobody checks:
# it holds until somebody moves a declaration out of the guarded file, and the
# failure is invented client names and addresses sitting inside the installed app
# (L3, L535).
#
# THE TERMS ARE READ FROM THE SOURCES, never from a list beside them, so a sample
# added tomorrow is covered without anybody remembering to add it (L41, L96).
#
# IT IS PROVED ON THE DEBUG PRODUCT FIRST. A scan whose terms are wrong finds
# nothing in either build and calls the Release one clean, which is the reassuring
# direction of being wrong (L159, L178). So every term must be FOUND in the Debug
# product before their absence from Release means anything.
#
# THREE ANSWERS, KEPT APART (L11, L98):
#   0  the Release product holds none of them, and Debug holds them all.
#   1  a sample reached the Release product, or the scan could not be proved.
#   2  there is nothing to measure: a product was never built here.
set -uo pipefail
# ovation#399: every library is loaded through require_lib, which refuses by name
# rather than carrying on without it. See scripts/lib/require.sh.
. "$(dirname "${BASH_SOURCE[0]}")/lib/require.sh" 2>/dev/null || { echo "REFUSED: scripts/lib/require.sh is missing, so nothing was checked." >&2; exit 2; }
# THE TREE IT JUDGES IS A SEAM, the way every other check here has one, so the
# suite can stage a tree rather than scan the real one (L2, L291). The default is
# this script's own checkout.
REPO_ROOT="${OVATION_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "${REPO_ROOT}" || exit 1

SOURCES=("Ovation/Document/ReviewSamples.swift" "Ovation/Document/ReviewSampleWorld.swift")

missing=""
for source in "${SOURCES[@]}"; do  # never empty: SOURCES is a literal of two files
    [ -f "${source}" ] || missing="${missing}${source} "
done
if [ -n "${missing}" ]; then
    echo "The sample sources are not here: ${missing% }" >&2
    echo "Nothing was scanned for, so this cannot say the Release product is clean." >&2
    exit 1
fi

# Every quoted NAME or SENTENCE in the sample sources: at least two words, or an
# address. A single word ("Ordinary") is a word any build holds for its own reasons,
# and scanning for one would refuse every Release product for something that is not
# a sample at all (L104).
# WITH WHERE EACH ONE IS DECLARED, because what this prints goes to a CI log of a
# PUBLIC repository and the terms come out of source files. They are meant to be
# invented, and a check that ECHOES them publishes whatever somebody actually put
# there; naming the file and line identifies the term to whoever has to fix it and
# carries nothing (L222, docs/PRIVACY-FLOOR.md).
located="$(grep -noE '"[^"]{8,}"' ${SOURCES[@]+"${SOURCES[@]}"} \
    | sed 's/"$//' \
    | sed 's/:\([0-9][0-9]*\):"/\t\1\t/' \
    | awk -F'\t' 'NF == 3 && $3 ~ /[A-Za-z]/ && $3 ~ /[ @]/ { print }' \
    | sort -u -t$'\t' -k3)"
terms="$(printf '%s\n' "${located}" | awk -F'\t' 'NF == 3 { print $3 }' | sort -u)"
count="$(printf '%s\n' "${terms}" | grep -c .)"
if [ "${count}" -eq 0 ]; then
    echo "No sample terms could be read from ${SOURCES[*]}, so a scan of the Release" >&2
    echo "product proves nothing about whether the samples reached it." >&2
    exit 1
fi

PRODUCTS="${OVATION_PRODUCTS_DIR:-}"
if [ -z "${PRODUCTS}" ]; then
    # shellcheck source=lib/built-product.sh
    require_lib "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/built-product.sh"
    debug_app="$(built_product_path Debug)/Ovation.app"
    release_app="$(built_product_path Release)/Ovation.app"
else
    debug_app="${PRODUCTS}/Debug/Ovation.app"
    release_app="${PRODUCTS}/Release/Ovation.app"
fi

debug_binary="${debug_app}/Contents/MacOS/Ovation"
release_binary="${release_app}/Contents/MacOS/Ovation"

if [ ! -f "${debug_binary}" ] || [ ! -f "${release_binary}" ]; then
    echo "CANNOT MEASURE: both products have to be built for this to mean anything."
    echo "    Debug:   ${debug_binary}"
    echo "    Release: ${release_binary}"
    echo "    Build them with: bash scripts/build-products.sh"
    echo "    Nothing was scanned. This is not a pass."
    exit 2
fi

# THE CONTROL FIRST. Terms absent from the Debug product are terms this scan cannot
# find anywhere, so their absence from Release says nothing at all.
unseen=""
while IFS= read -r term; do
    [ -n "${term}" ] || continue
    grep -qF "${term}" "${debug_binary}" || unseen="${unseen}${term}
"
done <<< "${terms}"

if [ -n "${unseen}" ]; then
    echo "$(printf '%s' "${unseen}" | grep -c .) sample term(s) are not in the Debug" >&2
    echo "product either, so scanning the Release product for them proves nothing." >&2
    echo "They are declared at:" >&2
    printf '%s' "${unseen}" | while IFS= read -r term; do
        [ -n "${term}" ] || continue
        printf '%s\n' "${located}" | awk -F'\t' -v t="${term}" '$3 == t { print "    " $1 " line " $2 }' >&2
    done
    echo "Either the samples changed and this is reading the wrong strings, or the" >&2
    echo "Debug product is stale. Build both: bash scripts/build-products.sh" >&2
    exit 1
fi

found=""
while IFS= read -r term; do
    [ -n "${term}" ] || continue
    grep -qF "${term}" "${release_binary}" && found="${found}${term}
"
done <<< "${terms}"

if [ -n "${found}" ]; then
    echo "$(printf '%s' "${found}" | grep -c .) sample term(s) reached the Release" >&2
    echo "product, which is the app Dan runs. They are declared at:" >&2
    printf '%s' "${found}" | while IFS= read -r term; do
        [ -n "${term}" ] || continue
        printf '%s\n' "${located}" | awk -F'\t' -v t="${term}" '$3 == t { print "    " $1 " line " $2 }' >&2
    done
    echo "The term itself is not printed here: this runs in CI of a public repository" >&2
    echo "and the terms come out of source files (L222)." >&2
    echo "Whatever holds them is outside the #if DEBUG that is supposed to." >&2
    exit 1
fi

echo "OK: ${count} sample term(s), every one in the Debug product and none in Release."
