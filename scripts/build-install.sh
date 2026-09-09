#!/usr/bin/env bash
# Ported-From: danwright32/downbeat Downbeat/build-install.sh @ 563865a7e8a93c678e6eed38c86281c8d9a730d0
#
# Build Ovation in Release and install it to /Applications, and RECORD what was
# installed.
#
# The record is the part everything else rests on. The app cannot run git and
# cannot know which checkout produced the bundle in /Applications, so unless the
# installer writes it down, the app has no way to notice it has fallen behind.
# That is not hypothetical: the source repository's copy of this exists because a
# Downbeat install sat six hours behind main with nothing anywhere noticing, and
# opening the app the ordinary way showed none of that day's work.
#
# TWO ORDERINGS ARE LOAD BEARING, both carried from the source because both were
# learned the hard way rather than reasoned out.
#
#   installed-build.json is written AFTER the bundle verifiably lands, so a
#   record never describes an install that did not happen (L12), and BEFORE the
#   app is launched, so the app's first read cannot land in the instant the
#   installer is still writing. Overture lost the whole feature to the second
#   half of that: the app started, read nothing, and spent two hours telling Dan
#   his copy had not come from the installer.
#
#   A running copy is identified by its EXECUTABLE PATH and quit by pid, NEVER by
#   the name "Ovation". Two builds of this app run at once as a matter of course,
#   the installed Release one and a Debug one from Xcode, and they share a name.
#   Asking macOS to quit "Downbeat" is what killed Dan's live Overture on
#   2026-08-04 while an installer was aimed at a different bundle.
#
# WHAT THIS PORT DELIBERATELY DOES NOT TAKE, per docs/PORT-DISCIPLINE.md. The
# source is 619 lines and much of it is Downbeat's own machinery: the shipped
# commit recorder, the LaunchServices registration cleanup, and the synthetic
# launch check. Each is a real thing Ovation may want later, and none of them is
# what ovation#10 is for. They are named here so their absence is a decision and
# not an oversight, and ovation#20 already covers the launch half.
#
# FIELD SET: Ovation writes the UNION of what the two siblings record, because
# NEITHER writes the set Ovation's own installed consumer guard needs. Overture
# writes provenance but no dirtyFiles; Downbeat writes dirtyFiles but calls the
# line of work `branch`. Ovation needs all three kinds of fact: which commit,
# whether the tree was clean, and where it came from.
set -uo pipefail

OVATION_INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OVATION_REPO_ROOT:-$(cd "${OVATION_INSTALLER_DIR}/.." && pwd)}"

APP_NAME="Ovation.app"
DEST="${OVATION_INSTALL_DEST:-/Applications/${APP_NAME}}"
BUILT_APP="${OVATION_BUILT_APP:-}"
DATA_DIR="${OVATION_DATA_DIR:-${HOME}/Library/Application Support/Ovation}"
CODESIGN_CMD="${OVATION_CODESIGN:-codesign}"
XATTR_CMD="${OVATION_XATTR:-xattr}"
RECORD="${DATA_DIR}/installed-build.json"

# ---------------------------------------------------------------------------
# Pure functions. Sourced by scripts/test-build-install.sh with --source-only so
# every branch can be exercised without installing anything.
# ---------------------------------------------------------------------------

# The pids in a "pid executable-path" table running the given executable.
#
# The comparison is EXACT and against the full path. A prefix match would take
# OvationHelper alongside Ovation, and a name match would take the Debug build
# running from Xcode, which is a live app somebody is using.
ovation_pids_from_table() {
  local exe="$1" pid path
  while read -r pid path; do
    [ "${path}" = "${exe}" ] && printf '%s\n' "${pid}"
  done
  return 0
}

# ASKING A REPOSITORY ABOUT ITSELF NEEDS MORE THAN `git -C`. An inherited GIT_DIR
# BEATS the -C, so every question below is answered by whatever GIT_DIR names
# rather than by the repository this was handed.
#
# That is not a hypothetical here. Git EXPORTS GIT_DIR to its hooks, and this
# script's suite runs inside the pre-push hook. Found on 2026-09-08: the suite
# passed run by hand and failed five assertions inside the gate, reporting the
# pushing worktree's own branch and its 188 dirty files against a fixture repo
# that held one file and was on main.
#
# THE STAKE IS HIGHER THAN A FAILING TEST. This record is the only thing that can
# say which code the app in /Applications came from, because the app cannot run
# git. A branch and a dirty count read off the wrong repository are not obviously
# wrong to anybody: they are plausible values describing somewhere else, and the
# record's whole purpose is to be believed later (L416).
#
# One helper, so a call site added later cannot quietly be the one that asks the
# wrong repository (L70, L621).
ovation_repo_git() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY \
      -u GIT_COMMON_DIR -u GIT_NAMESPACE git "$@"
}

