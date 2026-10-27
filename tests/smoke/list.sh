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

name="list --json devuelve un único objeto con repo y worktrees ([] si no hay)"
out="$(cd "$TMP/repo" && "$WT" list --json 2>/dev/null)" || fail "$name: th-wt list --json falló"
printf '%s' "$out" | jq -e 'type == "object" and (keys == ["repo", "worktrees"])' >/dev/null || fail "$name: no es un objeto con repo y worktrees: [$out]"
[ "$(printf '%s' "$out" | jq -r .repo)" = "acme/demo" ] || fail "$name: repo incorrecto: [$out]"
entry="$(printf '%s' "$out" | jq -S -c '.worktrees[] | select(.branch == "feature/login")')"
expected="{\"branch\":\"feature/login\",\"dirty\":false,\"merged\":true,\"missing\":false,\"path\":\"$HOME/.worktrees/acme/demo/feature-login\"}"
[ "$entry" = "$expected" ] || fail "$name: entrada=[$entry]"
out="$(cd "$TMP/lonely" && "$WT" list --json 2>/dev/null)" || fail "$name: th-wt list --json falló sin worktrees"
[ "$(printf '%s' "$out" | jq -S -c .)" = '{"repo":"acme/lonely","worktrees":[]}' ] || fail "$name: vacío=[$out]"
pass "$name"

name="list funciona con origin inalcanzable (no usa la red)"
mv "$TMP/origin.git" "$TMP/origin.gone"
rc=0
out="$(cd "$TMP/repo" && "$WT" list --json 2>&1)" || rc=$?
mv "$TMP/origin.gone" "$TMP/origin.git"
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
[ "$(printf '%s' "$out" | jq -r '.worktrees[] | select(.branch == "feature/login") | .branch')" = "feature/login" ] || fail "$name: no aparece feature/login: [$out]"
pass "$name"

name="list muestra como faltante un worktree cuyo directorio se borró y lista el resto"
(cd "$TMP/repo" && "$WT" new feature/gone) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-gone"
rm -rf "$dest"
out="$(cd "$TMP/repo" && "$WT" list --json 2>/dev/null)" || fail "$name: th-wt list --json abortó"
entry="$(printf '%s' "$out" | jq -S -c '.worktrees[] | select(.branch == "feature/gone")')"
expected="{\"branch\":\"feature/gone\",\"dirty\":false,\"merged\":true,\"missing\":true,\"path\":\"$dest\"}"
[ "$entry" = "$expected" ] || fail "$name: entrada=[$entry]"
[ "$(printf '%s' "$out" | jq -r '.worktrees[] | select(.branch == "feature/login") | .missing')" = false ] || fail "$name: feature/login no aparece intacto: [$out]"
out="$(cd "$TMP/repo" && "$WT" list 2>&1)" || fail "$name: th-wt list abortó"
line="$(printf '%s\n' "$out" | grep -F "feature/gone")" || fail "$name: no aparece la rama: [$out]"
case "$line" in *missing*) ;; *) fail "$name: la línea no dice missing: [$line]" ;; esac
pass "$name"

name="list sin origin o fuera de un repo git → exit 4 con mensaje"
git init -q -b main "$TMP/no-origin"
git -C "$TMP/no-origin" commit -q --allow-empty -m init
rc=0
err="$(cd "$TMP/no-origin" && "$WT" list 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: sin origin: exit=$rc, esperado 4"
case "$err" in *"th-wt: "*origin*) ;; *) fail "$name: sin origin: el mensaje no menciona origin: [$err]" ;; esac
mkdir "$TMP/plain"
rc=0
err="$(cd "$TMP/plain" && "$WT" list 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: fuera de repo: exit=$rc, esperado 4"
case "$err" in *"not a git repository"*) ;; *) fail "$name: fuera de repo: el mensaje no habla de repo git: [$err]" ;; esac
pass "$name"

name="list ejecutado desde dentro de un worktree da el mismo resultado que desde el checkout principal"
inside="$HOME/.worktrees/acme/demo/feature-login"
from_main="$(cd "$TMP/repo" && "$WT" list --json 2>/dev/null | jq -S -c .)"
from_inside="$(cd "$inside" && "$WT" list --json 2>/dev/null | jq -S -c .)" || fail "$name: th-wt list falló dentro del worktree"
[ -n "$from_main" ] || fail "$name: salida vacía desde el checkout principal"
[ "$from_main" = "$from_inside" ] || fail "$name: principal=[$from_main] dentro=[$from_inside]"
pass "$name"

