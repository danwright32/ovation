#!/bin/bash
# A staged run writes nothing to a durable record, by one rule, and a writer that
# skips the rule is refused by name.
#
# ovation#368. Two records a suite could write into each carried their own copy of
# the guard: the browser restart record in scripts/lib/design_render.py and the
# lock wait record in scripts/run-tests.sh. They disagreed. The renderer refused a
# staged fault whoever named a record (ovation#366); the runner took a named path
# whatever else was true, which is the shape that let seven runs of staged faults
# be counted as real on ovation#353 (L2, L93). And nothing would have caught a
# third record written with a third version, or with none (L27, L613).
#
# So this suite holds both halves: the rule itself, scripts/lib/durable-record.sh,
# as a table of every subject, declaration and name; and the scan,
# scripts/check-durable-records.sh, over a planted tree, with each outcome its
# contract names produced rather than merely passed (L151).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
# The one declaration the cases below use, cleared so a value inherited from the
# shell that launched this suite cannot answer for a case (L439).
unset OVATION_SUITE_RECORD_STAGED
harness_begin "durable record tests" 39

RULE="scripts/lib/durable-record.sh"
TARGET="scripts/check-durable-records.sh"
require_target "$RULE"
require_target "$TARGET"
harness_temp_dir WORK

says() { if grep -qF -- "$2" <<< "$1"; then echo yes; else echo no; fi; }
ask() { bash "$RULE" "$@" 2>/dev/null; }

# ---------------------------------------------------------------------------
# THE RULE. Real runs are what the records exist for, so they come first and are
# asserted to be untouched (L63): a fix that silenced real runs would pass every
# staged case below.
# ---------------------------------------------------------------------------
check "a real run with a record named writes to the named record" \
    "$(ask real OVATION_SUITE_RECORD_STAGED "$WORK/named.tsv" "$WORK/default.tsv")" "$WORK/named.tsv"
check "a real run with none named writes to the default record" \
    "$(ask real OVATION_SUITE_RECORD_STAGED "" "$WORK/default.tsv")" "$WORK/default.tsv"
check "a staged run with none named writes nothing" \
    "$(ask staged OVATION_SUITE_RECORD_STAGED "" "$WORK/default.tsv")" ""
# The defect ovation#368 exists for: a name reaching the record from a staged run.
check "a staged run writes nothing even to a record somebody named" \
    "$(ask staged OVATION_SUITE_RECORD_STAGED "$WORK/named.tsv" "$WORK/default.tsv")" ""
check "a staged run that declares the staging is what it measures writes to the named record" \
    "$(OVATION_SUITE_RECORD_STAGED=1 ask staged OVATION_SUITE_RECORD_STAGED "$WORK/named.tsv" "$WORK/default.tsv")" "$WORK/named.tsv"
check "and a declaration of nothing but spaces is not a declaration" \
    "$(OVATION_SUITE_RECORD_STAGED='  ' ask staged OVATION_SUITE_RECORD_STAGED "$WORK/named.tsv" "$WORK/default.tsv")" ""
check "a declaration made for ANOTHER record does not reach this one" \
    "$(OVATION_OTHER_RECORD_STAGED=1 ask staged OVATION_SUITE_RECORD_STAGED "$WORK/named.tsv" "$WORK/default.tsv")" ""

# A caller that cannot say what its subject is has not been judged, and silence
# would read as "write nothing" or "write", whichever it happened to fall into.
check_exit "a subject that is neither real nor staged is refused" \
    2 bash "$RULE" maybe OVATION_SUITE_RECORD_STAGED "" "$WORK/default.tsv"
OUT="$(bash "$RULE" maybe OVATION_SUITE_RECORD_STAGED "" "$WORK/default.tsv" 2>&1)"
check "and the refusal names the two it accepts" "$(says "$OUT" "real or staged")" "yes"
check_exit "a declaration that is not a variable name is refused" \
    2 bash "$RULE" staged "not a name" "" "$WORK/default.tsv"
check_exit "a record with no default is refused" \
    2 bash "$RULE" real OVATION_SUITE_RECORD_STAGED "" ""

# SOURCED, the same function answers the same way: run-tests.sh sources it and
# design_render.py executes it, and the two routes must be one rule.
check "sourced, the rule answers as it does when executed" \
    "$(bash -c '. "$1"; durable_record_path staged OVATION_SUITE_RECORD_STAGED "$2" "$3"' _ "$RULE" "$WORK/named.tsv" "$WORK/default.tsv")" ""

