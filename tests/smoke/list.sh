#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

# La rama por defecto local sale de refs/remotes/origin/HEAD; no se consulta la red.
git -C "$TMP/repo" remote set-head origin main >/dev/null

name="list muestra rama, ruta, limpio y contenida de un worktree creado con new"
(cd "$TMP/repo" && "$WT" new feature/login) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-login"
out="$(cd "$TMP/repo" && "$WT" list 2>&1)" || fail "$name: th-wt list falló: [$out]"
line="$(printf '%s\n' "$out" | grep -F "feature/login")" || fail "$name: no aparece la rama: [$out]"
case "$line" in *"$dest"*) ;; *) fail "$name: la línea no tiene la ruta: [$line]" ;; esac
case "$line" in *clean*) ;; *) fail "$name: la línea no dice clean: [$line]" ;; esac
case "$line" in *"contained in origin/main"*) ;; *) fail "$name: la línea no dice contained in origin/main: [$line]" ;; esac
case "$line" in *"not contained"*) fail "$name: la línea dice not contained: [$line]" ;; esac
pass "$name"
