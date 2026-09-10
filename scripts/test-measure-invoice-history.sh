#!/bin/bash
# The suite for scripts/measure-invoice-history.py.
#
# ovation#121 wrote the script so the numbers the design record and the PRD cite
# could be produced again. ovation#86 is why it now has a suite: it is the one
# tool here that opens Dan's REAL invoice history, and it was watched by nothing.
#
# EVERY FIXTURE IS FABRICATED. Nothing here reads the real export, and the client
# names below are invented, so the suite can be run and its output read anywhere
# (docs/PRIVACY-FLOOR.md).
#
# THE CASE THAT MATTERS MOST is the draft. The wrong number this script exists to
# prevent came from filtering on the export's issue date, which is stamped on
# drafts too, so drafts were counted as issued and the reported share of single
# line invoices was 85% when it is 80%. That predicate is asserted directly here.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "invoice history measurement tests" 22

TARGET="scripts/measure-invoice-history.py"
require_target "$TARGET"
harness_temp_dir WORK

HEADER='Invoice #,Invoice Status,Client Name,Item Name,Quantity,Line Subtotal,Discount Percentage,Tax 1 Amount,Date Issued'
run_on() { "./$TARGET" "$1" 2>&1; }
status_on() { "./$TARGET" "$1" >/dev/null 2>&1; printf '%s' "$?"; }
field() { run_on "$1" | grep -E "^  $2 " | awk '{print $NF}'; }
# A line that carries a count AND a share ends in the share, so the count is one
# field back. Named rather than inlined, because `field` reading the last column
# is right for every other line in this report and wrong only for these.
counted() { run_on "$1" | grep -E "^  $2 " | awk '{print $(NF-1)}'; }

# Two issued invoices, one of them two lines, and a DRAFT carrying a date.
cat > "$WORK/basic.csv" <<CSV
$HEADER
1101,Paid,Northmoor Ensemble,Photography,2,500,0,44.38,2026-01-04
1102,Sent,Harbour Line Theatre,Photography,1,250,0,22.19,2026-01-06
1102,Sent,Harbour Line Theatre,Rush turnaround,1,100,0,8.88,2026-01-06
1103,Draft,Northmoor Ensemble,Photography,4,1000,0,88.75,2026-01-09
CSV
check "an export with issued invoices measures successfully" "$(status_on "$WORK/basic.csv")" "0"
check "a DRAFT is not counted as issued, whatever date it carries" \
    "$(field "$WORK/basic.csv" 'issued invoices')" "2"
check "and the draft's line is out of the line count too" \
    "$(field "$WORK/basic.csv" 'lines on issued invoices')" "3"
check "the export's own total is reported beside it, so the two can be compared" \
    "$(field "$WORK/basic.csv" 'lines in the export')" "4"
check "distinct clients counts the issued ones" \
    "$(field "$WORK/basic.csv" 'distinct clients')" "2"

# THE PRIVACY FLOOR. It reads real client names by construction and must print
# counts only (docs/PRIVACY-FLOOR.md, L222).
check "no client name reaches the output" \
    "$(run_on "$WORK/basic.csv" | grep -ci 'Northmoor\|Harbour Line')" "0"
check "and no item name does either, since a production title is one" \
    "$(run_on "$WORK/basic.csv" | grep -ci 'Photography\|Rush turnaround')" "0"

# AN UNREADABLE VALUE IS COUNTED AND SAID, never scored as a confident zero.
cat > "$WORK/unreadable.csv" <<CSV
$HEADER
1101,Paid,Northmoor Ensemble,Photography,2,500,0,44.38,2026-01-04
1102,Sent,Harbour Line Theatre,Photography,not a number,250,0,22.19,2026-01-06
CSV
check "a value that cannot be read is counted rather than treated as zero" \
    "$(run_on "$WORK/unreadable.csv" | grep -cE '^  Quantity +1$')" "1"
check "and the report says the figures were computed without it" \
    "$(run_on "$WORK/unreadable.csv" | grep -c 'computed WITHOUT these')" "1"

# NOTHING UNREADABLE IS SAID OUT LOUD TOO, or "nobody looked" and "all clean"
# are the same output (L98).
check "a clean export says so rather than printing nothing" \
    "$(run_on "$WORK/basic.csv" | grep -c 'none, in any column it reads')" "1"

