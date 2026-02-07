#/usr/bin/env bash
set -e
json_content=$(cat ./devshell/pyver.json)
min_ver=$(echo "$json_content" | jq '.minSupportVer')
min_nogil_ver=$(echo "$json_content" | jq '.minSupportNoGILVer')
max_ver=$(echo "$json_content" | jq '.maxSupportVer')
for ((i = max_ver; i >= min_ver; i--)); do
	nix develop .#devenv-py3$i --command echo devenv-py3$i
	nix develop .#buildenv-py3$i --command echo buildenv-py3$i
done
for ((i = max_ver; i >= min_nogil_ver; i--)); do
	nix develop .#devenv-py3${i}t --command echo devenv-py3${i}t
	nix develop .#buildenv-py3${i}t --command echo buildenv-py3${i}t
done
