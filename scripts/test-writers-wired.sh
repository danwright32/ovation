#!/bin/bash
# Every writer the app declares is used by the app, or is listed with the issue that wires it.
#
# ovation#441. InvoiceNumberAllocator, InvoiceCloser and PaymentAllocator were each
# built with their own tests and called by nothing in the app, so each read as done
# from every angle but the one that counts (L3), and a backlog read through the
# domain layer said the milestone was further along than it is.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "writers wired tests" 10

TARGET="scripts/check-writers-wired.sh"
require_target "$TARGET"
harness_temp_dir WORK

TREE="$WORK/tree"
actor() { printf '@ModelActor\nactor %s {\n    func write() {}\n}\n' "$1" > "$TREE/App/$1.swift"; }
reset_tree() { [ -n "$WORK" ] || exit 1; rm -rf "$TREE"; mkdir -p "$TREE/App" "$TREE/scripts"; : > "$TREE/scripts/unwired-writers.tsv"; }
run_check() { OVATION_WRITERS_ROOT="$TREE" bash "$TARGET" 2>&1; }
says() { if grep -qF -- "$2" <<< "$1"; then echo yes; else echo no; fi; }

# 1. A writer the app constructs elsewhere is wired.
reset_tree; actor UsedWriter
printf 'let w = UsedWriter(modelContainer: c)\n' > "$TREE/App/Caller.swift"
OUT="$(run_check)"; ST=$?
check "a writer the app constructs is wired" "$ST" "0"
check "and it says how many writers it judged" "$(says "$OUT" "1 writer(s)")" "yes"

# 2. The defect: declared, tested, and called by nothing in the app.
reset_tree; actor OrphanWriter
OUT="$(run_check)"; ST=$?
check "a writer nothing in the app uses is refused" "$ST" "1"
check "and it is named" "$(says "$OUT" "OrphanWriter")" "yes"

# 2b. A COMMENT IS NOT A CALLER: a header naming `OrphanWriter.write` elsewhere
#     passed the very writers this exists to find.
printf '// OrphanWriter.write is what ovation#999 will call.\n/* OrphanWriter(modelContainer:) */\n' > "$TREE/App/Mentions.swift"
OUT="$(run_check)"; ST=$?
check "a writer only named in comments elsewhere is still unwired" "$ST" "1"

# 3. LISTED WITH ITS ISSUE, it is allowed, because a writer landing one commit
#    before its screen is legitimate and common. The listing is the record.
printf 'OrphanWriter\tovation#999\tits screen is not built yet\n' > "$TREE/scripts/unwired-writers.tsv"
OUT="$(run_check)"; ST=$?
check "an unwired writer listed with the issue that wires it passes" "$ST" "0"
check "and it is still said, with its issue, rather than going quiet" "$(says "$OUT" "ovation#999")" "yes"

# 4. A LISTING WITH NO ISSUE is refused: an exemption must say what ends it (L129, L233).
printf 'OrphanWriter\t\tlater\n' > "$TREE/scripts/unwired-writers.tsv"
OUT="$(run_check)"; ST=$?
check "a listing that names no issue is refused" "$ST" "1"

# 5. A STALE LISTING: the writer is wired now, so its entry is refused, or the list
#    would go on excusing writers that no longer need it (L346).
reset_tree; actor UsedWriter
printf 'let w = UsedWriter(modelContainer: c)\n' > "$TREE/App/Caller.swift"
printf 'UsedWriter\tovation#999\tits screen is not built yet\n' > "$TREE/scripts/unwired-writers.tsv"
OUT="$(run_check)"; ST=$?
check "a listing for a writer that is now wired is refused as stale" "$ST" "1"
check "and it says to remove that line" "$(says "$OUT" "remove it from")" "yes"

harness_end
