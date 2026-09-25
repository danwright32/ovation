#!/bin/bash
# Every writer the app declares is used by the app, or is listed with the issue that wires it,
# and every write closure RootView takes is passed by the app and every Edit menu action read.
#
# ovation#441. InvoiceNumberAllocator, InvoiceCloser and PaymentAllocator were each
# built with their own tests and called by nothing in the app, so each read as done
# from every angle but the one that counts (L3), and a backlog read through the
# domain layer said the milestone was further along than it is.
#
# ovation#485. The second half: a writer the app constructs reaches Dan only if the
# closure built around it is passed down, and a layer that drops one draws the same
# screen as a launch with no store. Cases 6 onward are that judgement, against a
# fixture shaped like the app's own RootView, App and InvoiceEditCommand.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "writers wired tests" 21

TARGET="scripts/check-writers-wired.sh"
require_target "$TARGET"
harness_temp_dir WORK

TREE="$WORK/tree"
actor() { printf '@ModelActor\nactor %s {\n    func write() {}\n}\n' "$1" > "$TREE/App/$1.swift"; }
# THE WIRED SHAPE OF THE APP, which every case starts from: RootView takes two write
# closures and the menu's command, the app passes all three, and it reads the menu's
# one action back through the object it passed.
root_view() { printf 'struct RootView: View {\n    var writeTime: (() async -> String?)?\n    var writeDiscount: (() async -> String?)?\n    var edits: InvoiceEditCommand?\n}\n' > "$TREE/App/RootView.swift"; }
menu_command() { printf 'final class InvoiceEditCommand {\n    var open: Open?\n    var addDiscount: ((Int) -> Void)?\n}\n' > "$TREE/App/InvoiceEditCommand.swift"; }
the_app() { printf 'struct TheApp: App {\n    var body: some Scene {\n        RootView(%s)\n    }\n    func add() { %s }\n}\n' "$1" "$2" > "$TREE/App/TheApp.swift"; }
WIRED_ARGS='writeTime: opened.map { c in { nil } }, writeDiscount: opened.map { c in { nil } }, edits: edits'
WIRED_READ='guard let add = edits.addDiscount else { return }; add(1)'
reset_tree() { [ -n "$WORK" ] || exit 1; rm -rf "$TREE"; mkdir -p "$TREE/App" "$TREE/scripts"; : > "$TREE/scripts/unwired-writers.tsv"; root_view; menu_command; the_app "$WIRED_ARGS" "$WIRED_READ"; }
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

# 6. The wired shape passes, and says it judged the passing down, not only the types.
reset_tree; actor UsedWriter
printf 'let w = UsedWriter(modelContainer: c)\n' > "$TREE/App/Caller.swift"
OUT="$(run_check)"; ST=$?
check "an app passing every closure and reading every action passes" "$ST" "0"
check "and it says the closures were judged" "$(says "$OUT" "every closure RootView is given")" "yes"

# 7. THE DEFECT, ovation#485: a layer drops a write, and the screen it feeds is the
#    screen of a launch with no store.
the_app 'writeTime: opened.map { c in { nil } }, edits: edits' "$WIRED_READ"
OUT="$(run_check)"; ST=$?
check "an app that does not pass a write closure is refused" "$ST" "1"
check "and the dropped closure is named" "$(says "$OUT" "without passing writeDiscount")" "yes"

# 8. PASSED AS A LITERAL NIL is the same defect spelled differently.
the_app 'writeTime: nil, writeDiscount: opened.map { c in { nil } }, edits: edits' "$WIRED_READ"
OUT="$(run_check)"; ST=$?
check "a write closure passed as nil is refused" "$ST" "1"
check "and it is named" "$(says "$OUT" "without passing writeTime")" "yes"

# 9. A COMMENT IS NOT AN ARGUMENT.
the_app 'writeTime: opened.map { c in { nil } }, // writeDiscount: later
                 edits: edits' "$WIRED_READ"
OUT="$(run_check)"; ST=$?
check "a write closure only named in a comment is still refused" "$ST" "1"

# 10. THE MENU: an action nothing reads is an entry present, enabled and doing nothing.
#     A writer's own method of the same name is not a read of the menu's action.
the_app "$WIRED_ARGS" 'try await writer.addDiscount(1)'
OUT="$(run_check)"; ST=$?
check "a menu action the app never reads through its command is refused" "$ST" "1"
check "and it is named" "$(says "$OUT" "never reads edits.addDiscount")" "yes"

# 11. SETTING IT IS NOT READING IT.
the_app "$WIRED_ARGS" 'edits.addDiscount = nil'
OUT="$(run_check)"; ST=$?
check "an action only ever assigned is refused as unread" "$ST" "1"

# 12. NOTHING TO JUDGE IS NOT A PASS (L98): with no RootView declared the check says
#     it could not measure, rather than finding every closure passed.
rm -f "$TREE/App/RootView.swift"; the_app "$WIRED_ARGS" "$WIRED_READ"
OUT="$(run_check)"; ST=$?
check "with no RootView to read the closures from, it cannot measure" "$ST" "2"

harness_end
