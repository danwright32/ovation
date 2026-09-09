#!/bin/bash
# The suite for scripts/write-design-shell.sh.
#
# ovation#177. The point of this script is that a remedy nothing executes is
# never tested, so nobody finds out it was wrong until the moment it is needed
# (L406). This is what executes it. The shape of every case is the one the issue
# asks for: DAMAGE a copy, run the writer, and assert the CHECKER then passes.
# Asserting the writer's own output instead would be one tool marking its own
# work (L70).
#
# TWO OF ITS THREE REAL BUGS WERE FOUND HERE and are each a case below, because
# both produced a script that reported success while writing the wrong thing.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "shell writer tests" 28

TARGET="scripts/write-design-shell.sh"
CHECKER="scripts/check-design-shell-inline.sh"
require_target "$TARGET"
require_target "$CHECKER"
harness_temp_dir WORK

# A fresh copy of the committed record per case, so nothing a case writes can
# reach the next one or the repository.
fresh() {
    local at="$WORK/$1"
    rm -rf "$at" && mkdir -p "$at" && cp -R docs/design/. "$at/"
    printf '%s' "$at"
}

write_in() { OVATION_DESIGN_ROOT="$1" python3 "$TARGET" "${@:2}" 2>&1; }
write_status() { OVATION_DESIGN_ROOT="$1" python3 "$TARGET" "${@:2}" >/dev/null 2>&1; printf '%s' "$?"; }
check_status() {
    OVATION_DESIGN_ROOT="$1" python3 "$CHECKER" >/dev/null 2>&1
    printf '%s' "$?"
}

damage() {
    # $1 root, $2 file, $3 the exact line to change, $4 what to change it to
    python3 - "$1/$2" "$3" "$4" <<'PYEOF'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
assert old in text, "the mutation matched nothing, so this case tests nothing"
open(path, "w").write(text.replace(old, new))
PYEOF
}

ON="\.item.on { background: #E5DCD2; color: var(--ink); font-weight: 600; }"
ON_PLAIN=".item.on { background: #E5DCD2; color: var(--ink); font-weight: 600; }"
ON_RED=".item.on { background: #FF0000; color: var(--ink); font-weight: 600; }"

# ---------------------------------------------------------------------------
# The committed record, which must already be in step and must stay untouched.
# ---------------------------------------------------------------------------
CLEAN="$(fresh clean)"
check "the committed record is already in step" "$(check_status "$CLEAN")" "0"
check "so the writer changes nothing" "$(write_status "$CLEAN")" "0"
check "and says how many copies it found in step" \
    "$(write_in "$CLEAN" | grep -c '20 copy(s) already in step, 0 rewritten')" "1"
check "and every file is byte for byte what it was" \
    "$(diff -r docs/design "$CLEAN" >/dev/null 2>&1 && echo same)" "same"

# ---------------------------------------------------------------------------
# THE CASE THE ISSUE ASKS FOR: damage a copy, run the writer, checker passes.
# ---------------------------------------------------------------------------
DRIFTED="$(fresh drifted)"
damage "$DRIFTED" invoice-list.html "$ON_PLAIN" "$ON_RED"
check "a damaged copy is refused by the checker first" "$(check_status "$DRIFTED")" "1"
# THE RUN IS CAPTURED ONCE. Calling the writer again to read its message would
# read a SECOND run, on a tree the first one already repaired, which reports
# nothing rewritten and is the check answering about the wrong event.
DRIFTED_SAID="$(write_in "$DRIFTED")"
DRIFTED_STATUS=$?
check "the writer repairs it" "$DRIFTED_STATUS" "0"
check "and says which file and which part" \
    "$(printf '%s' "$DRIFTED_SAID" | grep -c 'invoice-list.html: window.css REWRITTEN')" "1"
check "and the checker then passes" "$(check_status "$DRIFTED")" "0"
check "and the file is byte for byte the committed one again" \
    "$(diff -q docs/design/invoice-list.html "$DRIFTED/invoice-list.html" >/dev/null && echo same)" "same"
check "and no other file was touched" \
    "$(diff -r docs/design "$DRIFTED" >/dev/null 2>&1 && echo same)" "same"

# ---------------------------------------------------------------------------
# THE FIRST REAL BUG. `design_inline.strip_comments` collapses a block comment
# to ONE newline, which is right for comparing a shape and wrong for editing a
# file: every line after the first comment then has the wrong number. Built on
# it, this script repaired `.item.on` by writing it over a line of the PALETTE,
# and reported success (L237). The case that catches it is a file whose part is
# preceded by comments, which is every one of them.
# ---------------------------------------------------------------------------
check "the repair lands on the rule, not on a line that happens to sit there" \
    "$(grep -c "$ON" "$DRIFTED/invoice-list.html")" "1"
check "and the palette above it is untouched" \
    "$(grep -c -- '--rail: #3B2B21' "$DRIFTED/invoice-list.html")" "1"

