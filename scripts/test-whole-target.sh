#!/bin/bash
# Whether the whole target check can actually tell a bare plain button from none.
#
# ovation#615. Every case here drives the check over a STAGED tree rather than
# this repository, because a guard verified only against the current tree passes
# for as long as that tree happens to be clean and says nothing at all about what
# it would catch (L1, L2).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/lib/test-harness.sh"
harness_begin "whole target tests" 26

TARGET="scripts/check-whole-target.sh"
require_target "$TARGET"
harness_temp_dir WORK

OWNER_BODY='struct WholeTarget: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: configuration.trigger) { configuration.label.contentShape(area) }
            .buttonStyle(.plain)
    }
}'

# A STAGED TREE SHAPED LIKE THE REAL ONE: the style where the check expects it,
# plus whatever a case adds.
stage() {
    local root="$WORK/$1"
    rm -rf "$root"
    mkdir -p "$root/Ovation/App" "$root/Ovation/Roster"
    printf '%s\n' "$OWNER_BODY" > "$root/Ovation/App/WholeTarget.swift"
    printf '%s' "$root"
}

run_check() { OVATION_REPO_ROOT="$1" "./$TARGET" 2>&1; }
says() { if grep -qF -- "$2" <<< "$1"; then echo yes; else echo no; fi; }

# ---------------------------------------------------------------------------
# 1. THE TREE AS IT SHOULD BE: buttons that go through the style.
ROOT="$(stage clean)"
printf 'Button("Invoices") {}\n    .buttonStyle(WholeTarget(RoundedRectangle(cornerRadius: 5)))\n' \
    > "$ROOT/Ovation/Roster/ShellView.swift"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a tree whose buttons go through WholeTarget passes" "$STATUS" "0"
check "and it names the file it allowed" "$(says "$OUT" "WholeTarget.swift")" "yes"

# ---------------------------------------------------------------------------
# 2. A BARE PLAIN BUTTON, WHICH IS THE WHOLE POINT.
ROOT="$(stage bare)"
printf 'Button("Invoices") {}\n    .buttonStyle(.plain)\n' > "$ROOT/Ovation/Roster/ShellView.swift"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a bare plain style button is refused" "$STATUS" "1"
check "and the refusal names the file and line" "$(says "$OUT" "ShellView.swift:2")" "yes"
check "and what to use instead" "$(says "$OUT" ".buttonStyle(WholeTarget())")" "yes"

# ---------------------------------------------------------------------------
# 3. EVERY SPELLING OF THE STYLE. A guard matching one spelling of a thing is
#    walked round by the next person to write it differently (L247).
ROOT="$(stage spaced)"
printf 'Button("a") {}.buttonStyle( .plain )\n' > "$ROOT/Ovation/Roster/ShellView.swift"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "the shorthand with spaces inside is refused" "$STATUS" "1"

ROOT="$(stage typed)"
printf 'Button("a") {}.buttonStyle(PlainButtonStyle())\n' > "$ROOT/Ovation/Roster/ShellView.swift"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "the style named by its type is refused" "$STATUS" "1"

# 3b. CALLS, NOT LINES (review of #644). The first version read one line at a
#     time, and each of these passed it with the "every chromeless button" OK.
ROOT="$(stage split)"
printf 'Button("a") {}\n    .buttonStyle(\n        .plain)\n' > "$ROOT/Ovation/Roster/ShellView.swift"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a call split across lines is refused" "$STATUS" "1"
check "and it is named at the line the call starts" "$(says "$OUT" "ShellView.swift:2")" "yes"

ROOT="$(stage borderless)"
printf 'Button("a") {}.buttonStyle(.borderless)\n' > "$ROOT/Ovation/Roster/ShellView.swift"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "the borderless style, which hit tests the same way, is refused" "$STATUS" "1"

ROOT="$(stage borderless-typed)"
printf 'Button("a") {}.buttonStyle(BorderlessButtonStyle())\n' > "$ROOT/Ovation/Roster/ShellView.swift"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "and so is its type" "$STATUS" "1"

ROOT="$(stage plain-as)"
printf 'let style = .plain as PlainButtonStyle\n' > "$ROOT/Ovation/Roster/ShellView.swift"
printf 'let other = .borderless as BorderlessButtonStyle\n' > "$ROOT/Ovation/Roster/Other.swift"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "the shorthand handed on as a value is refused" "$STATUS" "1"
check "in both of its spellings" "$(says "$OUT" "Other.swift:1")" "yes"

