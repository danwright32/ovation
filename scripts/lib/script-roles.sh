#!/bin/bash
# The one reader of scripts/lib/script-roles.tsv. ovation#86.
#
# TWO COMPLETENESS RULES READ THIS, in test-preconditions.sh and in
# test-output-privacy.sh, and they read it THROUGH HERE rather than each parsing
# the file. Sharing the data while copying the code that applies it is not
# consolidation: the shared file reads as the single source of truth and nobody
# asks whether the parsing beside it was duplicated (L370).
#
# Sourced, never run.

# Where the inventory is, resolved from THIS file's own location rather than
# from the caller's working directory, because a path re-derived from a caller
# is relative to wherever that caller was invoked from (L372).
_SCRIPT_ROLES_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROLES_TSV="${_SCRIPT_ROLES_LIB_DIR}/script-roles.tsv"
SCRIPTS_DIR="$(cd "${_SCRIPT_ROLES_LIB_DIR}/.." && pwd)"

# Every declared entry, as `path<TAB>role<TAB>reason`. Comments and blank lines
# are dropped; nothing else is.
roles_entries() {
    [ -f "$SCRIPT_ROLES_TSV" ] || return 1
    grep -v '^#' "$SCRIPT_ROLES_TSV" | grep -v '^[[:space:]]*$'
}

roles_paths() { roles_entries | cut -f1 | sort; }

role_of() { roles_entries | awk -F'\t' -v p="$1" '$1 == p { print $2; exit }'; }

reason_of() { roles_entries | awk -F'\t' -v p="$1" '$1 == p { print $3; exit }'; }

roles_with() { roles_entries | awk -F'\t' -v r="$1" '$2 == r { print $1 }' | sort; }

# Every script actually on disk, relative to scripts/, sorted.
#
# IT LOOKS FOR WHAT A SCRIPT IS, not for one extension. The rules this replaced
# matched `check-*.sh`, which is why `check-design-collisions.py` was invisible
# to both of them while being run by nothing at all.
scripts_on_disk() {
    ( cd "$SCRIPTS_DIR" && find . -type f \( -name '*.sh' -o -name '*.py' \) \
        -not -path './git-hooks/*' | sed 's|^\./||' | sort )
}
