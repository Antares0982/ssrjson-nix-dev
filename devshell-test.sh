#!/usr/bin/env bash
set -e
json_content=$(cat ./devshell/pyver.json)
cur_ver=$(echo "$json_content" | jq '.curVer')
min_ver=$(echo "$json_content" | jq '.minSupportVer')
min_nogil_ver=$(echo "$json_content" | jq '.minSupportNoGILVer')
max_ver=$(echo "$json_content" | jq '.maxSupportVer')
check_shell() {
	echo "Testing $1"
	nix develop ".#$1" --command python -c '
import sys, sysconfig
minor, free_threaded = map(int, sys.argv[1:])
assert sys.version_info[:2] == (3, minor), sys.version
assert bool(sysconfig.get_config_var("Py_GIL_DISABLED")) == free_threaded, sys.abiflags
assert getattr(sys, "_is_gil_enabled", lambda: True)() != free_threaded, sys.version
' "$2" "$3"
}
check_shell default "$cur_ver" 0
for ((i = max_ver; i >= min_ver; i--)); do
	check_shell "devenv-py3$i" "$i" 0
	check_shell "buildenv-py3$i" "$i" 0
done
for ((i = max_ver; i >= min_nogil_ver; i--)); do
	check_shell "devenv-py3${i}t" "$i" 1
	check_shell "buildenv-py3${i}t" "$i" 1
done
check_shell benchmarkenv "$cur_ver" 0
