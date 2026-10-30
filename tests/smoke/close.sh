#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

# La rama por defecto local sale de refs/remotes/origin/HEAD; no se consulta la red.
git -C "$TMP/repo" remote set-head origin main >/dev/null

name="close sin --yes muestra ruta, rama, mergeada, cambios, commits sin push y qué se borra, y no toca nada"
(cd "$TMP/repo" && "$WT" new feature/x) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-x"
out="$(cd "$TMP/repo" && "$WT" close feature/x 2>&1)" || fail "$name: th-wt close falló: [$out]"
for pat in "branch: +feature/x" "merged: +true" "dirty: +false" "unpushed: +0 commits" "delete: +worktree and branch"; do
  printf '%s\n' "$out" | grep -qE "$pat" || fail "$name: falta [$pat]: [$out]"
done
printf '%s\n' "$out" | grep -qF "$dest" || fail "$name: falta la ruta: [$out]"
[ -d "$dest" ] || fail "$name: se borró el directorio en el dry-run"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/x || fail "$name: se borró la rama en el dry-run"
pass "$name"

name="close --json sin --yes devuelve un único objeto con el plan"
out="$(cd "$TMP/repo" && "$WT" close feature/x --json 2>/dev/null)" || fail "$name: th-wt close --json falló"
expected="{\"branch\":\"feature/x\",\"delete\":{\"branch\":true,\"worktree\":true},\"dirty\":false,\"merged\":true,\"missing\":false,\"path\":\"$dest\",\"unpushed\":0}"
[ "$(printf '%s' "$out" | jq -S -c .)" = "$expected" ] || fail "$name: plan=[$out]"
[ -d "$dest" ] || fail "$name: se borró el directorio en el dry-run"
pass "$name"

name="close de una rama sin worktree bajo la raíz → exit 4 sin borrar nada"
git -C "$TMP/repo" branch -q sin-worktree
rc=0
out="$(cd "$TMP/repo" && "$WT" close sin-worktree 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: rama sin worktree: exit=$rc, esperado 4: [$out]"
git -C "$TMP/repo" worktree add -q -b fuera "$TMP/fuera"
rc=0
out="$(cd "$TMP/repo" && "$WT" close fuera 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: worktree fuera de la raíz: exit=$rc, esperado 4: [$out]"
[ -d "$TMP/fuera" ] || fail "$name: se borró el worktree fuera de la raíz"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/sin-worktree || fail "$name: se borró la rama"
pass "$name"

name="close sin rama o con opción desconocida → exit 2 sin borrar nada"
rc=0
(cd "$TMP/repo" && "$WT" close >/dev/null 2>&1) || rc=$?
[ "$rc" = 2 ] || fail "$name: sin rama: exit=$rc, esperado 2"
rc=0
(cd "$TMP/repo" && "$WT" close feature/x --bogus >/dev/null 2>&1) || rc=$?
[ "$rc" = 2 ] || fail "$name: opción desconocida: exit=$rc, esperado 2"
[ -d "$dest" ] || fail "$name: se borró el worktree"
pass "$name"

name="close --yes de un worktree limpio con rama mergeada borra el directorio y la rama"
(cd "$TMP/repo" && "$WT" new feature/y) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-y"
rc=0
out="$(cd "$TMP/repo" && "$WT" close feature/y --yes 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
[ ! -e "$dest" ] || fail "$name: sigue el directorio"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/y && fail "$name: sigue la rama"
wts="$(git -C "$TMP/repo" worktree list --porcelain)"
case "$wts" in *"$dest"*) fail "$name: git worktree list aún muestra el worktree" ;; esac
pass "$name"

name="close --yes con rama no mergeada borra el directorio, conserva la rama y avisa"
(cd "$TMP/repo" && "$WT" new feature/z) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-z"
git -C "$dest" commit -q --allow-empty -m "trabajo sin mergear"
git -C "$dest" push -q origin HEAD:feature/z
rc=0
out="$(cd "$TMP/repo" && "$WT" close feature/z --yes 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
[ ! -e "$dest" ] || fail "$name: sigue el directorio"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/z || fail "$name: se borró la rama no mergeada"
printf '%s\n' "$out" | grep -qE '^th-wt: .*feature/z.*kept' || fail "$name: no hay aviso de rama conservada: [$out]"
pass "$name"

