#!/usr/bin/env bash
set -euo pipefail

prepare_update() {
    echo "update_sha=$(git rev-parse HEAD)" >> "$GITHUB_OUTPUT"
    if [[ "$DO_UPDATE" != true && "$NEW_BRANCH" != true ]]; then
        return
    fi
    if [[ "$NEW_BRANCH" != true && "$GITHUB_REF_TYPE" != branch ]]; then
        echo "Direct updates require a branch" >&2
        return 1
    fi

    before_sha=$(git rev-parse HEAD)
    nix --option commit-lockfile-summary "flake.lock: Update [skip ci]" flake update --commit-lock-file
    update_sha=$(git rev-parse HEAD)
    if [[ "$before_sha" == "$update_sha" ]]; then
        echo "No flake.lock update"
        return
    fi

    rev=$(jq -er '.nodes.nixpkgs.locked.rev' flake.lock)
    final_branch="$GITHUB_REF_NAME"
    if [[ "$NEW_BRANCH" == true ]]; then
        final_branch="flake-update/nixpkgs-${rev:0:12}"
    fi
    pending_branch="pending-flake-update/nixpkgs-${rev:0:12}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
    {
        echo "branch_name=$pending_branch"
        echo "final_branch_name=$final_branch"
        echo "update_sha=$update_sha"
    } >> "$GITHUB_OUTPUT"
    git push origin "HEAD:refs/heads/$pending_branch"
}

finalize_update() {
    if [[ -z "$PENDING_BRANCH" ]]; then
        return
    fi
    : "${FINAL_BRANCH:?Expected final branch}" "${UPDATE_SHA:?Expected candidate SHA}"
    result=0
    if [[ "$PREPARE_RESULT" == success && "$X86_RESULT" == success &&
          "$ARM_RESULT" == success && "$MAC_RESULT" == success ]]; then
        if [[ "$NEW_BRANCH" == true ]]; then
            if existing=$(git ls-remote --heads origin "refs/heads/$FINAL_BRANCH"); then
                if [[ -n "$existing" ]]; then
                    echo "Branch $FINAL_BRANCH already exists; leaving it unchanged"
                else
                    git push origin "$UPDATE_SHA:refs/heads/$FINAL_BRANCH" || result=$?
                fi
            else
                result=$?
            fi
        else
            git push origin "$UPDATE_SHA:refs/heads/$FINAL_BRANCH" || result=$?
        fi
    else
        echo "Validation failed: prepare=$PREPARE_RESULT x86=$X86_RESULT arm=$ARM_RESULT mac=$MAC_RESULT" >&2
        result=1
    fi
    git push origin --delete "$PENDING_BRANCH" || result=$?
    return "$result"
}

case "${1:?Expected prepare or finalize}" in
    prepare) prepare_update ;;
    finalize) finalize_update ;;
    *) echo "Expected prepare or finalize" >&2; exit 1 ;;
esac
