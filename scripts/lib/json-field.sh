# Reading one field out of a JSON file, on any machine. ovation#152.
#
# WHY IT IS A LIBRARY. Two guards read JSON, `check-booking-queue.sh` and
# `check-sibling-installs.sh`, and both did it with `plutil`, which exists only
# on macOS. The Linux job added by ovation#152 found the first on its first run
# and the second on its next: every well formed file read as unreadable, so each
# check reported a fault about healthy data. A second copy of a reader is a second
# thing to keep correct, and the copy that falls behind is the one nobody is
# looking at (L613, L370).
#
# THE NOTE plutil EARNED IS KEPT, because it is about plutil rather than about
# either caller: `plutil -lint` reports "Unexpected character {" on the very JSON
# that `plutil -extract` reads without complaint (measured 2026-09-06), so the
# tool named for the job was the wrong one even on the platform that has it.
#
# python3 is already required by this repository's other guards, so this adds no
# dependency; it removes one.

# Whether the file parses as JSON at all. An unreadable file is NOT an empty one,
# and every caller here draws that distinction itself.
readable_json() {
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" >/dev/null 2>&1
}

# One TOP LEVEL field, printed raw, or nothing when it is absent.
#
# A container prints `present` rather than its contents, because every caller
# only asks whether it is there, and printing a client or venue object would put
# real names into output that reaches transcripts and scrollback (L222).
json_field() {
    python3 - "$1" "$2" <<'PYFIELD' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1]) as fh:
        data = json.load(fh)
except Exception:
    raise SystemExit(1)
if not isinstance(data, dict) or sys.argv[2] not in data:
    raise SystemExit(0)
value = data[sys.argv[2]]
if isinstance(value, (dict, list)):
    print("present")
elif isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    raise SystemExit(0)
else:
    print(value)
PYFIELD
}