# How many tracked files differ, or NOTHING when git cannot be asked.
#
# Nothing rather than zero. A repository this cannot read is not a clean one
# (L98). The source carries a comment about the first version of this piping
# straight into `wc -l`: git failed, wc counted an empty stream, the answer was
# "0", and a directory that could not be asked reported a CLEAN tree. So git is
# captured on its own and the failure is caught by the substitution.
ovation_dirty_file_count() {
  local repo="$1" out
  out=$(ovation_repo_git -C "${repo}" status --porcelain 2>/dev/null) || return 0
  # An empty answer from a repository that ANSWERED is a real zero, and has to
  # stay distinguishable from the silence above.
  if [ -z "${out}" ]; then printf '0'; return 0; fi
  printf '%s' "$(printf '%s\n' "${out}" | wc -l | tr -d ' ')"
}

# Which line of work this came from, or nothing when it cannot be asked (L98).
# git's own answer, so a detached checkout comes back as `HEAD` and is passed
# through unchanged rather than translated here: the reader has to tell a branch
# from a detached checkout, and a translation done in shell would be a second
# vocabulary free to drift from the one that reads it (L41).
ovation_provenance() {
  local repo="$1" out
  out="$(ovation_repo_git -C "${repo}" rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 0
  printf '%s' "${out}"
}

# The record's exact bytes.
#
# EVERY OPTIONAL FIELD IS OMITTED WHEN NOT KNOWN, never written with a
# reassuring default. Absent means NOT RECORDED: not "clean", not "main", not
# "ad hoc". A reader treats an absent field as CANNOT MEASURE, never as a pass
# (L11, L98). Writing 0 or "main" for a repository nobody could read would have
# an old record vouch for something nothing ever checked.
ovation_installed_build_json() {
  local commit="$1" commit_date="$2" repo_path="$3"
  local identity="${4:-}" dirty="${5:-}" provenance="${6:-}" installed_at="${7:-}"
  local record
  record=$(printf '{"version":1,"commit":"%s","commitDate":"%s","repoPath":"%s"' \
    "${commit}" "${commit_date}" "${repo_path}")
  [ -n "${identity}" ]    && record="${record}$(printf ',"signingIdentity":"%s"' "${identity}")"
  # A NUMBER, not a string, so a reader cannot accidentally compare it to text.
  [ -n "${dirty}" ]       && record="${record}$(printf ',"dirtyFiles":%s' "${dirty}")"
  [ -n "${provenance}" ]  && record="${record}$(printf ',"provenance":"%s"' "${provenance}")"
  [ -n "${installed_at}" ] && record="${record}$(printf ',"installedAt":"%s"' "${installed_at}")"
  printf '%s}\n' "${record}"
}

# The identity the bundle was ACTUALLY signed with, or nothing. Read off the
# signed product rather than off the build setting, because a value the
# configuration sets is only in force if nothing downstream recomputes it (L188).
ovation_signing_identity() {
  local app="$1" out
  out="$("${CODESIGN_CMD}" -d --verbose=2 "${app}" 2>&1)" || return 0
  case "${out}" in
    *"Signature=adhoc"*) printf 'adhoc' ;;
    *) printf '%s' "$(printf '%s' "${out}" | sed -n 's/^Authority=\(.*\)$/\1/p' | head -1)" ;;
  esac
}

[ "${1:-}" = "--source-only" ] && return 0 2>/dev/null

# ---------------------------------------------------------------------------
# The install itself.
# ---------------------------------------------------------------------------

