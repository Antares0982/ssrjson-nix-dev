#!/usr/bin/env bash
set -euo pipefail

# Delete all remote flake-update branches except the most recent one.
# Branch pattern: flake-update/nixpkgs-*

remote="${1:-origin}"

# Collect remote branches matching the pattern, sorted by committerdate (newest first)
branches=$(git for-each-ref \
  --sort=-committerdate \
  --format='%(refname:strip=3)' \
  "refs/remotes/${remote}/flake-update/nixpkgs-*")

if [ -z "$branches" ]; then
  echo "No flake-update branches found on remote '${remote}'."
  exit 0
fi

total=$(echo "$branches" | wc -l)
if [ "$total" -le 1 ]; then
  echo "Only one flake-update branch exists — nothing to delete."
  exit 0
fi

# Keep the first (newest) branch, delete the rest
newest=$(echo "$branches" | head -n1)
to_delete=$(echo "$branches" | tail -n +2)

echo "Keeping:  ${newest}"
echo "Deleting $(echo "$to_delete" | wc -l) branch(es) on remote '${remote}':"
echo "$to_delete" | sed 's/^/  /'
echo

echo "$to_delete" | xargs git push "${remote}" --delete
echo "Done."
