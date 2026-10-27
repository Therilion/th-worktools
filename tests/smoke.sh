#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd -P "$(dirname "$0")" && pwd)"

for f in "$DIR"/smoke/*.sh; do
  echo "# $(basename "$f")"
  bash "$f"
done
