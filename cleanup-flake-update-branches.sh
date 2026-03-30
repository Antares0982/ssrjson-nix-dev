#!/usr/bin/env bash
set -euo pipefail

# Delete all remote flake-update branches except the most recent one.
# Also delete all stale pending-flake-update branches (these are CI temporaries).
# Branch patterns:
#   flake-update/nixpkgs-*          (verified, keep newest)
#   pending-flake-update/nixpkgs-*  (unverified, delete all)

remote="${1:-origin}"

# ── Clean up all pending (unverified) branches unconditionally ──
pending_branches=$(git for-each-ref \
	--sort=-committerdate \
	--format='%(refname:strip=3)' \
	"refs/remotes/${remote}/pending-flake-update/nixpkgs-*")

if [ -n "$pending_branches" ]; then
	echo "Deleting $(echo "$pending_branches" | wc -l) pending branch(es) on remote '${remote}':"
	echo "$pending_branches" | sed 's/^/  /'
	echo
	echo "$pending_branches" | xargs git push "${remote}" --delete
	echo
fi

# ── Clean up verified branches, keeping the newest ──
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
