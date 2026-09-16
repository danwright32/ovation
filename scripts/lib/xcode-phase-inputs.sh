#!/bin/bash
# Which paths the Xcode phase of a test run can read, worked out from the tree.
#
# ovation#358. The push gate skips that phase (the project, both builds, the pure
# and hosted Swift suites and the wait for the sibling locks) when nothing being
# pushed can reach it. Until this file it decided from a fixed list of paths no
# build could open, and ovation#154 took scripts/ off that list because the build
# command lives there. That was right about the build command and wrong about the
# other hundred and thirty scripts, so every design or shell change paid about
# twenty five minutes a push for a question it could not affect. A narrowed list
# was rejected then because somebody would have to keep it honest for ever (L27,
# L96), so this derives the answer instead, from the tree being pushed:
#
#   SCRIPTS. The roots are scripts/run-tests.sh, which is where the phase lives,
#   and every script whose CODE runs xcodebuild or xcodegen. A file is read when
#   its name appears in the code of anything already read, followed all the way
#   down. Comments are not code: nearly every script here names others in its
#   comments, and counting them made 146 of 148 files reachable. The shell suites
#   (test-*.sh) are never roots, because run-tests.sh runs every one of them on
#   every push whatever the gate decides, so a suite that stubs xcodebuild is not
#   part of the phase.
#
#   SWIFT. The Swift suites open repository files through #filePath, so a path a
#   Swift file names as a string literal is read. Three tests read files under
#   docs/design/, and docs/ had been on the skippable list since ovation#22, so a
#   push changing only those files skipped the very tests that judge them (L88).
#
#   EVERYTHING ELSE is read, unless it is on the short list of files no build can
#   open: docs/, .github/, Markdown and git's own attribute files. Not being able
#   to see a reference is not evidence there is none (L98), so anything outside
#   the two derived areas stays on the safe side.
#
# WHAT A TEXT SEARCH CANNOT SEE is a script path assembled at run time.
# scripts/test-xcode-phase-inputs.sh traces a real run of the phase, with every
# tool faked, and refuses a touched script this derivation says is not read.
#
# Usage, from bash 3.2 upwards (macOS ships it, so no associative arrays):
#
#     . scripts/lib/xcode-phase-inputs.sh
#     xcode_phase_inputs_load "$REPO_ROOT" || { echo "$XPI_ERROR"; ...; }
#     if xcode_phase_reads docs/design/x.json; then echo "$XPI_WHY"; fi

XPI_REACHED=""
XPI_WORDS=""
XPI_SWIFT_PATHS=""
XPI_ERROR=""
XPI_WHY=""

# THE RUNNER'S XCODE PHASE, and only it (ovation#360).
#
# scripts/run-tests.sh does two halves: the shell suites, which run on every push
# whatever the gate decides, and the Xcode phase, which is what a skip skips. A
# file the shell half reads cannot change what the phase does, and counting them
# together made scripts/shell-suite-floor.txt an input to the build: every push
# adding a suite has to move that number (ovation#329), so the commonest change
# in this repository paid twenty five minutes for a question it could not affect.
#
# The region is found by the runner's OWN marker for the phase, the conditional
# on OVATION_SKIP_XCODE_PHASE at the left margin, through to the `fi` at the left
# margin that closes it. Deriving it from the same line the runner branches on is
# what keeps the two from drifting; a line number would be stale within the week
# (L41, L70).
#
# A RUNNER WHOSE MARKER CANNOT BE FOUND IS READ WHOLE. That is the safe direction:
# the phase's inputs are then over-counted rather than under-counted, which costs
# time rather than correctness (L93).
_xpi_phase_region() {
    awk 'BEGIN { inside = 0 }
        /^if \[ -n "\$\{SKIP_XCODE_PHASE\}" \]; then$/ { inside = 1; found = 1 }
        inside { print }
        inside && /^fi$/ { inside = 0 }
        END { if (!found) exit 1 }' "$1"
}

# Every word the code of these files could name a file by, one per line. A line
# whose first non blank character is # is a comment in shell and in Python alike.
# Written without character classes, which older awks on Linux runners lack.
_xpi_words() {
    _xpi_words_in "$@"
}

_xpi_words_in() {
    awk '!/^[ \t]*#/ {
        s = $0
        while (match(s, /[A-Za-z0-9_.+-]+/)) {
            print substr(s, RSTART, RLENGTH)
            s = substr(s, RSTART + RLENGTH)
        }
    }' "$@" | sort -u
}

# The files on stdin that can run and are not shell suites, from the current
# directory. What can run is a .sh or .py file, or anything starting with #!. The
# roles registry and the floors are data, and a data file that mentions
# xcodebuild in a sentence runs nothing. A function rather than a loop inside a
# command substitution, because bash 3.2 misreads a case pattern's closing
# parenthesis there as the end of the substitution.
_xpi_executables() {
    local f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$(basename "$f")" in test-*.sh) continue ;; esac
        case "$f" in
            *.sh|*.py) printf '%s\n' "$f" ;;
            *) [ "$(head -c 2 "$f" 2>/dev/null)" = "#!" ] && printf '%s\n' "$f" ;;
        esac
    done
}

