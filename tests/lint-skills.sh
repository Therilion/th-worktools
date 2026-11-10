#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -P "$(dirname "$0")/.." && pwd)"
status=0
err() { echo "lint: $1" >&2; status=1; }

for dir in "$ROOT"/skills/th-*/; do
  folder="$(basename "$dir")"
  file="$dir/SKILL.md"
  [ -f "$file" ] || { err "$folder: falta SKILL.md"; continue; }

  name="$(awk '/^---$/ { n++; next } n == 1 && /^name:/ { sub(/^name:[ ]*/, ""); print; exit }' "$file")"
  [ "$name" = "$folder" ] || err "$folder: name='$name' no coincide con la carpeta"

  # Toda línea con scripts/ debe usar la ruta fija entre comillas dobles y sin ${…}
  # (Claude Code no auto-aprueba comandos con llaves de variable).
  fixed="\"\$HOME/.local/share/th-worktools/skills/$folder/scripts/"
  if grep -F 'scripts/' "$file" | grep -v -F "$fixed" >/dev/null \
    || grep -F 'scripts/' "$file" | grep -F "\${" >/dev/null; then
    err "$folder: ruta scripts/ sin la forma fija \"\$HOME/.local/share/th-worktools/skills/$folder/scripts/…\" (sin \${…})"
  fi
done

exit "$status"