if [ -z "${OVATION_SKIP_BUILD:-}" ]; then
  echo "==> Building Ovation (Release)"
  # A FRESH CLONE HAS NO PROJECT (ovation#151). The same helper the test runner
  # uses, so there is one rule about when a project is made rather than two.
  # shellcheck source=lib/ensure-xcode-project.sh
  . "${REPO_ROOT}/scripts/lib/ensure-xcode-project.sh"
  ensure_xcode_project "${REPO_ROOT}" \
      "${OVATION_XCODE_PROJECT:-${REPO_ROOT}/Ovation.xcodeproj}" \
      "${OVATION_XCODEGEN:-$(command -v xcodegen || echo /opt/homebrew/bin/xcodegen)}" \
      || exit 2

  xcodebuild -project "${REPO_ROOT}/Ovation.xcodeproj" -scheme Ovation \
    -configuration Release -destination 'platform=macOS' build || exit 1
  BUILT_APP="${BUILT_APP:-$(xcodebuild -project "${REPO_ROOT}/Ovation.xcodeproj" \
    -scheme Ovation -configuration Release -destination 'platform=macOS' \
    -showBuildSettings 2>/dev/null \
    | awk '$1=="BUILT_PRODUCTS_DIR" && $2=="=" {print $3; exit}')/${APP_NAME}}"
fi

# REFUSE before touching anything. A record must never describe an install that
# did not happen, and the surest way to honour that is to stop here (L12).
if [ ! -d "${BUILT_APP}" ]; then
  echo "Error: there is no built bundle at ${BUILT_APP}" >&2
  echo "       Nothing was installed and the existing record is untouched." >&2
  exit 1
fi

# Staged BESIDE the destination rather than in a temp directory, so the final
# step is a rename within one volume rather than a copy that can half finish.
# The staged bundle keeps the name Ovation.app: codesign reads the extension to
# decide it is looking at a bundle at all.
STAGING_DIR="$(dirname "${DEST}")/.ovation-install-staging"
STAGING="${STAGING_DIR}/${APP_NAME}"
PREVIOUS="${STAGING_DIR}/previous-${APP_NAME}"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}" || exit 1
cp -R "${BUILT_APP}" "${STAGING}" || exit 1
"${XATTR_CMD}" -cr "${STAGING}" >/dev/null 2>&1 || true

# Quit whatever is running FROM the bundle about to be replaced, and refuse to
# go on if anything still is. Deleting a bundle out from under a running process
# is how an app ends up half replaced and unable to launch.
PIDS="$(ps -axo pid=,comm= | ovation_pids_from_table "${DEST}/Contents/MacOS/Ovation")"
if [ -n "${PIDS}" ]; then
  echo "==> Quitting the copy running from ${DEST}"
  for pid in ${PIDS}; do kill -TERM "${pid}" 2>/dev/null || true; done
  waited=0
  while [ -n "$(ps -axo pid=,comm= | ovation_pids_from_table "${DEST}/Contents/MacOS/Ovation")" ]; do
    waited=$((waited+1))
    [ "${waited}" -gt 100 ] && { echo "Error: a copy is still running from ${DEST}" >&2; exit 1; }
    sleep 0.1
  done
fi

# KEEP THE PREVIOUS COPY until the new one is verifiably in place (L5).
rm -rf "${PREVIOUS}"
[ -d "${DEST}" ] && mv "${DEST}" "${PREVIOUS}"
if ! mv "${STAGING}" "${DEST}"; then
  echo "Error: could not move the new bundle into place." >&2
  [ -d "${PREVIOUS}" ] && mv "${PREVIOUS}" "${DEST}" && echo "       The previous copy was put back." >&2
  exit 1
fi

# THE BUNDLE HAS TO BE THERE before anything is recorded about it.
if [ ! -d "${DEST}" ]; then
  echo "Error: the bundle is not at ${DEST} after the move. Nothing was recorded." >&2
  exit 1
fi
rm -rf "${STAGING_DIR}"

COMMIT="$(ovation_repo_git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || true)"
COMMIT_DATE="$(ovation_repo_git -C "${REPO_ROOT}" log -1 --format=%cI 2>/dev/null || true)"
DIRTY="$(ovation_dirty_file_count "${REPO_ROOT}")"
PROVENANCE="$(ovation_provenance "${REPO_ROOT}")"
IDENTITY="$(ovation_signing_identity "${DEST}")"
INSTALLED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "${DATA_DIR}" || exit 1
ovation_installed_build_json "${COMMIT}" "${COMMIT_DATE}" "${REPO_ROOT}" \
  "${IDENTITY}" "${DIRTY}" "${PROVENANCE}" "${INSTALLED_AT}" > "${RECORD}" || exit 1

echo "==> Installed to ${DEST}"
echo "==> Recorded ${RECORD}"
cat "${RECORD}"