name="list sin origin/HEAD local muestra merged desconocido (null) en lugar de abortar"
git init -q -b main "$TMP/nohead"
git -C "$TMP/nohead" commit -q --allow-empty -m init
git -C "$TMP/nohead" remote add origin "git@github.com:acme/nohead.git"
dest="$HOME/.worktrees/acme/nohead/feature-x"
git -C "$TMP/nohead" worktree add -q -b feature/x "$dest"
rc=0
out="$(cd "$TMP/nohead" && "$WT" list --json 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
expected="{\"branch\":\"feature/x\",\"dirty\":false,\"merged\":null,\"missing\":false,\"path\":\"$dest\"}"
[ "$(printf '%s' "$out" | jq -S -c '.worktrees[]')" = "$expected" ] || fail "$name: json=[$out]"
out="$(cd "$TMP/nohead" && "$WT" list 2>&1)" || fail "$name: th-wt list abortó"
line="$(printf '%s\n' "$out" | grep -F "feature/x")" || fail "$name: no aparece la rama: [$out]"
case "$line" in *unknown*) ;; *) fail "$name: la línea no dice unknown: [$line]" ;; esac
pass "$name"

name="list con opción o argumento desconocido → exit 2 sin salida de datos"
for args in "--jsno" "foo" "--json --bogus"; do
  rc=0
  # shellcheck disable=SC2086
  out="$(cd "$TMP/repo" && "$WT" list $args 2>/dev/null)" || rc=$?
  [ "$rc" = 2 ] || fail "$name: [$args]: exit=$rc, esperado 2"
  [ -z "$out" ] || fail "$name: [$args]: imprimió a stdout: [$out]"
done
pass "$name"

name="list muestra un worktree con HEAD desacoplado con branch null y merged calculado sobre HEAD"
dest="$HOME/.worktrees/acme/demo/detached-check"
git -C "$TMP/repo" worktree add -q --detach "$dest" origin/main
out="$(cd "$TMP/repo" && "$WT" list --json 2>/dev/null)" || fail "$name: th-wt list --json falló"
entry="$(printf '%s' "$out" | jq -S -c --arg p "$dest" '.worktrees[] | select(.path == $p)')"
expected="{\"branch\":null,\"dirty\":false,\"merged\":true,\"missing\":false,\"path\":\"$dest\"}"
[ "$entry" = "$expected" ] || fail "$name: entrada=[$entry]"
git -C "$dest" commit -q --allow-empty -m "commit suelto"
out="$(cd "$TMP/repo" && "$WT" list --json 2>/dev/null)"
[ "$(printf '%s' "$out" | jq -c --arg p "$dest" '.worktrees[] | select(.path == $p) | .merged')" = false ] || fail "$name: con un commit propio debería ser merged=false: [$out]"
out="$(cd "$TMP/repo" && "$WT" list 2>&1)" || fail "$name: th-wt list falló"
line="$(printf '%s\n' "$out" | grep -F "$dest")" || fail "$name: no aparece la ruta: [$out]"
case "$line" in *"(detached)"*) ;; *) fail "$name: la línea no dice (detached): [$line]" ;; esac
pass "$name"

name="list con origin/HEAD apuntando a una rama que ya no existe muestra merged desconocido (null) sin error de git"
git -C "$TMP/nohead" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/gone
dest="$HOME/.worktrees/acme/nohead/feature-x"
rc=0
out="$(cd "$TMP/nohead" && "$WT" list --json 2>"$TMP/dangling.err")" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
expected="{\"branch\":\"feature/x\",\"dirty\":false,\"merged\":null,\"missing\":false,\"path\":\"$dest\"}"
[ "$(printf '%s' "$out" | jq -S -c '.worktrees[]')" = "$expected" ] || fail "$name: json=[$out]"
[ ! -s "$TMP/dangling.err" ] || fail "$name: escribió a stderr: [$(cat "$TMP/dangling.err")]"
out="$(cd "$TMP/nohead" && "$WT" list 2>&1)" || fail "$name: th-wt list abortó"
case "$out" in *"containment unknown"*) ;; *) fail "$name: el texto no dice containment unknown: [$out]" ;; esac
pass "$name"

name="list marca dirty un archivo nuevo aunque status.showUntrackedFiles=no"
(cd "$TMP/repo" && "$WT" new feature/untracked-cfg) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-untracked-cfg"
echo nuevo > "$dest/nuevo.txt"
git config --global status.showUntrackedFiles no
out="$(cd "$TMP/repo" && "$WT" list --json 2>/dev/null)" || fail "$name: th-wt list --json falló"
git config --global --unset status.showUntrackedFiles
[ "$(printf '%s' "$out" | jq -c '.worktrees[] | select(.branch == "feature/untracked-cfg") | .dirty')" = true ] || fail "$name: dirty debería ser true: [$out]"
pass "$name"

name="list no modifica el índice del worktree (no toma index.lock)"
(cd "$TMP/repo" && "$WT" new feature/no-lock) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-no-lock"
# Mismo contenido, otro mtime: un git status normal refrescaría y reescribiría el índice.
touch -t 202001010000 "$dest/tracked.txt"
index="$(git -C "$dest" rev-parse --absolute-git-dir)/index"
before="$(cksum < "$index")"
(cd "$TMP/repo" && "$WT" list --json >/dev/null 2>&1) || fail "$name: th-wt list falló"
after="$(cksum < "$index")"
[ "$before" = "$after" ] || fail "$name: el índice cambió: antes=[$before] después=[$after]"
pass "$name"
