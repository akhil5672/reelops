#!/usr/bin/env bash
# One-time: replaces placeholders in this repo and the sibling reelops-gitops repo.
# Usage: ACCOUNT_ID=123456789012 GITHUB_OWNER=your-gh-user ALERT_EMAIL=you@example.com scripts/init-placeholders.sh
set -euo pipefail
: "${ACCOUNT_ID:?set ACCOUNT_ID}" "${GITHUB_OWNER:?set GITHUB_OWNER}" "${ALERT_EMAIL:?set ALERT_EMAIL}"
root="$(cd "$(dirname "$0")/.." && pwd)"
targets=("$root")
[[ -d "$root/../reelops-gitops" ]] && targets+=("$root/../reelops-gitops")
for t in "${targets[@]}"; do
  grep -rlE 'ACCOUNT_ID|GITHUB_OWNER|ALERT_EMAIL' "$t" \
    --exclude-dir=.git --exclude-dir=.terraform --exclude=init-placeholders.sh --exclude="*.md" |
  while read -r file; do
    sed -i.bak -e "s/ACCOUNT_ID/${ACCOUNT_ID}/g" -e "s/GITHUB_OWNER/${GITHUB_OWNER}/g" -e "s/ALERT_EMAIL/${ALERT_EMAIL}/g" "$file"
    rm -f "${file}.bak"; echo "updated $file"
  done
done