# ---------------------------------------------------------------------------
# THE SECOND REAL BUG. These files carry their typefaces as base64, where `//`
# occurs by the thousand inside one token. A stripper that cut on any `//`
# truncated the whole payload, so `fonts.css` could not be located at all and
# the script REFUSED four copies it should have written.
# ---------------------------------------------------------------------------
FONTS="$(fresh fonts)"
check "every part is located, the embedded fonts included" \
    "$(write_in "$FONTS" | grep -c 'NOT FOUND')" "0"

# ---------------------------------------------------------------------------
# A rule ADDED to the shell reaches every file that carries the part.
# ---------------------------------------------------------------------------
ADDED="$(fresh added)"
damage "$ADDED" shell/window.css \
    ".dot { width: 11px; height: 11px; border-radius: 50%; }" \
    ".dot { width: 11px; height: 11px; border-radius: 50%; }
.dot.focused { outline: 1px solid var(--accent); }"
check "a rule added to the shell leaves four copies drifted" \
    "$(OVATION_DESIGN_ROOT="$ADDED" python3 "$CHECKER" 2>&1 | grep -c DRIFTED)" "4"
check "the writer puts it into all of them" "$(write_status "$ADDED")" "0"
check "and the checker then passes" "$(check_status "$ADDED")" "0"
check "and it landed beside the rule it follows in the part" \
    "$(grep -A1 '^\.dot { width' "$ADDED/invoice-list.html" | grep -c 'dot.focused')" "1"

# ---------------------------------------------------------------------------
# A rule REMOVED from the shell goes from every file too.
# ---------------------------------------------------------------------------
REMOVED="$(fresh removed)"
damage "$REMOVED" shell/window.css \
    ".dot.r { background: #ED6A5E; } .dot.y { background: #F4BF50; } .dot.g { background: #61C454; }
" ""
check "the writer removes it everywhere" "$(write_status "$REMOVED")" "0"
check "and the checker passes" "$(check_status "$REMOVED")" "0"
check "and the rule is gone from the file" \
    "$(grep -c 'dot.r' "$REMOVED/invoice-list.html")" "0"

# ---------------------------------------------------------------------------
# A FILE'S OWN PROSE IS NEVER LOST. `invoice-list.html` interleaves its rounds'
# decision records among the shell's rules, and those are the most expensive
# thing in these files. A writer that replaced the copy wholesale would delete
# them, which is why this patches the code lines instead.
# ---------------------------------------------------------------------------
check "a file's own decision record survives the rewrite" \
    "$(grep -c 'THE COLUMN HEADERS, settled' "$ADDED/invoice-list.html")" "1"
check "and so does the reasoning about the date column" \
    "$(grep -c 'The date column is 152px' "$ADDED/invoice-list.html")" "1"

# ---------------------------------------------------------------------------
# --check WRITES NOTHING, so a gate can ask without changing the tree.
# ---------------------------------------------------------------------------
ASKED="$(fresh asked)"
damage "$ASKED" invoice-list.html "$ON_PLAIN" "$ON_RED"
check "--check answers with its own code rather than a pass or a failure" \
    "$(write_status "$ASKED" --check)" "3"
check "and it wrote nothing" \
    "$(grep -c "$ON_RED" "$ASKED/invoice-list.html")" "1"

# ---------------------------------------------------------------------------
# A COPY IT CANNOT FIND IS A REFUSAL, never an insertion at a guessed place. An
# operation that finds its target by matching text reports success when it
# matches nothing, and the next step acts on a state nobody created (L100).
# ---------------------------------------------------------------------------
GONE="$(fresh gone)"
python3 - "$GONE" <<'PYEOF'
import sys
# Every code line of window.css taken out of one file, leaving its comments and
# everything else, which is the state where the writer has nothing to anchor on.
path = sys.argv[1] + "/clients.html"
part = [" ".join(l.split()) for l in open(sys.argv[1] + "/shell/window.css").read().split("\n")]
part = {p for p in part if p and not p.startswith(("/*", "*", "*/"))}
kept = [l for l in open(path).read().split("\n") if " ".join(l.split()) not in part]
open(path, "w").write("\n".join(kept))
PYEOF
GONE_SAID="$(write_in "$GONE")"
GONE_STATUS=$?
check "a file that carries no line of a part is refused" "$GONE_STATUS" "1"
check "and the refusal names the file and says nothing was written for it" \
    "$(printf '%s' "$GONE_SAID" | grep -c 'clients.html: window.css NOT FOUND')" "1"
check "and it never writes the part in at a guessed place" \
    "$(grep -c '^\.railtop {' "$GONE/clients.html")" "0"

# ---------------------------------------------------------------------------
# NOTHING TO WRITE IS NOT A PASS (L98).
# ---------------------------------------------------------------------------
check "no shell at all cannot write" \
    "$(OVATION_DESIGN_ROOT="$WORK/nowhere" python3 "$TARGET" >/dev/null 2>&1; printf '%s' "$?")" "2"

harness_end
