#!/bin/bash
# Run a rendered design check ONCE and read its status and its words from that
# one run. Sourced by the suites of the six rendering checks.
#
# ovation#282. The invoice screen suite ran the check twice per damaged file,
# once for the exit status and once for the names of the claims that fired, and
# kept nothing of the second run but lines matching one pattern. On 2026-09-13 on
# CI the first run refused and the second came back as an empty string, so the
# failure read `expected '...', got ''` and the run that produced it was gone. A
# sibling agent met the same shape in the sidebar card suite the same night.
# Two renders of one file can disagree, and a suite that asks each question of a
# different render has no way to say which of them answered.
#
# SO A CASE RENDERS ONCE. `rendered_run` keeps everything the check printed, and
# its exit status, beside each other in files named for the case, and every read
# below takes both from there. The status is kept in a FILE rather than only a
# variable because the reads are made inside `$(...)`, a subshell, where a
# variable set by an earlier call is still visible but one set by a later call is
# not, and a helper that worked only in the order it was first written in is a
# trap for the next suite (L437).
#
# AND A MISMATCH SAYS WHAT THE CHECK SAID. Nothing at all and output naming no
# claim are different faults: the first never reached a page, the second reached
# one and said something the pattern does not recognise, a CANNOT MEASURE or a
# probe that threw. Each has its own sentence, with the exit status, rather than
# both arriving as an empty string (L11, L98).
#
# WHAT IS QUOTED IS BOUNDED, so a check that printed a page of output cannot bury
# the assertion that failed (L445), and it prefers the lines that carry a verdict
# over the lines that merely say what was rendered. The design files these checks
# read carry no client names, and a bound keeps a future one from reaching a log
# in bulk if that ever stops being true (docs/PRIVACY-FLOOR.md).
#
#     rendered_run <case> <command...>        RENDERED_STATUS is left set
#     rendered_status <case>                  the exit status of that run
#     rendered_claims <case> <sed expression> the claim names, sorted, joined by ;
#     rendered_said <case>                    what the run said, bounded
#     check_rendered_status <description> <case> <expected status>
#     check_rendered_count  <description> <case> <grep pattern> <expected count>
#
# <case> is a path prefix: the run writes <case>.out and <case>.status.

RENDERED_QUOTE_LIMIT=400

rendered_run() {
    local case_path="$1"
    shift
    "$@" > "$case_path.out" 2>&1
    RENDERED_STATUS=$?
    printf '%s' "$RENDERED_STATUS" > "$case_path.status"
    return 0
}

rendered_status() {
    if [ -f "$1.status" ]; then
        cat "$1.status"
    else
        printf 'NO RUN RECORDED for %s' "$(basename "$1")"
    fi
}

# What the run said, in one bounded line. The verdict lines first (a FAIL, a
# CANNOT, a REFUSED, an OK, a traceback's last word), because those carry the
# diagnosis; only when there are none, the last lines it printed.
rendered_said() {
    local out="$1.out" said
    said="$(grep -E '^ *(FAIL|CANNOT|REFUSED|OK:|USED WRONGLY|[A-Za-z]*Error)|NO CARD|NO SETTLED DAY|UNRESOLVED' "$out" 2>/dev/null \
        | head -n 8 | tr '\n' ' ')"
    [ -n "$said" ] || said="$(grep -v '^[[:space:]]*$' "$out" 2>/dev/null | tail -n 3 | tr '\n' ' ')"
    said="$(printf '%s' "$said" | tr -s ' ')"
    if [ "${#said}" -gt "$RENDERED_QUOTE_LIMIT" ]; then
        said="${said:0:$RENDERED_QUOTE_LIMIT}..."
    fi
    printf '%s' "${said% }"
}

rendered_claims() {
    local case_path="$1" expression="$2" out="$1.out" claims status lines
    if [ ! -f "$out" ]; then
        printf 'NO RUN RECORDED for %s: nothing was rendered under that name' "$(basename "$case_path")"
        return 0
    fi
    claims="$(sed -n "$expression" "$out" | sort -u | tr '\n' ';')"
    if [ -n "$claims" ]; then
        printf '%s' "$claims"
        return 0
    fi
    status="$(rendered_status "$case_path")"
    if [ ! -s "$out" ]; then
        printf 'NO CLAIM NAMED: the check printed nothing at all, and exited %s' "$status"
        return 0
    fi
    lines="$(wc -l < "$out" | tr -d ' ')"
    printf 'NO CLAIM NAMED: the check exited %s and printed %s line(s) naming no claim: %s' \
        "$status" "$lines" "$(rendered_said "$case_path")"
}

check_rendered_status() {
    local description="$1" case_path="$2" expected="$3" status
    status="$(rendered_status "$case_path")"
    if [ "$status" = "$expected" ]; then
        check "$description" "$status" "$expected"
    else
        check "$description" "$status, and the check said: $(rendered_said "$case_path")" "$expected"
    fi
}

check_rendered_count() {
    local description="$1" case_path="$2" pattern="$3" expected="$4" count
    count="$(grep -c -- "$pattern" "$case_path.out" 2>/dev/null)"
    count="${count:-0}"
    if [ "$count" = "$expected" ]; then
        check "$description" "$count" "$expected"
    else
        check "$description" \
            "$count, and the check exited $(rendered_status "$case_path") and said: $(rendered_said "$case_path")" \
            "$expected"
    fi
}
