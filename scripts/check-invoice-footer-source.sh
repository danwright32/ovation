#!/bin/bash
# Whether anything that DRAWS or SENDS an invoice still reads the shipped footer
# text instead of what Dan wrote in Settings.
#
# ovation#319, PRD 9 and 41a. The three sentences at the foot of an invoice go to
# clients under Dan's name, and they used to be fixed in the source: outbound copy
# that can only change through a code change is copy that does not get changed.
# They now live in `InvoiceFooterSetting`, and `InvoiceFooter.fixed` survives only
# as what a field he has never written falls back to.
#
# THE DEFECT THIS EXISTS TO CATCH IS SILENT AND LOOKS RIGHT. A page built from
# `.fixed` renders perfectly, says something plausible, and goes out to a real
# client having quietly ignored everything Dan typed. Nothing about the output
# says which of the two it used, and the settings pane would go on showing his
# text (L98, L144).
#
# IT IS A SCAN RATHER THAN A TYPE, and that is a deliberate trade. Making `fixed`
# private to the setting would be stronger, and it cannot be: the suites build
# pages from a known footer on purpose, and so does the review sample world. What
# is forbidden is the APP's drawing and sending paths reading it, so the rule is
# about WHERE the reference is, which no compiler can express (L621 says a rule
# each call site must opt into cannot be enforced by a scan, so this enumerates
# the files rather than trusting each one to behave).
#
# ALLOWED, EACH FOR A WRITTEN REASON (L233, L129):
#
#   Ovation/Document/InvoiceDocument.swift   declares it, and its own fallback
#   Ovation/Document/InvoiceFooterSetting.swift  serves it for an unwritten field
#   Ovation/Document/ReviewSampleWorld.swift the sample world, which exists to
#                                            draw a page from a KNOWN footer and
#                                            never sends anything
#
# Anything else under Ovation/ is refused by name.
#
# Seam, so the suite drives it over a staged tree rather than this repository
# (L2): OVATION_REPO_ROOT.
set -uo pipefail

REPO_ROOT="${OVATION_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SOURCE_DIR="$REPO_ROOT/Ovation"

# DERIVED FROM ONE LIST, so the message and the check cannot name different files
# (L70). Paths are relative to the source directory.
ALLOWED=(
    "Document/InvoiceDocument.swift"
    "Document/InvoiceFooterSetting.swift"
    "Document/ReviewSampleWorld.swift"
)

if [ ! -d "$SOURCE_DIR" ]; then
    echo "CANNOT MEASURE: there is no source directory at $SOURCE_DIR."
    echo "    Nothing was scanned, which is not the same as nothing being wrong (L98)."
    exit 2
fi

is_allowed() {
    local candidate="$1" allowed
    for allowed in "${ALLOWED[@]}"; do  # never empty: ALLOWED is a literal list above
        [ "$candidate" = "$allowed" ] && return 0
    done
    return 1
}

# EVERY SWIFT FILE UNDER THE APP, enumerated from the tree rather than from a list
# somebody maintains beside it: a file missing from such a list is exempt from the
# check meant to catch it (L96).
offenders=""
scanned=0
while IFS= read -r file; do
    scanned=$((scanned + 1))
    relative="${file#"$SOURCE_DIR"/}"
    is_allowed "$relative" && continue
    # `InvoiceFooter.fixed` and a bare `.fixed` where the type is already known are
    # the same reference, so both are matched. A comment naming it is matched too,
    # and that is the safe direction: a comment saying the page uses the shipped
    # text is either wrong or describes the defect (L103).
    if grep -qE '(InvoiceFooter\.fixed|footer:[[:space:]]*\.fixed)' "$file"; then
        offenders="${offenders}${relative}"$'\n'
    fi
done < <(find "$SOURCE_DIR" -name '*.swift' -type f)

if [ "$scanned" -eq 0 ]; then
    echo "CANNOT MEASURE: no Swift files were found under $SOURCE_DIR."
    echo "    A scan that examined nothing is not a clean scan (L98)."
    exit 2
fi

if [ -n "$offenders" ]; then
    echo "REFUSED: the shipped footer text is read where the invoice is drawn or sent."
    printf '%s' "$offenders" | sed 's/^/        /'
    echo "    InvoiceFooter.fixed is what an unwritten field falls back to, and nothing"
    echo "    else. A page built from it ignores everything Dan typed in Settings and"
    echo "    still looks right, so this cannot be left to be noticed later (ovation#319)."
    echo "    Read the footer from InvoiceFooterSetting instead, or, if this file really"
    echo "    does need a known footer, add it to ALLOWED in this script with its reason."
    exit 1
fi

echo "OK: $scanned Swift file(s) scanned, and the shipped footer text is read only where it may be."
printf '%s\n' "${ALLOWED[@]}" | sed 's/^/        /'  # never empty: ALLOWED is a literal list above
exit 0