name="close --yes borra una rama contenida en origin/main aunque main local esté atrasada"
(cd "$TMP/repo" && "$WT" new feature/w) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-w"
git -C "$dest" commit -q --allow-empty -m "integrado"
git -C "$dest" push -q origin HEAD:main
git -C "$TMP/repo" fetch -q origin
[ "$(git -C "$TMP/repo" rev-parse main)" != "$(git -C "$TMP/repo" rev-parse origin/main)" ] || fail "$name: el setup no dejó main atrasada"
rc=0
out="$(cd "$TMP/repo" && "$WT" close feature/w --yes 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
[ ! -e "$dest" ] || fail "$name: sigue el directorio"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/w && fail "$name: sigue la rama contenida en origin/main"
pass "$name"

name="close --yes con cambios sin commitear → exit 4, no borra nada y dice por qué"
(cd "$TMP/repo" && "$WT" new feature/d) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-d"
echo sucio > "$dest/sucio.txt"
rc=0
out="$(cd "$TMP/repo" && "$WT" close feature/d --yes 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$out]"
[ -d "$dest" ] || fail "$name: se borró el directorio"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/d || fail "$name: se borró la rama"
reason="$(printf '%s\n' "$out" | grep '^th-wt: ' || true)"
case "$reason" in *"uncommitted changes"*) ;; *) fail "$name: el motivo no dice cambios sin commitear: [$reason]" ;; esac
case "$reason" in *unpushed*) fail "$name: el motivo menciona commits sin push: [$reason]" ;; esac
pass "$name"

name="close --yes con commits sin push → exit 4, no borra nada y dice por qué"
(cd "$TMP/repo" && "$WT" new feature/p) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-p"
git -C "$dest" commit -q --allow-empty -m "sin push"
rc=0
out="$(cd "$TMP/repo" && "$WT" close feature/p --yes 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$out]"
[ -d "$dest" ] || fail "$name: se borró el directorio"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/p || fail "$name: se borró la rama"
reason="$(printf '%s\n' "$out" | grep '^th-wt: ' || true)"
case "$reason" in *"1 unpushed"*) ;; *) fail "$name: el motivo no dice 1 unpushed: [$reason]" ;; esac
case "$reason" in *uncommitted*) fail "$name: el motivo menciona cambios sin commitear: [$reason]" ;; esac
pass "$name"

name="close --yes --force con cambios y commits sin push cierra el worktree y conserva la rama no mergeada"
(cd "$TMP/repo" && "$WT" new feature/f) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-f"
git -C "$dest" commit -q --allow-empty -m "sin push"
echo sucio > "$dest/sucio.txt"
oid="$(git -C "$TMP/repo" rev-parse refs/heads/feature/f)"
rc=0
out="$(cd "$TMP/repo" && "$WT" close feature/f --yes --force 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
[ ! -e "$dest" ] || fail "$name: sigue el directorio"
[ "$(git -C "$TMP/repo" rev-parse refs/heads/feature/f)" = "$oid" ] || fail "$name: la rama cambió o no existe"
printf '%s\n' "$out" | grep -qE '^th-wt: .*feature/f.*kept' || fail "$name: no hay aviso de rama conservada: [$out]"
pass "$name"

name="close --yes desde dentro del worktree a cerrar → exit 4"
(cd "$TMP/repo" && "$WT" new feature/c) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-c"
mkdir "$dest/sub"
rc=0
out="$(cd "$dest/sub" && "$WT" close feature/c --yes 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: desde un subdirectorio: exit=$rc, esperado 4: [$out]"
rc=0
out="$(cd "$dest" && "$WT" close feature/c --yes 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: desde la raíz del worktree: exit=$rc, esperado 4: [$out]"
[ -d "$dest" ] || fail "$name: se borró el directorio"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/c || fail "$name: se borró la rama"
pass "$name"

