#!/bin/bash
# The suite for scripts/check-design-terms-agree.sh.
#
# ovation#98, round D. A client's standing payment terms are set on the Clients
# screen and an invoice's due date is changed on the invoice screen, and PRD 51h
# makes them ONE list: a client whose standing terms offer 21 days, against an
# invoice that cannot produce one, is two vocabularies for a single thing.
#
# In the product that is one constant. In the design record it is two copies,
# because a design file must be one self contained document (ovation#114) and so
# cannot load anything, and two copies of one list with nothing comparing them is
# L370. That already went wrong once in this folder, with a rule fixed in
# rules/time-field.js and left stale in the file that carries it.
#
# THE CLAIM THIS DEFENDS WAS MADE TO DAN. Round D's readout told him the two
# lists are read from one place so they can never come to offer different terms.
# On the day that was said it was false: nothing compared them. A claim made
# while choosing a design is a claim the design owes (L407).
#
# EACH MUTATION ASSERTS ITS OWN REFUSAL BY NAME. A defect large enough to break
# a file makes every check fail at once and is indistinguishable from the one
# that should have (L154), so a suite that only asserted "it refused" would pass
# on a file it could not parse at all.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "the two design files offer the same payment terms" 13

TARGET="scripts/check-design-terms-agree.sh"
require_target "$TARGET"
require_target "docs/design/clients.html"
require_target "docs/design/invoice.html"
harness_temp_dir WORK

# The real files agree, and that is the first thing asserted: a suite that only
# ever runs against damaged copies never proves the check passes anything.
OUT="$("./$TARGET" 2>&1)"
check "the committed files agree" "$?" "0"
case "$OUT" in
    *"On receipt"*) check "it names the terms it compared" "yes" "yes" ;;
    *) check "it names the terms it compared" "$OUT" "should list the terms" ;;
esac

# A copy is made, damaged, and checked, so the real files are never touched.
copy_pair() {
    mkdir -p "$WORK/$1/docs/design"
    cp docs/design/clients.html docs/design/invoice.html "$WORK/$1/docs/design/"
}

run_on() {
    ( cd "$WORK/$1" && "$OLDPWD/$TARGET" docs/design/clients.html docs/design/invoice.html 2>&1 )
}

# 1. A TERM ADDED TO ONE SIDE. The Clients screen offers something no invoice
#    can produce, which is the fault this exists to catch.
copy_pair extra
python3 - "$WORK/extra/docs/design/clients.html" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
old = 'var TERMS = ["On receipt", "7 days", "14 days", "30 days"];'
assert text.count(old) == 1, "the clients file no longer declares TERMS as expected"
open(path, "w", encoding="utf-8").write(
    text.replace(old, 'var TERMS = ["On receipt", "7 days", "14 days", "21 days", "30 days"];'))
PY
OUT="$(run_on extra)"; RC=$?
check "an extra term is refused" "$RC" "1"
case "$OUT" in
    *"21 days"*) check "it names the term that does not agree" "yes" "yes" ;;
    *) check "it names the term that does not agree" "$OUT" "should say 21 days" ;;
esac
case "$OUT" in
    *"clients.html"*) check "it names the file the extra term is in" "yes" "yes" ;;
    *) check "it names the file the extra term is in" "$OUT" "should say clients.html" ;;
esac

# 2. A TERM RENAMED ON ONE SIDE. Same four terms, one spelled differently, which
#    reads as agreement to anybody counting them.
copy_pair renamed
python3 - "$WORK/renamed/docs/design/invoice.html" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
old = '["On receipt", 0]'
assert text.count(old) == 1, "the invoice file no longer declares TERMS as expected"
open(path, "w", encoding="utf-8").write(text.replace(old, '["Upon receipt", 0]'))
PY
OUT="$(run_on renamed)"; RC=$?
check "a renamed term is refused" "$RC" "1"
case "$OUT" in
    *"Upon receipt"*) check "it names the renamed term" "yes" "yes" ;;
    *) check "it names the renamed term" "$OUT" "should say Upon receipt" ;;
esac

# 3. THE ORDER CHANGED. The same four terms in a different order is a different
#    list to a reader, who is choosing from a menu rather than a set.
copy_pair reordered
python3 - "$WORK/reordered/docs/design/clients.html" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
old = 'var TERMS = ["On receipt", "7 days", "14 days", "30 days"];'
open(path, "w", encoding="utf-8").write(
    text.replace(old, 'var TERMS = ["7 days", "On receipt", "14 days", "30 days"];'))
PY
OUT="$(run_on reordered)"; RC=$?
check "a different order is refused" "$RC" "1"
case "$OUT" in
    *order*) check "it says the order is what differs" "yes" "yes" ;;
    *) check "it says the order is what differs" "$OUT" "should mention the order" ;;
esac

# 4. THE DECLARATION IS GONE. A check that cannot find its subject must refuse,
#    never report agreement between two lists it never read (L98).
copy_pair missing
python3 - "$WORK/missing/docs/design/clients.html" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
old = 'var TERMS = ["On receipt", "7 days", "14 days", "30 days"];'
open(path, "w", encoding="utf-8").write(text.replace(old, 'var TERMS_GONE = [];'))
PY
OUT="$(run_on missing)"; RC=$?
check "a missing declaration is refused rather than passed" "$RC" "2"
case "$OUT" in
    *"no payment terms"*) check "it says the declaration is missing" "yes" "yes" ;;
    *) check "it says the declaration is missing" "$OUT" "should say no payment terms" ;;
esac

# 5. A FILE THAT IS NOT THERE. Same rule, different cause, and it says which,
#    because one message answering for both is one outcome in practice (L11).
OUT="$("./$TARGET" docs/design/clients.html "$WORK/nowhere.html" 2>&1)"; RC=$?
check "an absent file is refused" "$RC" "2"
case "$OUT" in
    *"cannot read"*) check "it says it could not read the file" "yes" "yes" ;;
    *) check "it says it could not read the file" "$OUT" "should say cannot read" ;;
esac

harness_end
