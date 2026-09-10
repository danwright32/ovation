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
import datetime
import statistics
import sys


UNREADABLE = collections.Counter()


def numeric(text, column="unnamed"):
    """A number, or None. NEVER a zero standing in for one.

    Callers used to write `numeric(x) or 0`, which turns a value the script
    could not read into a confident zero: an unreadable discount was counted as
    NO discount, and nothing said so (L11). Every refusal is counted here and
    reported at the end, so a malformed export is visible rather than quietly
    scored as a tidy answer."""
    raw = (text or "").strip()
    cleaned = raw.replace("$", "").replace(",", "")
    if cleaned == "":
        return None
    try:
        return float(cleaned)
    except ValueError:
        UNREADABLE[column] += 1
        return None


def a_date(text):
    """A date, or None. Never today's date standing in for a missing one."""
    raw = (text or "").strip()
    if not raw:
        return None
    for shape in ("%Y-%m-%d", "%m/%d/%Y", "%d/%m/%Y"):
        try:
            return datetime.datetime.strptime(raw, shape).date()
        except ValueError:
            continue
    UNREADABLE["Date"] += 1
    return None


def payments_with_another_open(by_invoice):
    """How often a payment arrived while another of that client's invoices was open.

    ovation#190. PRD 14j says that with more than one invoice open Ovation
    applies the money to neither and asks, and nothing knew how often that
    happens. This is the closest the export can come: for every invoice that was
    paid, count the client's OTHER invoices that were issued before that payment
    and not yet paid at it.

    IT IS AN UPPER BOUND ON THE SITUATION, NOT A COUNT OF IT, and the caller says
    so. The export carries no payment amounts and no balances, so a payment that
    left money over is indistinguishable here from one that settled its invoice
    exactly, and money HELD is what PRD 14j is actually about.

    AN INVOICE WITH NO PAID DATE IS OPEN FROM ITS ISSUE DATE ONWARDS, never
    absent. The real export has one, the overdue invoice, and treating it as
    closed would make every later payment look like the only one outstanding.
    """
    spans = []
    for number, lines in by_invoice.items():
        row = lines[0]
        issued = a_date(row.get("Date Issued"))
        if issued is None:
            continue
        spans.append((row["Client Name"], issued, a_date(row.get("Date Paid")), number))

    measured = 0
    with_another = 0
    clients = set()
    for client, issued, paid, number in spans:
        if paid is None:
            continue
        measured += 1
        others = [s for s in spans
                  if s[0] == client and s[3] != number
                  and s[1] <= paid and (s[2] is None or s[2] > paid)]
        if others:
            with_another += 1
            clients.add(client)
    return measured, with_another, clients


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

    hours = [numeric(r["Quantity"], "Quantity") for r in issued if numeric(r["Quantity"], "Quantity") is not None]
    if hours:
        on_quarter = sum(1 for h in hours if abs(h * 4 - round(h * 4)) < 1e-9)
        print("\nHOURS BILLED")
        print(f"  lines                      {len(hours)}")
        print(f"  median                     {statistics.median(hours)}")
        print(f"  longest                    {max(hours)}")
        print(f"  exactly 1.0                {sum(1 for h in hours if h == 1.0) / len(hours):6.1%}")
        print(f"  on a quarter hour          {on_quarter / len(hours):6.1%}")

    discounted = {r["Invoice #"] for r in issued if numeric(r["Discount Percentage"], "Discount Percentage") not in (None, 0.0)}
    credits = {r["Invoice #"] for r in issued if (numeric(r["Line Subtotal"], "Line Subtotal") or 0) < 0}
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

    taxed = {r["Invoice #"] for r in issued if numeric(r["Tax 1 Amount"], "Tax 1 Amount") not in (None, 0.0)}
    print(f"\nINVOICES CHARGING TAX        {len(taxed):4d}   {len(taxed) / total:6.1%}")

    # ovation#190. Counted from the two dates the export does carry, and the
    # sentence about payment amounts is part of the measurement rather than a
    # caveat on it: without it the number reads as how often money was held.
    print("\nPAYMENTS ARRIVING WITH ANOTHER INVOICE OPEN")
    if "Date Paid" not in (rows[0].keys() if rows else {}):
        print("  this export has no Date Paid column, so nothing here was measured")
    else:
        measured, with_another, clients = payments_with_another_open(by_invoice)
        print(f"  payments measured          {measured:4d}")
        if measured:
            print(f"  arriving with another open {with_another:4d}   {with_another / measured:6.1%}")
        else:
            print(f"  arriving with another open {with_another:4d}")
        print(f"  clients it happened to     {len(clients):4d}")
        print("  The export carries no payment amounts and no balances, so this is how often the"
              "\n  SITUATION arose, never how often money was actually held.")

    # Said out loud, and said even when it is zero, because "no unreadable
    # values" and "nobody looked" must not be the same output (L98).
    print("\nVALUES THE SCRIPT COULD NOT READ")
    if UNREADABLE:
        for column, count in sorted(UNREADABLE.items()):
            print(f"  {column:<22} {count:4d}")
        print("  every figure above was computed WITHOUT these.")
    else:
        print("  none, in any column it reads")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
