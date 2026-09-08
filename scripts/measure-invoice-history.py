#!/usr/bin/env python3
"""Measure the SHAPE of Dan's invoicing history, for the design record.

ovation#121. Every number the design record and the PRD cite about invoices was
produced by a script written in a session scratchpad and deleted when the
session ended, so nothing could produce any of them again. That is how one of
them came out wrong: filtering on the export's issue date counts drafts as
issued, because the export stamps a date on drafts too, and the reported share
of single line invoices was 85% when it is 80%.

PRINTS COUNTS AND SHARES ONLY. Never a client, a venue, a vendor or a
production title. An earlier version withheld an item name unless it was used by
more than one client, on the reasoning that a vocabulary word cannot be one
client's name. That let a PRODUCTION TITLE through, because a show can be
photographed for two different clients (ovation#23). There is no heuristic here
now: item names are counted, never printed.

Usage: measure-invoice-history.py <freshbooks-export.csv>
"""
import collections
import csv
import statistics
import sys


def numeric(text):
    text = (text or "").replace("$", "").replace(",", "").strip()
    try:
        return float(text)
    except ValueError:
        return None


def issued_rows(rows):
    """Issued means the STATUS says so, never that a date is present.

    The export stamps Date Issued on drafts as well, so filtering on it admits
    41 draft lines and reports a different invoice altogether."""
    return [r for r in rows if (r["Invoice Status"] or "").strip().lower() != "draft"]


def main(argv):
    if len(argv) != 2:
        print(__doc__.strip().splitlines()[-1])
        return 2
    with open(argv[1], newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))

    issued = issued_rows(rows)
    by_invoice = collections.defaultdict(list)
    for row in issued:
        by_invoice[row["Invoice #"]].append(row)
    total = len(by_invoice)
    if not total:
        print("no issued invoices found, so nothing can be measured")
        return 1

    print("INVOICES")
    print(f"  lines in the export        {len(rows)}")
    print(f"  lines on issued invoices   {len(issued)}")
    print(f"  issued invoices            {total}")
    print(f"  distinct clients           {len({r['Client Name'] for r in issued})}")

    lines = collections.Counter(len(v) for v in by_invoice.values())
    print("\nLINES PER INVOICE")
    for n in sorted(lines):
        print(f"  {n:>2}   {lines[n]:4d}   {lines[n] / total:6.1%}")

    hours = [numeric(r["Quantity"]) for r in issued if numeric(r["Quantity"]) is not None]
    if hours:
        on_quarter = sum(1 for h in hours if abs(h * 4 - round(h * 4)) < 1e-9)
        print("\nHOURS BILLED")
        print(f"  lines                      {len(hours)}")
        print(f"  median                     {statistics.median(hours)}")
        print(f"  longest                    {max(hours)}")
        print(f"  exactly 1.0                {sum(1 for h in hours if h == 1.0) / len(hours):6.1%}")
        print(f"  on a quarter hour          {on_quarter / len(hours):6.1%}")

    discounted = {r["Invoice #"] for r in issued if (numeric(r["Discount Percentage"]) or 0) != 0}
    credits = {r["Invoice #"] for r in issued if (numeric(r["Line Subtotal"]) or 0) < 0}
    print("\nHOW OFTEN THE RARE THINGS HAPPEN")
    print(f"  invoices with a discount   {len(discounted):4d}   {len(discounted) / total:6.1%}")
    print(f"  invoices with a credit     {len(credits):4d}   {len(credits) / total:6.1%}")

    # An invoice covers more than one EVENT when it names more than one thing
    # that is not a shared service word. Counted, never printed.
    per_name = collections.defaultdict(set)
    for row in issued:
        per_name[(row["Item Name"] or "").strip().lower()].add(row["Client Name"])
    service_words = {name for name, clients in per_name.items() if len(clients) > 1}
    events = collections.Counter()
    for invoice_lines in by_invoice.values():
        named = {(r["Item Name"] or "").strip().lower() for r in invoice_lines} - service_words
        events[len(named) if named else 1] += 1
    print("\nEVENTS COVERED BY ONE INVOICE")
    for n in sorted(events):
        print(f"  {n:>2}   {events[n]:4d}   {events[n] / total:6.1%}")

    taxed = {r["Invoice #"] for r in issued if (numeric(r["Tax 1 Amount"]) or 0) != 0}
    print(f"\nINVOICES CHARGING TAX        {len(taxed):4d}   {len(taxed) / total:6.1%}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
