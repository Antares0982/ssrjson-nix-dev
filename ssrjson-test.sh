#!/usr/bin/env bash
set -euo pipefail

source_dir=${1:?Expected ssrJSON checkout}
candidate_sha=${2:?Expected nix-dev commit}
input="github:Antares0982/ssrjson-nix-dev/$candidate_sha"
echo "ssrJSON: $(git -C "$source_dir" rev-parse HEAD)"
echo "ssrjson-nix-dev: $candidate_sha"

targets=$(jq -er '
    (range(.latestWheelBuildableVer; .minSupportNoGILVer - 1; -1) | "ssrjson-wheel-py3\(.)t"),
    (range(.latestWheelBuildableVer; .minSupportVer - 1; -1) | "ssrjson-wheel-py3\(.)")
' "$source_dir/ci/pyver.json")

while IFS= read -r target; do
    echo "Building $target"
    nix build "$source_dir#$target" --no-link --print-build-logs \
        --no-write-lock-file --override-input ssrjson-nix-dev "$input"
done <<< "$targets"