# Whether a newline separated list holds this exact line.
_xpi_has() {
    case $'\n'"$1"$'\n' in
        *$'\n'"$2"$'\n'*) return 0 ;;
        *) return 1 ;;
    esac
}

# The words of every file in the list, with the runner read through its phase
# region alone. Run from the root of the tree.
_xpi_words_for() {
    local f
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        if [ "$f" = "scripts/run-tests.sh" ] && _xpi_phase_region "$f" > /dev/null 2>&1; then
            _xpi_phase_region "$f" | _xpi_words_in -
        else
            _xpi_words_in "$f"
        fi
    done <<< "$1" | sort -u
}

# Load what the Xcode phase of the tree at $1 reads. Returns 1 with XPI_ERROR set
# when it cannot be worked out, and a caller must then treat every path as read.
xcode_phase_inputs_load() {
    local root="$1" candidates executables roots queue words fresh
    XPI_REACHED="" XPI_WORDS="" XPI_SWIFT_PATHS="" XPI_ERROR=""

    if [ ! -f "${root}/scripts/run-tests.sh" ]; then
        XPI_ERROR="there is no scripts/run-tests.sh in ${root}, and the Xcode phase lives there, so nothing can say what the phase reads."
        return 1
    fi
    if ! candidates="$(cd "${root}" && find scripts -type f -not -path '*/__pycache__/*' | sort)"; then
        XPI_ERROR="could not list the files under ${root}/scripts."
        return 1
    fi

    executables="$(cd "${root}" && printf '%s\n' "${candidates}" | _xpi_executables)"

    roots="$(cd "${root}" && printf '%s\n' "${executables}" | while IFS= read -r f; do
        awk '!/^[ \t]*#/ && /xcodebuild|xcodegen/ { found = 1; exit } END { exit !found }' "$f" \
            && printf '%s\n' "$f"
    done)"
    roots="$(printf 'scripts/run-tests.sh\n%s\n' "${roots}" | grep -v '^$' | sort -u)"

    XPI_REACHED="${roots}"
    queue="${roots}"
    while [ -n "${queue}" ]; do
        # shellcheck disable=SC2046
        words="$(cd "${root}" && _xpi_words_for "${queue}")"
        XPI_WORDS="$(printf '%s\n%s\n' "${XPI_WORDS}" "${words}" | grep -v '^$' | sort -u)"
        fresh="$(printf '%s\n' "${candidates}" | while IFS= read -r f; do
            _xpi_has "${XPI_REACHED}" "$f" && continue
            _xpi_has "${words}" "$(basename "$f")" && printf '%s\n' "$f"
        done)"
        [ -n "${fresh}" ] && XPI_REACHED="$(printf '%s\n%s\n' "${XPI_REACHED}" "${fresh}" | sort -u)"
        queue="${fresh}"
    done

    # String literals in Swift code, cut at any interpolation back to the last
    # slash before it, so "docs/rules/\(name).json" covers everything in
    # docs/rules/. Only literals holding a slash can name a path in a folder.
    # Hidden folders are not searched: .git is not source, and the primary
    # checkout keeps other worktrees under .claude/, whose Swift files are another
    # tree's (L234).
    XPI_SWIFT_PATHS="$(cd "${root}" && find . -path './.*' -prune -o -name '*.swift' -print0 \
        | xargs -0 awk '!/^[ \t]*\/\// {
            s = $0
            while (match(s, /"[^"]*"/)) {
                lit = substr(s, RSTART + 1, RLENGTH - 2)
                s = substr(s, RSTART + RLENGTH)
                cut = index(lit, "\\(")
                if (cut > 0) {
                    lit = substr(lit, 1, cut - 1)
                    sub(/[^\/]*$/, "", lit)
                }
                sub(/^\.\//, "", lit)
                if (lit != "" && index(lit, "/") > 0 && substr(lit, 1, 1) != "/") print lit
            }
        }' | sort -u)"
    return 0
}

# Whether the Xcode phase reads the path, relative to the repository root. The
# reason is left in XPI_WHY for a caller that wants to say it.
xcode_phase_reads() {
    local path="$1" lit
    XPI_WHY=""
    while IFS= read -r lit; do
        [ -n "${lit}" ] || continue
        case "${lit}" in
            */) case "${path}" in "${lit}"*) ;; *) continue ;; esac ;;
            *) [ "${path}" = "${lit}" ] || case "${path}" in "${lit}/"*) ;; *) continue ;; esac ;;
        esac
        XPI_WHY="a Swift file names ${lit} as a path, and the Swift suites open repository files"
        return 0
    done <<< "${XPI_SWIFT_PATHS}"

    case "${path}" in
        scripts/*)
            if _xpi_has "${XPI_REACHED}" "${path}"; then
                XPI_WHY="it is part of what builds or runs the Xcode phase"
                return 0
            fi
            if _xpi_has "${XPI_WORDS}" "$(basename "${path}")"; then
                XPI_WHY="a script the Xcode phase runs names it"
                return 0
            fi
            return 1
            ;;
        docs/*|.github/*|*.md|.gitignore|.gitattributes)
            return 1
            ;;
    esac
    XPI_WHY="nothing shows the Xcode phase cannot read it"
    return 0
}
