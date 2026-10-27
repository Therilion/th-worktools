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

name="list marca dirty un worktree con un archivo trackeado modificado"
echo base > "$TMP/repo/tracked.txt"
git -C "$TMP/repo" add tracked.txt
git -C "$TMP/repo" commit -q -m "agrega tracked.txt"
git -C "$TMP/repo" push -q origin main
(cd "$TMP/repo" && "$WT" new feature/dirty-tracked) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-dirty-tracked"
echo cambio >> "$dest/tracked.txt"
out="$(cd "$TMP/repo" && "$WT" list 2>&1)" || fail "$name: th-wt list falló: [$out]"
line="$(printf '%s\n' "$out" | grep -F "feature/dirty-tracked")" || fail "$name: no aparece la rama: [$out]"
case "$line" in *dirty*) ;; *) fail "$name: la línea no dice dirty: [$line]" ;; esac
case "$line" in *clean*) fail "$name: la línea dice clean: [$line]" ;; esac
pass "$name"

name="list marca dirty un worktree con un archivo nuevo sin trackear"
(cd "$TMP/repo" && "$WT" new feature/dirty-untracked) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-dirty-untracked"
echo nuevo > "$dest/untracked.txt"
out="$(cd "$TMP/repo" && "$WT" list 2>&1)" || fail "$name: th-wt list falló: [$out]"
line="$(printf '%s\n' "$out" | grep -F "feature/dirty-untracked")" || fail "$name: no aparece la rama: [$out]"
case "$line" in *dirty*) ;; *) fail "$name: la línea no dice dirty: [$line]" ;; esac
case "$line" in *clean*) fail "$name: la línea dice clean: [$line]" ;; esac
pass "$name"

name="list marca not contained una rama con commits que origin/main no tiene"
(cd "$TMP/repo" && "$WT" new feature/ahead) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-ahead"
git -C "$dest" commit -q --allow-empty -m "trabajo propio"
out="$(cd "$TMP/repo" && "$WT" list 2>&1)" || fail "$name: th-wt list falló: [$out]"
line="$(printf '%s\n' "$out" | grep -F "feature/ahead")" || fail "$name: no aparece la rama: [$out]"
case "$line" in *"not contained in origin/main"*) ;; *) fail "$name: la línea no dice not contained in origin/main: [$line]" ;; esac
pass "$name"

name="list marca contained una rama ya integrada en origin/main aunque main haya avanzado"
(cd "$TMP/repo" && "$WT" new feature/integrated) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-integrated"
git -C "$dest" commit -q --allow-empty -m "trabajo integrado"
git -C "$dest" push -q origin HEAD:main
git -C "$TMP/repo" pull -q --ff-only origin main
git -C "$TMP/repo" commit -q --allow-empty -m "main avanza"
git -C "$TMP/repo" push -q origin main
out="$(cd "$TMP/repo" && "$WT" list 2>&1)" || fail "$name: th-wt list falló: [$out]"
line="$(printf '%s\n' "$out" | grep -F "feature/integrated")" || fail "$name: no aparece la rama: [$out]"
case "$line" in *"not contained"*) fail "$name: la línea dice not contained: [$line]" ;; esac
case "$line" in *"contained in origin/main"*) ;; *) fail "$name: la línea no dice contained in origin/main: [$line]" ;; esac
pass "$name"

name="list no muestra el checkout principal ni worktrees fuera de ~/.worktrees/acme/demo/"
git -C "$TMP/repo" worktree add -q -b outside-branch "$TMP/outside"
git -C "$TMP/repo" worktree add -q -b foreign-branch "$HOME/.worktrees/acme/other/foreign"
git -C "$TMP/repo" worktree add -q -b sibling-branch "$HOME/.worktrees/acme/demo-2/sibling"
out="$(cd "$TMP/repo" && "$WT" list 2>&1)" || fail "$name: th-wt list falló: [$out]"
case "$out" in *feature/login*) ;; *) fail "$name: no aparece feature/login: [$out]" ;; esac
for hidden in "$TMP/repo" outside-branch foreign-branch sibling-branch; do
  case "$out" in *"$hidden"*) fail "$name: aparece $hidden: [$out]" ;; esac
done
pass "$name"

name="list sin worktrees bajo la raíz dice que no hay ninguno, con exit 0"
git init -q -b main "$TMP/lonely"
git -C "$TMP/lonely" commit -q --allow-empty -m init
git -C "$TMP/lonely" remote add origin "git@github.com:acme/lonely.git"
git -C "$TMP/lonely" fetch -q "$TMP/origin.git" main:refs/remotes/origin/main
git -C "$TMP/lonely" remote set-head origin main >/dev/null
rc=0
out="$(cd "$TMP/lonely" && "$WT" list 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
case "$out" in *"no worktrees"*) ;; *) fail "$name: no dice que no hay worktrees: [$out]" ;; esac
pass "$name"