# ---------------------------------------------------------------------------
# THE SCAN, over a planted tree.
# ---------------------------------------------------------------------------
TREE="$WORK/tree"
reset_tree() { [ -n "$WORK" ] || exit 1; rm -rf "$TREE"; mkdir -p "$TREE/scripts/lib"; : > "$TREE/scripts/durable-record-exemptions.tsv"; }
run_check() { OVATION_DURABLE_RECORDS_ROOT="$TREE" bash "$TARGET" 2>&1; }

# 1. A shell writer that asks the rule for its path passes, and is said.
reset_tree
cat > "$TREE/scripts/routed.sh" <<'SH'
LOG="$(durable_record_path real OVATION_X_RECORD_STAGED "${OVATION_X_LOG:-}" "$HOME/x.tsv")"
printf 'a\n' >> "${LOG}"
SH
OUT="$(run_check)"; ST=$?
check "a shell writer whose path comes from the rule passes" "$ST" "0"
check "and it is named as routed, so the count is read" "$(says "$OUT" "routed.sh")" "yes"

# 1b. EVERY assignment must be the rule's: the lock wait record took the rule's
#     shape of answer and then a name straight from the environment (L178).
printf 'LOG="${OVATION_X_LOG:-}"\n' >> "$TREE/scripts/routed.sh"
OUT="$(run_check)"; ST=$?
check "a writer whose variable is also assigned around the rule is refused" "$ST" "1"

# 1c. THE TARGET MUST BE THE ROUTED VARIABLE EXACTLY. A path built FROM it is
#     another file the rule never judged: `${LOG}.bak` beside the record, or the
#     record's name with something else joined on (L266).
for built in '"${LOG}.bak"' '"$LOG"x' '"${LOG}${OTHER}"'; do
    reset_tree
    printf 'LOG="$(durable_record_path real OVATION_X_RECORD_STAGED "" "$HOME/x.tsv")"\nprintf "a\\n" >> %s\n' "$built" > "$TREE/scripts/built.sh"
    OUT="$(run_check)"; ST=$?
    check "an append to $built, built from a routed variable, is refused" "$ST:$(says "$OUT" "UNROUTED: scripts/built.sh:2")" "1:yes"
done

# 2. The defect: an append to a durable path that never asks.
reset_tree
printf 'printf "a\\n" >> "$HOME/Library/Logs/Ovation/new.tsv"\n' > "$TREE/scripts/unrouted.sh"
OUT="$(run_check)"; ST=$?
check "a shell writer that never asks the rule is refused" "$ST" "1"
check "and it is named with its line" "$(says "$OUT" "scripts/unrouted.sh:1")" "yes"

# 3. A PYTHON writer is found the same way, and a second writer in a file whose
#    first one IS routed is still refused: a file level match would pass it (L135).
reset_tree
cat > "$TREE/scripts/lib/writer.py" <<'PY'
record = durable_record_path("real", "OVATION_X_RECORD_STAGED", named, default)
with open(record, "a") as handle:
    handle.write(line)
with open(other, "a") as handle:
    handle.write(line)
PY
OUT="$(run_check)"; ST=$?
check "a second python writer beside a routed one is refused" "$ST" "1"
check "and it is the second one that is named" "$(says "$OUT" "scripts/lib/writer.py:4")" "yes"
check "and the routed one is not" "$(says "$OUT" "UNROUTED: scripts/lib/writer.py:2")" "no"

# 3b. ANOTHER LANGUAGE'S OPERATOR is not a shell append (ovation#619). The lift
#     harness had to write a JavaScript hash without an unsigned shift because
#     the scan read its brackets, inside a string of a python program, as a shell
#     append: the check shaping code it has no business judging. Another language
#     lives in a script here in two places: a whole file that is python behind the
#     exec line, and a heredoc a shell script feeds to another interpreter.
reset_tree
cat > "$TREE/scripts/polyglot.sh" <<'PY'
#!/usr/bin/env python3
''''exec python3 "$0" "$@" #'''
SCRIPT = "function h(x) { return (x >>> 0).toString(16); }"
bits = 1 >> 1
PY
OUT="$(run_check)"; ST=$?
check "a shift inside a python program started from a .sh file is not an append" "$ST" "0"

reset_tree
cat > "$TREE/scripts/fed.sh" <<'SH'
#!/bin/bash
OUT="$(python3 - "$1" <<'INNER'
SCRIPT = "function h(x) { return (x >>> 0).toString(16); }"
bits = 1 >> 1
INNER
)"
node <<-INNER
	var y = 8 >>> 1;
	INNER
