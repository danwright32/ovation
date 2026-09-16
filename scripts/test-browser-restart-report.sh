#!/bin/bash
# Whether a browser restart that CI recorded reaches the tracker, and whether a
# run that could not be read is ever reported as a run that recorded nothing.
#
# ovation#352. ovation#332 put this logic inside a step of
# .github/workflows/browser-restarts.yml, which is a `workflow_run` workflow, so
# it only ever runs from the DEFAULT branch: it could not run on the pull request
# that added it, and its first real execution is on main after a browser has
# actually stopped answering, which happened once in two months. That is the half
# that decides whether a finding is seen, back in YAML for exactly the reason
# ovation#339 took it out (L3).
#
# Every way it breaks is silent in the direction that LOSES the report, and the
# next occurrence is months away, so the fault would be discovered by not hearing
# about something.
#
# `gh` AND THE REPORTER ARE SEAMS, so each outcome is PRODUCED here rather than
# reasoned about: a lookup that fails, a run holding no record, a download that
# fails, a record that is missing or empty, a record with two lines, and a
# reporter that says nothing open carries the title. Nothing reaches the real
# tracker and nothing downloads anything (L2, L291).
#
# THE STUBS ANSWER AND RECORD, both halves: a case asserting a comment did NOT
# happen is satisfied by a stub that cannot comment at all (L159).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "browser restart report tests" 30

TARGET="scripts/report-browser-restarts.sh"
require_target "$TARGET"
harness_temp_dir WORK
REPO_ROOT="$PWD"

# ---------------------------------------------------------------------------
# The stubs. Their bodies are INDENTED, because scripts/test-run-tests.sh refuses
# a suite that reads `$1` on a line of its own and a heredoc's lines are read by
# that rule exactly like the suite's own (L135).
BIN="$WORK/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'STUB'
#!/bin/bash
    D="${STUB_DIR:?the gh stub was run with no directory to answer from}"
    printf '%s %s\n' "${1:-}" "${2:-}" >> "$D/calls.log"
    for a in "$@"; do printf '%s\n' "$a" >> "$D/args.log"; done
    if [ "${1:-}" = "api" ]; then
        [ -f "$D/artifacts.txt" ] && cat "$D/artifacts.txt"
        exit "$(cat "$D/api.status" 2>/dev/null || echo 0)"
    fi
    if [ "${1:-} ${2:-}" = "run download" ]; then
        dir=""
        while [ "$#" -gt 0 ]; do
            [ "$1" = "--dir" ] && dir="${2:-}"
            shift
        done
        status="$(cat "$D/download.status" 2>/dev/null || echo 0)"
        if [ "$status" = "0" ] && [ -n "$dir" ] && [ -d "$D/payload" ]; then
            mkdir -p "$dir"
            cp -R "$D/payload/." "$dir/"
        fi
        exit "$status"
    fi
    exit 0
STUB
chmod +x "$BIN/gh"

# The reporter. It records the words it was handed, and answers with whatever
# code the case staged, so the mapping of ITS codes onto this script's verdict is
# what each case measures (L184).
cat > "$BIN/report-finding" <<'STUB'
#!/bin/bash
    D="${STUB_DIR:?the reporter stub was run with no directory to answer from}"
    printf 'reporter %s\n' "${1:-}" >> "$D/calls.log"
    while [ "$#" -gt 0 ]; do
        if [ "$1" = "--comment-file" ] && [ -f "${2:-}" ]; then cp "$2" "$D/comment.md"; fi
        if [ "$1" = "--title" ]; then printf '%s\n' "${2:-}" > "$D/title.txt"; fi
        shift
    done
    exit "$(cat "$D/reporter.status" 2>/dev/null || echo 1)"
STUB
chmod +x "$BIN/report-finding"

# stage <name>: a fresh answer directory, holding the ordinary case.
#
# THE GUARD BEFORE THE DELETE IS NOT DECORATION (L5). The harness creates WORK and
# exits if it could not, and a recursive delete built from a variable is not the
# place to depend on that holding somewhere else: an empty one would delete from
# the filesystem root. scripts/test-git-hooks.sh carries the same two lines.
stage() {
    [ -n "$WORK" ] || exit 1
    STUB_DIR="$WORK/stub-$1"
    rm -rf "$STUB_DIR"; mkdir -p "$STUB_DIR/payload"
    printf 'browser-restarts\n' > "$STUB_DIR/artifacts.txt"
    printf '2026-09-15T10:00:00Z\tPage.navigate\tinvoice.html\n' \
        > "$STUB_DIR/payload/browser-restarts.tsv"
    printf '%s' "$STUB_DIR"
}

