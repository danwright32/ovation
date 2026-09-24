#!/bin/bash
# Say whether the installed Ovation is behind main, from the record the installer wrote.
#
# ovation#389. `scripts/build-install.sh` writes installed-build.json, holding the
# commit the installed app was built from, and nothing read it. Measured
# 2026-09-17: the installed app was four commits and four days behind main and
# nothing said so; it surfaced only because a Settings tab Dan wanted was not
# there. Dan opens Ovation to do real invoicing and reasonably assumes what he
# sees is what shipped. Stored data needs a reader, not just a writer (L46, L3).
#
# THE READER IS THE POST-MERGE STEP. This repository's CLAUDE.md names this
# script as the step after every merge, so the session that just merged is the
# one that tells Dan his copy is behind and gives him the command. A line printed
# nowhere anybody reads would be a counter rather than a detector (L357).
#
# Judged against origin/main where the checkout has it, else main, because the
# question is what has shipped, and a local main can lag (L454). Nothing here
# fetches: the caller has just merged, and fetching is the caller's to decide.
#
# Exit codes: 0 the install is main's tip, 1 it is behind or not on main,
# 2 there is no record, or it names no readable commit, or no main to judge by.
set -uo pipefail

RECORD="${OVATION_INSTALLED_RECORD:-$HOME/Library/Application Support/Ovation/installed-build.json}"

if [ ! -f "$RECORD" ]; then
    echo "CANNOT MEASURE: there is no install record at $RECORD, so whether the installed"
    echo "    Ovation is current cannot be told. It was never installed through"
    echo "    bash scripts/build-install.sh, which is what writes one."
    exit 2
fi

commit="$(python3 -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("commit") or "")
except Exception:
    print("")' "$RECORD" 2>/dev/null)"
if ! grep -qiE '^[0-9a-f]{7,40}$' <<< "$commit"; then
    echo "CANNOT MEASURE: the install record at $RECORD could not be read for a commit,"
    echo "    so whether the installed Ovation is current cannot be told."
    exit 2
fi

main=""
for ref in origin/main main; do
    if git rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then main="$ref"; break; fi
done
if [ -z "$main" ]; then
    echo "CANNOT MEASURE: this checkout has neither origin/main nor main to judge the install by."
    exit 2
fi
tip="$(git rev-parse "$main")"

if [ "$(git rev-parse "$commit" 2>/dev/null)" = "$tip" ]; then
    echo "OK: the installed Ovation was built from ${commit:0:8}, which is $main's tip."
    exit 0
fi
if ! git merge-base --is-ancestor "$commit" "$main" 2>/dev/null; then
    echo "BEHIND: the installed Ovation was built from ${commit:0:8}, which is not on main,"
    echo "    so what is running is not what shipped. Reinstall from main:"
    echo "    bash scripts/build-install.sh"
    exit 1
fi
behind="$(git rev-list --count "${commit}..${main}")"
echo "BEHIND: the installed Ovation is ${behind} commit(s) behind $main (built from ${commit:0:8})."
echo "    What Dan opens is missing that work. Reinstall with:"
echo "    bash scripts/build-install.sh"
exit 1
