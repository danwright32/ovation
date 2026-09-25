#!/bin/bash
# ovation-runs-on: macos
# THROWAWAY PROBE FOR ovation#497, on a branch that is never merged. It asks the
# compiler CI selects whether it has the defect that branch measured on Xcode
# 27.0: a @Model class losing its Hashable conformance inside one batch mode
# frontend job. It REPORTS rather than judges, because either answer is the
# measurement wanted; only the control building is asserted.
set -u
if ! command -v xcrun >/dev/null 2>&1; then
  echo "CANNOT MEASURE: no xcrun here, so no Swift compiler with SwiftData."
  exit 2
fi
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
printf 'import SwiftData\n\n@Model\nfinal class Client {\n    var name: String\n    init(name: String) { self.name = name }\n}\n' > "$DIR/Client.swift"
printf 'import SwiftData\n\n@Model\nfinal class Invoice {\n    var client: Client?\n    init() {}\n}\n' > "$DIR/Invoice.swift"
printf 'func banked(_ invoice: Invoice) -> Bool {\n    (invoice.client?.name ?? "").isEmpty\n}\n' > "$DIR/Reader.swift"
printf 'func clients(_ held: [Client: Int]) -> Set<Client> {\n    Set(held.keys)\n}\n' > "$DIR/User.swift"
mkdir "$DIR/out"
F="$DIR/Client.swift $DIR/Invoice.swift $DIR/Reader.swift $DIR/User.swift"
echo "PROBE 497 compiler: $(xcrun swiftc --version 2>&1 | head -1)"
echo "PROBE 497 xcode: $(xcodebuild -version 2>&1 | tr '\n' ' ')"
( cd "$DIR/out" && xcrun swiftc -c -target arm64-apple-macos26.0 -module-name Repro -wmo $F ) > "$DIR/wmo.log" 2>&1
wmo=$?
( cd "$DIR/out" && rm -f ./*.o && xcrun swiftc -c -target arm64-apple-macos26.0 -module-name Repro -enable-batch-mode -driver-batch-count 2 -j1 $F ) > "$DIR/batch.log" 2>&1
batch=$?
errs=$(grep -c "does not conform to protocol 'Hashable'" "$DIR/batch.log")
echo "PROBE 497 control, whole module: exit ${wmo}"
echo "PROBE 497 two batches: exit ${batch}, ${errs} Hashable lines"
grep "error:" "$DIR/batch.log" | head -4
if [ "${wmo}" -ne 0 ]; then
  cat "$DIR/wmo.log"
  echo "FAIL: the control did not build, so the probe measured nothing."
  exit 1
fi
if [ "${batch}" -ne 0 ] && [ "${errs}" -gt 0 ]; then
  echo "PROBE 497 VERDICT: REPRODUCES on this compiler"
else
  echo "PROBE 497 VERDICT: DOES NOT REPRODUCE on this compiler"
fi
exit 0
