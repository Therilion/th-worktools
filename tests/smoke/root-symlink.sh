#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

git -C "$TMP/repo" remote set-head origin main >/dev/null

name="raíz bajo un symlink: new crea el worktree y list y close lo encuentran"
real="$HOME"
ln -s "$real" "$TMP/home-link"
export HOME="$TMP/home-link"
dest="$real/.worktrees/acme/demo/feature-x"
out="$(cd "$TMP/repo" && "$WT" new feature/x --json 2>/dev/null)" || fail "$name: th-wt new falló"
[ "$(printf '%s' "$out" | jq -r .path)" = "$dest" ] || fail "$name: el path de new no es el canónico: [$out]"
[ -d "$dest" ] || fail "$name: no existe $dest"
out="$(cd "$TMP/repo" && "$WT" list --json 2>/dev/null)" || fail "$name: th-wt list falló"
[ "$(printf '%s' "$out" | jq -r '.worktrees[].path')" = "$dest" ] || fail "$name: list no lo encuentra: [$out]"
out="$(cd "$TMP/repo" && "$WT" close feature/x 2>&1)" || fail "$name: close sin --yes falló: [$out]"
printf '%s\n' "$out" | grep -qF "$dest" || fail "$name: el plan no tiene la ruta: [$out]"
[ -d "$dest" ] || fail "$name: close sin --yes borró el directorio"
out="$(cd "$TMP/repo" && "$WT" close feature/x --yes 2>&1)" || fail "$name: close --yes falló: [$out]"
[ ! -e "$dest" ] || fail "$name: close --yes no borró el directorio"
pass "$name"