# run <stub dir> [run id]: the script, with both seams pointed at the stubs and a
# record directory of its own, so no case writes into the checkout.
run() {
    local dir="$1" runID="${2-4242}" out
    [ -n "$WORK" ] || exit 1
    out="$WORK/out-$(basename "$dir")"
    rm -rf "$out"
    ( cd "$WORK" && STUB_DIR="$dir" \
        OVATION_GH="$BIN/gh" \
        OVATION_REPORT_FINDING="$BIN/report-finding" \
        OVATION_RESTART_RECORD_DIR="$out" \
        GITHUB_REPOSITORY="danwright32/ovation" \
        OVATION_RESTART_RUN_ID="$runID" \
        OVATION_RESTART_RUN_URL="https://github.com/danwright32/ovation/actions/runs/4242" \
        bash "$REPO_ROOT/$TARGET" 2>&1 )
}

calls() { cat "$1/calls.log" 2>/dev/null || true; }

# WHETHER IT WAS SAID, not how many lines it took to say it. A count would break
# on a message that wraps, which is a fact about the wrapping (L103).
said() { printf '%s' "$1" | grep -qiE "$2" && echo said || echo "not said"; }

# ---------------------------------------------------------------------------
# THE ORDINARY CASE: a run that recorded a restart.
D1="$(stage recorded)"
printf '1\n' > "$D1/reporter.status"
OUT1="$(run "$D1")"; ST1=$?
check "a run holding a record reports it and succeeds" "$ST1" "0"
check "and it says the occurrence was reported" \
    "$(said "$OUT1" 'reported')" "said"
check "and the reporter was actually called" \
    "$(calls "$D1" | grep -c '^reporter recurred')" "1"
check "and it was given the title the issue carries" \
    "$(cat "$D1/title.txt" 2>/dev/null)" \
    "A headless browser stopped answering during CI and was restarted"
check "and the comment carries the recorded line" \
    "$(grep -c 'Page.navigate' "$D1/comment.md" 2>/dev/null)" "1"
check "and the comment names the run it came from" \
    "$(grep -c 'actions/runs/4242' "$D1/comment.md" 2>/dev/null)" "1"
check "and the comment says how many restarts, so one and five do not read alike" \
    "$(grep -c '^1 restart' "$D1/comment.md" 2>/dev/null)" "1"

# TWO LINES IS TWO OCCURRENCES, and the count is READ from the record rather
# than assumed to be one (L467).
D2="$(stage two-lines)"
printf '1\n' > "$D2/reporter.status"
printf '2026-09-15T10:00:00Z\tPage.navigate\tinvoice.html\n2026-09-15T11:00:00Z\tRuntime.evaluate\tclients.html\n' \
    > "$D2/payload/browser-restarts.tsv"
OUT2="$(run "$D2")"; ST2=$?
check "a record of two lines is two restarts" "$ST2:$(grep -c '^2 restart' "$D2/comment.md" 2>/dev/null)" "0:1"
check "and both lines reach the comment" \
    "$(grep -cE 'Page.navigate|Runtime.evaluate' "$D2/comment.md" 2>/dev/null)" "2"

# ---------------------------------------------------------------------------
# NOTHING TO COUNT, which is the ordinary state of almost every run. It must be
# told apart from a lookup that could not answer (L98, L11).
D3="$(stage no-artifact)"
printf 'design-screenshots\n' > "$D3/artifacts.txt"
OUT3="$(run "$D3")"; ST3=$?
check "a run that kept no record succeeds" "$ST3" "0"
check "and says no browser stopped answering in it" \
    "$(said "$OUT3" 'no browser stopped answering')" "said"
check "and nothing was reported" "$(calls "$D3" | grep -c '^reporter')" "0"

D4="$(stage no-run)"
OUT4="$(run "$D4" "")"; ST4=$?
check "started by hand with no run to read, it succeeds and counts nothing" \
    "$ST4:$(calls "$D4" | grep -c '^reporter')" "0:0"
check "and it says there was no run to read" \
    "$(said "$OUT4" 'no run')" "said"

