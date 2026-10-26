#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -P "$(dirname "$0")/.." && pwd)"
status=0
err() { echo "lint: $1" >&2; status=1; }

for dir in "$ROOT"/skills/*/; do
  folder="$(basename "$dir")"
  file="$dir/SKILL.md"
  [ -f "$file" ] || { err "$folder: falta SKILL.md"; continue; }

  name="$(awk '/^---$/ { n++; next } n == 1 && /^name:/ { sub(/^name:[ ]*/, ""); print; exit }' "$file")"
  [ "$name" = "$folder" ] || err "$folder: name='$name' no coincide con la carpeta"

  if grep 'scripts/' "$file" | grep -v 'CLAUDE_SKILL_DIR' >/dev/null; then
    err "$folder: ruta scripts/ sin el prefijo \${CLAUDE_SKILL_DIR"
  fi
done

exit "$status"