echo done
SH
OUT="$(run_check)"; ST=$?
check "a shift inside a heredoc fed to python or node is not an append" "$ST" "0"
check "and nothing in it is counted as a writer" "$(says "$OUT" "UNROUTED")" "no"

# The same shapes must not become a hiding place for a REAL append: one after the
# heredoc ends, one in a heredoc fed to a shell, one python writer inside a python
# heredoc, and a python writer in a python program behind the exec line.
printf 'printf "a\\n" >> "$HOME/after.tsv"\n' >> "$TREE/scripts/fed.sh"
OUT="$(run_check)"; ST=$?
check "a real append after a python heredoc ends is still refused, by its line" \
    "$ST:$(says "$OUT" "UNROUTED: scripts/fed.sh:11")" "1:yes"

reset_tree
cat > "$TREE/scripts/shellfed.sh" <<'SH'
bash <<'INNER'
printf 'a\n' >> "$HOME/inner.tsv"
INNER
SH
OUT="$(run_check)"; ST=$?
check "an append in a heredoc fed to a shell is still refused" \
    "$ST:$(says "$OUT" "UNROUTED: scripts/shellfed.sh:2")" "1:yes"

reset_tree
cat > "$TREE/scripts/pywriter.sh" <<'SH'
python3 - <<'INNER'
with open(other, "a") as handle:
    handle.write("x")
INNER
SH
OUT="$(run_check)"; ST=$?
check "a python writer in a heredoc fed to python is still refused" \
    "$ST:$(says "$OUT" "UNROUTED: scripts/pywriter.sh:2")" "1:yes"

# A heredoc whose end is never found has not been read, so nothing after its
# start is skipped: the rest of the file is judged as shell (L100).
reset_tree
printf 'python3 - <<INNER\nprintf "a\\n" >> "$HOME/open.tsv"\n' > "$TREE/scripts/unended.sh"
OUT="$(run_check)"; ST=$?
check "an append after a heredoc that never ends is still refused" \
    "$ST:$(says "$OUT" "UNROUTED: scripts/unended.sh:2")" "1:yes"

reset_tree
cat > "$TREE/scripts/polywriter.sh" <<'PY'
''''exec python3 "$0" "$@" #'''
with open(other, "a") as handle:
    handle.write("x")
PY
OUT="$(run_check)"; ST=$?
check "a python writer in a python program behind the exec line is still refused" \
    "$ST:$(says "$OUT" "UNROUTED: scripts/polywriter.sh:2")" "1:yes"

# 4. A COMMENT ABOUT an append is not one.
reset_tree
printf '# every wait is appended with >> "$LOG"\n' > "$TREE/scripts/commented.sh"
OUT="$(run_check)"; ST=$?
check "an append written only in a comment is not a writer" "$ST" "0"

# 5. LISTED WITH A REASON, an unrouted writer passes and is still said, because
#    a writer whose subject nothing can inject is legitimate (a person's verdict).
reset_tree
printf 'printf "a\\n" >> "${RECORD}"\n' > "$TREE/scripts/by-hand.sh"
printf 'by-hand.sh\ta person types the verdict, so nothing can stage it\n' > "$TREE/scripts/durable-record-exemptions.tsv"
OUT="$(run_check)"; ST=$?
check "an unrouted writer listed with a reason passes" "$ST" "0"
check "and its reason is printed rather than going quiet" "$(says "$OUT" "a person types the verdict")" "yes"

# 6. A LISTING WITH NO REASON is refused (L233).
printf 'by-hand.sh\t\n' > "$TREE/scripts/durable-record-exemptions.tsv"
OUT="$(run_check)"; ST=$?
check "a listing with no reason is refused" "$ST" "1"

# 7. A STALE LISTING for a file with no unrouted writer is refused (L346).
reset_tree
printf 'echo nothing\n' > "$TREE/scripts/quiet.sh"
printf 'quiet.sh\tonce wrote a record\n' > "$TREE/scripts/durable-record-exemptions.tsv"
OUT="$(run_check)"; ST=$?
check "a listing for a file with no unrouted writer is refused as stale" "$ST" "1"
check "and it says to remove that line" "$(says "$OUT" "remove it from")" "yes"

# 8. NOTHING TO JUDGE is its own answer, never a pass (L98).
rm -rf "$TREE"; mkdir -p "$TREE"
check_exit "a tree with no scripts directory cannot be judged" 2 run_check

# 9. THE REAL TREE, which is the case the scan exists for.
OUT="$(bash "$TARGET" 2>&1)"; ST=$?
check "the committed scripts route every durable record through the rule or list it" "$ST" "0"

harness_end
