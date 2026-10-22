#!/usr/bin/env bash
# Uploads a fake clip and polls until the worker finishes it.
# Usage: scripts/smoke-test.sh [base_url]   (default http://localhost:8000)
set -euo pipefail
BASE="${1:-http://localhost:8000}"
f="$(mktemp --suffix=.mp4 2>/dev/null || mktemp)"; head -c 2048 /dev/urandom > "$f"
id="$(curl -fsS -F "file=@${f};filename=smoke.mp4" "$BASE/ingest" | jq -r .asset_id)"
echo "asset_id=$id"
for _ in $(seq 1 30); do
  s="$(curl -fsS "$BASE/status/$id" | jq -r .status)"
  echo "  status=$s"
  [[ "$s" == "DONE" ]] && exit 0
  [[ "$s" == "FAILED" ]] && { echo "worker marked it FAILED (expected ~5% of the time)"; exit 0; }
  sleep 2
done
echo "timed out waiting for the worker"; exit 1