# ---------------------------------------------------------------------------
# COULD NOT MEASURE IS NOT NOTHING. Each of these fails the job, and each says
# its own cause rather than one sentence covering four (L11).
D5="$(stage lookup-failed)"
printf '1\n' > "$D5/api.status"
OUT5="$(run "$D5")"; ST5=$?
check "a lookup that failed does not report a quiet all clear" \
    "$([ "$ST5" -ne 0 ] && echo failed || echo passed):$(calls "$D5" | grep -c '^reporter')" "failed:0"
check "and it says the artifacts could not be read" \
    "$(said "$OUT5" 'could not be read')" "said"

D6="$(stage download-failed)"
printf '1\n' > "$D6/download.status"
OUT6="$(run "$D6")"; ST6=$?
check "a record that is listed and cannot be downloaded fails" \
    "$([ "$ST6" -ne 0 ] && echo failed || echo passed):$(calls "$D6" | grep -c '^reporter')" "failed:0"
check "and it says the download failed rather than that nothing was kept" \
    "$(said "$OUT6" 'could not be downloaded')" "said"

D7="$(stage wrong-file)"
rm -f "$D7/payload/browser-restarts.tsv"
printf 'something else\n' > "$D7/payload/other.txt"
OUT7="$(run "$D7")"; ST7=$?
check "an artifact holding no browser-restarts.tsv fails" \
    "$([ "$ST7" -ne 0 ] && echo failed || echo passed):$(calls "$D7" | grep -c '^reporter')" "failed:0"
check "and it names the file it did not find" \
    "$(printf '%s' "$OUT7" | grep -c 'browser-restarts.tsv')" "1"

D8="$(stage empty-record)"
: > "$D8/payload/browser-restarts.tsv"
OUT8="$(run "$D8")"; ST8=$?
check "an empty record fails, because the renderer only creates it by writing to it" \
    "$([ "$ST8" -ne 0 ] && echo failed || echo passed):$(calls "$D8" | grep -c '^reporter')" "failed:0"
check "and it says the record is empty" "$(said "$OUT8" 'empty')" "said"

# ---------------------------------------------------------------------------
# A RESTART MEASURED AND REPORTED TO NOBODY IS THE SILENT LOSS THIS EXISTS TO
# PREVENT (L98). The reporter's 8 means nothing open carries the title.
D9="$(stage no-issue)"
printf '8\n' > "$D9/reporter.status"
OUT9="$(run "$D9")"; ST9=$?
check "a reported occurrence nothing carries fails the job" \
    "$([ "$ST9" -ne 0 ] && echo failed || echo passed)" "failed"
check "and it says the occurrence reached nobody" \
    "$(said "$OUT9" 'nobody|no open issue')" "said"

# ANY OTHER CODE FROM THE REPORTER IS A FAULT TOO, and it is carried rather than
# flattened, so a caller reading the code can tell them apart (L184).
D10="$(stage reporter-broke)"
printf '4\n' > "$D10/reporter.status"
run "$D10" >/dev/null; ST10=$?
check "another refusal from the reporter is carried out, not flattened" "$ST10" "4"

# AND THE ONE CODE THAT MEANS IT WAS COMMENTED IS THE ONLY SUCCESS. A reporter
# that exits 0, which it never does, must not read as a comment that happened.
D11="$(stage reporter-zero)"
printf '0\n' > "$D11/reporter.status"
OUT11="$(run "$D11")"; ST11=$?
check "an unexpected success from the reporter is not read as a comment" \
    "$([ "$ST11" -ne 0 ] && echo failed || echo passed)" "failed"

# ---------------------------------------------------------------------------
# THE WORKFLOW RUNS THIS SCRIPT, and that is what makes any of the above true of
# what happens on a runner (L3, L58). Both halves: the step calls it, and the
# logic it replaced is not sitting in the YAML as well.
YML=".github/workflows/browser-restarts.yml"
require_target "$YML"
check "the workflow runs this script" \
    "$(grep -c 'run: bash scripts/report-browser-restarts.sh' "$YML")" "1"
check "and the YAML no longer decides whether a record was kept" \
    "$(grep -c 'gh run download\|actions/runs/.*artifacts' "$YML")" "0"
check "and it passes the run the trigger names" \
    "$(grep -c 'OVATION_RESTART_RUN_ID' "$YML")" "1"
check "and the run's own URL, so the comment can name where it came from" \
    "$(grep -c 'OVATION_RESTART_RUN_URL' "$YML")" "1"

harness_end
