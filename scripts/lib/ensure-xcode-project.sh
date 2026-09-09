# ovation#151. Make the Xcode project when there is none, and only then.
#
# `Ovation.xcodeproj` is generated from project.yml by xcodegen and is gitignored,
# so a fresh clone, Dan's second Mac and any CI runner start without one. What
# that gave was `xcodebuild: error: Ovation.xcodeproj does not exist`, which names
# the symptom rather than the missing step.
#
# NEVER REGENERATED WHEN IT IS THERE, and that is the whole of the decision.
# Rewriting the project on every build is a different act from making one on a
# machine that has none: it rewrites the file underneath an open Xcode. The third
# option, committing the project the way Overture does, was not taken because this
# repository deliberately ignores it and would then owe a freshness check to carry
# the drift, which Overture pays for with `scripts/check-pbxproj-fresh.sh`.
#
# IT IS A SHARED FUNCTION rather than a block copied into each caller, because
# every route to xcodebuild needs it and a second copy is a second thing to keep
# correct (L613, L370).
#
# Sourced, so it can read and be read by the caller's own seams.

# Answers 0 when there is a project to build, and REFUSES with its own message
# otherwise. Takes the repository root, the project path and the generator, all
# from the caller, so nothing here re-derives a path a caller already knows (L70).
ensure_xcode_project() {
    local repo_root="$1" project="$2" generator="$3"

    [ -d "${project}" ] && return 0

    if [ ! -x "${generator}" ]; then
        echo "Error: there is no Xcode project at ${project} and xcodegen" >&2
        echo "       is not at ${generator}, so one cannot be made." >&2
        echo "       The project is generated from project.yml rather than committed." >&2
        echo "       Install it with: brew install xcodegen" >&2
        return 2
    fi

    if ! ( cd "${repo_root}" && "${generator}" generate ); then
        echo "Error: xcodegen could not generate ${project} from project.yml." >&2
        return 2
    fi

    # A GENERATOR THAT EXITS 0 AND WRITES NOTHING is the shape this exists for:
    # without it the next line is xcodebuild's own error about a missing project,
    # one step further from the cause (L100, L184).
    if [ ! -d "${project}" ]; then
        echo "Error: xcodegen reported success and ${project} is still not there." >&2
        return 2
    fi

    echo "==> Generated $(basename "${project}") from project.yml, which was absent."
    return 0
}