# AN EXPORT WITH NOTHING ISSUED IS NOT A SUCCESSFUL MEASUREMENT.
cat > "$WORK/drafts-only.csv" <<CSV
$HEADER
1103,Draft,Northmoor Ensemble,Photography,4,1000,0,88.75,2026-01-09
CSV
check "an export holding only drafts refuses rather than reporting zeroes" \
    "$(status_on "$WORK/drafts-only.csv")" "1"
check "and it says nothing could be measured" \
    "$(run_on "$WORK/drafts-only.csv" | grep -c 'nothing can be measured')" "1"

# The rare things, which the design record cites as shares.
cat > "$WORK/rare.csv" <<CSV
$HEADER
1101,Paid,Northmoor Ensemble,Photography,2,500,10,44.38,2026-01-04
1102,Sent,Harbour Line Theatre,Photography,1,250,0,22.19,2026-01-06
1102,Sent,Harbour Line Theatre,Referral credit,1,-250,0,0,2026-01-06
CSV
check "an invoice carrying a discount is counted as one" \
    "$(run_on "$WORK/rare.csv" | grep -cE 'invoices with a discount +1 ')" "1"
check "and an invoice carrying a negative line is counted as a credit" \
    "$(run_on "$WORK/rare.csv" | grep -cE 'invoices with a credit +1 ')" "1"

# ---------------------------------------------------------------------------
# PAYMENTS ARRIVING WITH ANOTHER INVOICE OPEN (ovation#190). PRD 14j says that
# with more than one invoice open Ovation applies the money to neither and asks,
# and nothing knew how often that happens. It is measured from the two dates the
# export does carry, because the one thing it does NOT carry is payment amounts,
# so how often money was actually held cannot be measured from it at all.
# ---------------------------------------------------------------------------
PAID_HEADER="$HEADER,Date Paid"

# One client with two invoices whose open periods OVERLAP, and one with a single
# invoice. 1102 is paid on the 10th while 1101 is still open, so exactly one of
# the two payments arrives with another invoice open. 1101 is paid on the 20th,
# by which time 1102 is closed, which is the case that must NOT count.
cat > "$WORK/overlap.csv" <<CSV
$PAID_HEADER
1101,Paid,Northmoor Ensemble,Photography,2,500,0,44.38,2026-01-04,2026-01-20
1102,Paid,Northmoor Ensemble,Photography,1,250,0,22.19,2026-01-06,2026-01-10
1103,Paid,Harbour Line Theatre,Photography,1,250,0,22.19,2026-01-06,2026-01-08
CSV
check "every payment in the export is counted, so the share has a denominator" \
    "$(field "$WORK/overlap.csv" 'payments measured')" "3"
check "a payment arriving while another invoice is open is counted" \
    "$(counted "$WORK/overlap.csv" 'arriving with another open')" "1"
check "and the client it happened to is counted once, not per payment" \
    "$(field "$WORK/overlap.csv" 'clients it happened to')" "1"

# AN INVOICE WITH NO PAID DATE IS STILL OPEN, not absent. The real export has
# exactly one, the overdue invoice, and counting it as closed would make every
# payment after it look like the only one outstanding.
cat > "$WORK/stillopen.csv" <<CSV
$PAID_HEADER
1101,Overdue,Northmoor Ensemble,Photography,2,500,0,44.38,2026-01-04,
1102,Paid,Northmoor Ensemble,Photography,1,250,0,22.19,2026-01-06,2026-01-10
CSV
check "an issued invoice with no paid date is open, so the payment beside it counts" \
    "$(counted "$WORK/stillopen.csv" 'arriving with another open')" "1"
check "and it is not itself counted as a payment" \
    "$(field "$WORK/stillopen.csv" 'payments measured')" "1"

# WHAT IT CANNOT MEASURE IS SAID OUT LOUD. The export carries no payment amounts
# and no balances, so nothing here can say how often money was actually HELD:
# this is an upper bound on the situation, not a count of it. Silence would let
# the number be read as the thing it is a bound on (L11, L98).
check "the section says what the export cannot answer" \
    "$(run_on "$WORK/overlap.csv" | grep -c 'no payment amounts')" "1"

# AN EXPORT WITHOUT THE COLUMN AT ALL refuses this measurement by name rather
# than reporting zero, which is what every other fixture in this suite is.
check "an export with no Date Paid column says so instead of reporting none" \
    "$(run_on "$WORK/basic.csv" | grep -c 'no Date Paid column')" "1"

check "an export that is not there cannot be measured" "$(status_on "$WORK/nowhere.csv")" "1"

harness_end
