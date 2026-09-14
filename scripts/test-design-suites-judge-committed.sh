#!/bin/bash
# Each rendering check's suite runs it against the COMMITTED design files, and
# this proves it by damaging them (ovation#220).
#
# The six rendering checks are not in the push gate, and the reason recorded for
# that in scripts/lib/script-roles.tsv is that every push already runs each of
# them against the committed files through its sibling suite. That was checked
# by hand on 2026-09-11 and asserted by nothing. If a suite were narrowed to
# planted fixtures only, every check would stay green, the inventory would go on
# giving that reason, and a push would stop judging docs/design with nothing
# able to say so. A constraint recorded only as a comment is enforced by nothing
# (L407).
#
# IT IS ASSERTED BY BEHAVIOUR, NEVER BY READING THE SUITES. Three of the six
# reach the committed record by letting OVATION_DESIGN_ROOT default, so they
# never mention docs/design at all and a search of their text would report them
# as not covering it. So each case copies the tree, damages ONE committed design
# file in the copy in a way its check refuses, runs that suite from the copy with
# the root left to default, and requires the suite to go red, and red on the
# assertion about the COMMITTED record rather than on some other one: a suite
# that failed because the copy lacked a file would be red too (L154).
#
# THE COPY IS PROVED COMPLETE, not assumed. Two suites that read the record by
# default are run on an UNDAMAGED copy made the same way and must pass, so a red
# above is the damage and not the copy (L159).
#
# AND THE JUDGEMENT IS SEEN TO FAIL. A stand in suite that passes whatever the
# design files hold is run through the same judgement and must be told apart
# from the six (L1).
#
# IT COSTS WHAT THE SIX SUITES COST AND A LITTLE MORE, 38 seconds of wall clock
# and 47 of CPU in one run on 2026-09-14 at a load average of 3.5, because the
# claim is about the whole suite: a suite could reach the committed record at
# any point in its run, so nothing shorter than running it proves it.
#
# IT NEEDS A BROWSER, like the suites it runs. With none it says CANNOT MEASURE
# and exits 2 rather than reading six suites that could not measure as six that
# judged nothing (L98, L411).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "rendering suites judge the committed design record" 15

require_target "docs/design"
harness_temp_dir WORK

env -u OVATION_DESIGN_ROOT python3 scripts/check-design-window-top.sh docs/design/invoice-pdf.html \
    >/dev/null 2>&1
if [ "$?" = "3" ]; then
    harness_cannot_measure \
        "no headless browser, so the rendering suites cannot judge anything and neither can this" \
        "npx playwright install chromium, or set OVATION_HEADLESS_BROWSER"
fi

# A copy of everything a rendering suite reads: its scripts, the design record,
# and the workflow the draws suite holds against its checks.
copy_tree() {
    mkdir -p "$1/docs"
    cp -R scripts "$1/scripts" && cp -R docs/design "$1/docs/design" && cp -R .github "$1/.github"
}

# $1 tree, $2 design file, $3 sed expression, $4 what the edit must leave behind.
# Prints how many lines carry it, so a damage that matched nothing is seen (L100).
damage() {
    local file="$1/docs/design/$2"
    sed "$3" "$file" > "$file.damaged" && mv "$file.damaged" "$file"
    grep -c -- "$4" "$file"
}

# $1 tree, $2 suite. Prints the suite's exit status, and whether a failed
# assertion names the committed record: `1:yes` is a suite that judged it.
judged() {
    local out="$1/$2.out" status named
    env -u OVATION_DESIGN_ROOT bash "$1/scripts/$2" > "$out" 2>&1
    status=$?
    named="$(grep -c '^FAIL: .*committed' "$out")"
    printf '%s:%s' "$status" "$([ "${named:-0}" -ge 1 ] && echo yes || echo no)"
}

# ---------------------------------------------------------------------------
# Each suite, and the committed file damaged under it.
# ---------------------------------------------------------------------------
T="$WORK/draws"; copy_tree "$T"
check "the draws suite's damage is in its copy" \
    "$(damage "$T" invoice-pdf.html 's|<body>|<body><script>console.error("damaged in a copy");</script>|' 'damaged in a copy')" "1"
check "the draws suite goes red on the committed record when a committed file logs an error" \
    "$(judged "$T" test-design-draws.sh)" "1:yes"

T="$WORK/invoice"; copy_tree "$T"
check "the invoice suite's damage is in its copy" \
    "$(damage "$T" invoice.html 's|\.invsum\.hasout \.sline\.totline|.invsum.neverset .sline.totline|g' 'invsum.neverset')" "2"
check "the invoice suite goes red on the committed file when its totals draw at one weight" \
    "$(judged "$T" test-invoice-screen-draws.sh)" "1:yes"

T="$WORK/clients"; copy_tree "$T"
check "the clients suite's damage is in its copy" \
    "$(damage "$T" clients.html 's/      fillRow(n, byName\[n.dataset.client\]);//' 'fillRow(n, byName')" "0"
check "the clients suite goes red on the committed file when its repaint stops redrawing rows" \
    "$(judged "$T" test-clients-screen-draws.sh)" "1:yes"

# The three below reach the record only by letting OVATION_DESIGN_ROOT default.
T="$WORK/tokens"; copy_tree "$T"
check "the token suite's damage is in its copy" \
    "$(damage "$T" invoice-list.html 's|</style>|body { outline-color: var(--defined-nowhere-in-a-copy); }\n</style>|' 'defined-nowhere-in-a-copy')" "1"
check "the token suite goes red on the committed record when a committed rule names a missing token" \
    "$(judged "$T" test-design-tokens-resolve.sh)" "1:yes"

T="$WORK/sidebar"; copy_tree "$T"
check "the sidebar card suite's damage is in its copy" \
    "$(damage "$T" invoice-list.html 's|To chase|To follow up|' 'To follow up')" "1"
check "the sidebar card suite goes red on the committed record when one file's card drifts" \
    "$(judged "$T" test-design-sidebar-card.sh)" "1:yes"

T="$WORK/window-top"; copy_tree "$T"
check "the window ceiling suite's damage is in its copy" \
    "$(damage "$T" invoice-list.html 's|</style>|body { padding-top: 900px; }\n</style>|' 'padding-top: 900px')" "1"
check "the window ceiling suite goes red on the committed record when a window slides down" \
    "$(judged "$T" test-design-window-top.sh)" "1:yes"

# ---------------------------------------------------------------------------
# The copy is complete: made the same way and left undamaged, suites pass on it.
# ---------------------------------------------------------------------------
T="$WORK/undamaged"; copy_tree "$T"
check "an undamaged copy passes the token suite, so a red above is the damage" \
    "$(judged "$T" test-design-tokens-resolve.sh)" "0:no"
check "and it passes the window ceiling suite" \
    "$(judged "$T" test-design-window-top.sh)" "0:no"

# ---------------------------------------------------------------------------
# The judgement can fail: a suite that never reads the record is told apart.
# ---------------------------------------------------------------------------
cat > "$T/scripts/test-planted-fixtures-only.sh" <<'SUITE'
#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "a suite narrowed to planted fixtures" 1
check "a planted fixture passes" "0" "0"
harness_end
SUITE
damage "$T" invoice-pdf.html 's|<body>|<body><script>console.error("damaged in a copy");</script>|' 'damaged' > /dev/null
check "a suite narrowed to planted fixtures stays green over a damaged record, and is not counted as judging it" \
    "$(judged "$T" test-planted-fixtures-only.sh)" "0:no"

harness_end