name="close de un worktree con el directorio borrado lo muestra como faltante y lo cierra sin --force"
(cd "$TMP/repo" && "$WT" new feature/m) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-m"
rm -rf "$dest"
out="$(cd "$TMP/repo" && "$WT" close feature/m --json 2>/dev/null)" || fail "$name: th-wt close --json falló"
[ "$(printf '%s' "$out" | jq -c '[.missing, .dirty, .merged]')" = "[true,null,true]" ] || fail "$name: plan=[$out]"
out="$(cd "$TMP/repo" && "$WT" close feature/m 2>&1)" || fail "$name: th-wt close falló: [$out]"
printf '%s\n' "$out" | grep -qi 'missing' || fail "$name: el plan no dice que falta el directorio: [$out]"
printf '%s\n' "$out" | grep -qE 'dirty: +unknown' || fail "$name: dirty no sale unknown: [$out]"
rc=0
out="$(cd "$TMP/repo" && "$WT" close feature/m --yes 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
wts="$(git -C "$TMP/repo" worktree list --porcelain)"
case "$wts" in *"$dest"*) fail "$name: git worktree list aún muestra el worktree" ;; esac
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/m && fail "$name: sigue la rama"
pass "$name"

name="close sin origin/HEAD local muestra merged desconocido, conserva la rama y sugiere git remote set-head origin -a"
(cd "$TMP/repo" && "$WT" new feature/u) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-u"
git -C "$TMP/repo" remote set-head origin -d >/dev/null
out="$(cd "$TMP/repo" && "$WT" close feature/u --json 2>/dev/null)" || fail "$name: th-wt close --json falló"
[ "$(printf '%s' "$out" | jq -c '[.merged, .delete.branch]')" = "[null,false]" ] || fail "$name: plan=[$out]"
out="$(cd "$TMP/repo" && "$WT" close feature/u 2>&1)" || fail "$name: th-wt close falló: [$out]"
printf '%s\n' "$out" | grep -qE 'merged: +unknown' || fail "$name: merged no sale unknown: [$out]"
rc=0
out="$(cd "$TMP/repo" && "$WT" close feature/u --yes 2>&1)" || rc=$?
git -C "$TMP/repo" remote set-head origin main >/dev/null
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
[ ! -e "$dest" ] || fail "$name: sigue el directorio"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/u || fail "$name: se borró la rama con merged desconocido"
printf '%s\n' "$out" | grep -qF 'git remote set-head origin -a' || fail "$name: falta la sugerencia: [$out]"
pass "$name"

name="close --yes de un worktree bloqueado → exit 4 con mensaje"
(cd "$TMP/repo" && "$WT" new feature/l) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-l"
git -C "$TMP/repo" worktree lock "$dest"
rc=0
out="$(cd "$TMP/repo" && "$WT" close feature/l --yes 2>&1)" || rc=$?
git -C "$TMP/repo" worktree unlock "$dest"
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$out]"
printf '%s\n' "$out" | grep -q '^th-wt: ' || fail "$name: falta el mensaje th-wt: [$out]"
[ -d "$dest" ] || fail "$name: se borró el directorio"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/l || fail "$name: se borró la rama"
pass "$name"

name="close --yes no borra del registro otros worktrees con el directorio faltante"
(cd "$TMP/repo" && "$WT" new feature/gone) || fail "$name: th-wt new falló"
gone="$HOME/.worktrees/acme/demo/feature-gone"
rm -rf "$gone"
(cd "$TMP/repo" && "$WT" new feature/g) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-g"
rc=0
out="$(cd "$TMP/repo" && "$WT" close feature/g --yes 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
[ ! -e "$dest" ] || fail "$name: sigue el directorio"
wts="$(git -C "$TMP/repo" worktree list --porcelain)"
case "$wts" in *"$gone"*) ;; *) fail "$name: se borró del registro el worktree con directorio faltante" ;; esac
pass "$name"