# A COMMENT OR A STRING ABOUT THE STYLE IS PROSE, even across lines (L673).
ROOT="$(stage prose-block)"
printf '/* never\n   .buttonStyle(.plain) here */\nlet why = "not .buttonStyle(.borderless)"\nText("a")\n' \
    > "$ROOT/Ovation/Roster/ShellView.swift"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a block comment and a string naming the style are not refused" "$STATUS" "0"

# A STRING INSIDE AN INTERPOLATION IS STILL INSIDE THE STRING (ovation#665).
# A literal read as running to the next quote ends at the quote that opens the
# nested string, so the nested string's words were read as code.
ROOT="$(stage nested)"
cat > "$ROOT/Ovation/Roster/ShellView.swift" <<'SWIFT'
Text("\(open ? "not .buttonStyle(.plain)" : "")")
Text("\(label("\(inner ? "PlainButtonStyle" : "")"))")
SWIFT
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a style named in a string nested in an interpolation is not refused" "$STATUS" "0"

ROOT="$(stage raw)"
cat > "$ROOT/Ovation/Roster/ShellView.swift" <<'SWIFT'
let why = #"a "quoted" .buttonStyle(.borderless) note"#
SWIFT
OUT="$(run_check "$ROOT")"
STATUS=$?
check "nor one in a raw string carrying its own quotes" "$STATUS" "0"

# And blanking a whole literal must not swallow the code after it.
ROOT="$(stage nested-then-code)"
cat > "$ROOT/Ovation/Roster/ShellView.swift" <<'SWIFT'
Button("\(open ? "a" : "b")") {}
    .buttonStyle(.plain)
let after = #"x"# ; Button("c") {}.buttonStyle(.borderless)
SWIFT
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a real style after an interpolated string is still refused" "$STATUS" "1"
check "and so is one after a raw string, at its own line" "$(says "$OUT" "ShellView.swift:3")" "yes"

# ---------------------------------------------------------------------------
# 4. MORE THAN ONE IS ALL REPORTED, not only the first.
ROOT="$(stage several)"
mkdir -p "$ROOT/Ovation/Invoices"
printf 'Button("a") {}.buttonStyle(.plain)\n' > "$ROOT/Ovation/Roster/ShellView.swift"
printf 'Button("b") {}.buttonStyle(.plain)\n' > "$ROOT/Ovation/Invoices/PopupList.swift"
OUT="$(run_check "$ROOT")"
check "the first of two is named" "$(says "$OUT" "ShellView.swift")" "yes"
check "and so is the second" "$(says "$OUT" "PopupList.swift")" "yes"

# ---------------------------------------------------------------------------
# 5. A COMMENT ABOUT THE STYLE IS PROSE, NOT A BUTTON (L673), and refusing it
#    would refuse the sentence explaining why the style is not used.
ROOT="$(stage prose)"
printf '    // not .buttonStyle(.plain), which hit tests only the words\nText("a")\n' \
    > "$ROOT/Ovation/Roster/ShellView.swift"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a comment naming the style is not refused" "$STATUS" "0"

# ---------------------------------------------------------------------------
# 6. THE OWNER MUST STILL DO THE JOB. An owner that has lost its content shape
#    sends every site to a style that no longer gives them one (L96, L98, L400).
ROOT="$(stage gutted)"
printf 'struct WholeTarget: PrimitiveButtonStyle {\n    Button(action: t) { l }.buttonStyle(.plain)\n}\n' \
    > "$ROOT/Ovation/App/WholeTarget.swift"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "an owner with no content shape is refused" "$STATUS" "1"
check "and it says every other file is now exempt by accident" \
      "$(says "$OUT" "exempt by accident")" "yes"

ROOT="$(stage unplain)"
printf 'struct WholeTarget { func b() -> some View { l.contentShape(area) } }\n' \
    > "$ROOT/Ovation/App/WholeTarget.swift"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "an owner that is no longer the plain style is refused" "$STATUS" "1"

# ---------------------------------------------------------------------------
# 7. AND A TREE WITH NO STYLE AT ALL IS REFUSED, rather than passing because
#    there is nothing left to compare against.
ROOT="$WORK/empty"
rm -rf "$ROOT"
mkdir -p "$ROOT/Ovation"
OUT="$(run_check "$ROOT")"
STATUS=$?
check "a tree with no style is refused" "$STATUS" "1"
check "and it says the guard is checking nothing" "$(says "$OUT" "checking nothing")" "yes"

harness_end
