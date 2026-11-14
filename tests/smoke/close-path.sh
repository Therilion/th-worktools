#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

# La rama por defecto local sale de refs/remotes/origin/HEAD; no se consulta la red.
git -C "$TMP/repo" remote set-head origin main >/dev/null

# Dos commits extra en main/origin para que `bisect start HEAD HEAD~2` detenga HEAD en el punto medio (desacoplado).
git -C "$TMP/repo" commit -q --allow-empty -m "c1"
git -C "$TMP/repo" commit -q --allow-empty -m "c2"
git -C "$TMP/repo" push -q origin main

name="close <ruta> de un worktree en bisect muestra el plan sin rama, no borra nada y acepta ruta relativa con barra final"
(cd "$TMP/repo" && "$WT" new feature/bx) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-bx"
git -C "$dest" bisect start HEAD HEAD~2 >/dev/null 2>&1
git -C "$dest" worktree list --porcelain | grep -q '^detached$' || fail "$name: el setup no dejó HEAD desacoplado"
branch_oid="$(git -C "$TMP/repo" rev-parse refs/heads/feature/bx)"
rel="../home/.worktrees/acme/demo/feature-bx/"
out="$(cd "$TMP/repo" && "$WT" close "$rel" 2>&1)" || fail "$name: th-wt close falló: [$out]"
for pat in "branch: +\(detached\)" "unpushed: +0 commits only in this HEAD" "delete: +worktree only \(detached HEAD, no branch\)"; do
  printf '%s\n' "$out" | grep -qE "$pat" || fail "$name: falta [$pat]: [$out]"
done
printf '%s\n' "$out" | grep -qF "$dest" || fail "$name: falta la ruta: [$out]"
[ -d "$dest" ] || fail "$name: se borró el directorio en el dry-run"
[ "$(git -C "$TMP/repo" rev-parse refs/heads/feature/bx)" = "$branch_oid" ] || fail "$name: cambió la rama en el dry-run"
pass "$name"

name="close <ruta> --json de un worktree desacoplado da branch null y delete.branch false"
out="$(cd "$TMP/repo" && "$WT" close "$dest" --json 2>/dev/null)" || fail "$name: th-wt close --json falló"
expected="{\"branch\":null,\"delete\":{\"branch\":false,\"worktree\":true},\"dirty\":false,\"ignored\":[],\"merged\":true,\"missing\":false,\"path\":\"$dest\",\"unpushed\":0}"
[ "$(printf '%s' "$out" | jq -S -c .)" = "$expected" ] || fail "$name: plan=[$out]"
pass "$name"

name="close <ruta> --yes de un worktree en bisect borra el worktree y conserva la rama"
rc=0
out="$(cd "$TMP/repo" && "$WT" close "$dest" --yes 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
[ ! -e "$dest" ] || fail "$name: sigue el directorio"
wts="$(git -C "$TMP/repo" worktree list --porcelain)"
case "$wts" in *"$dest"*) fail "$name: git worktree list aún muestra el worktree" ;; esac
[ "$(git -C "$TMP/repo" rev-parse refs/heads/feature/bx)" = "$branch_oid" ] || fail "$name: la rama cambió o no existe"
if printf '%s\n' "$out" | grep -qE '^th-wt: branch .* kept'; then
  fail "$name: imprimió aviso de rama conservada: [$out]"
fi
pass "$name"

name="close <ruta> --yes de un rebase a medias con commits solo en HEAD → exit 4 sin borrar; con --force lo cierra"
(cd "$TMP/repo" && "$WT" new feature/rb) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-rb"
echo x > "$dest/f.txt"
git -C "$dest" add f.txt
git -C "$dest" commit -q -m "rb1"
rb_oid="$(git -C "$TMP/repo" rev-parse refs/heads/feature/rb)"
echo m > "$TMP/repo/m.txt"
git -C "$TMP/repo" add m.txt
git -C "$TMP/repo" commit -q -m "m1"
git -C "$TMP/repo" push -q origin main
GIT_SEQUENCE_EDITOR='sed -i.bak s/^pick/edit/' git -C "$dest" rebase -i origin/main >/dev/null 2>&1
git -C "$dest" worktree list --porcelain | grep -q '^detached$' || fail "$name: el setup no dejó HEAD desacoplado"
[ "$(git -C "$dest" rev-list --count HEAD --not --branches --remotes=origin)" -ge 1 ] || fail "$name: el setup no dejó commits solo en HEAD"
rc=0
out="$(cd "$TMP/repo" && "$WT" close "$dest" --yes 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$out]"
[ -d "$dest" ] || fail "$name: se borró el directorio sin --force"
case "$out" in *"commit(s) only in its detached HEAD"*) ;; *) fail "$name: falta motivo de commits solo en HEAD: [$out]" ;; esac
rc=0
out="$(cd "$TMP/repo" && "$WT" close "$dest" --yes --force 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: con --force: exit=$rc, esperado 0: [$out]"
[ ! -e "$dest" ] || fail "$name: sigue el directorio tras --force"
[ "$(git -C "$TMP/repo" rev-parse refs/heads/feature/rb)" = "$rb_oid" ] || fail "$name: cambió o se borró la rama"
pass "$name"

name="close <ruta> de un worktree con rama da el mismo plan que close <rama>"
(cd "$TMP/repo" && "$WT" new feature/eq) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-eq"
by_branch="$(cd "$TMP/repo" && "$WT" close feature/eq --json 2>/dev/null | jq -S -c .)" || fail "$name: close <rama> --json falló"
by_path="$(cd "$TMP/repo" && "$WT" close "$dest" --json 2>/dev/null | jq -S -c .)" || fail "$name: close <ruta> --json falló"
[ "$by_branch" = "$by_path" ] || fail "$name: difieren: rama=[$by_branch] ruta=[$by_path]"
pass "$name"

name="close <ruta> fuera de la raíz o sin worktree → exit 4 sin borrar nada"
git -C "$TMP/repo" worktree add -q --detach "$TMP/fuera-det"
rc=0
out="$(cd "$TMP/repo" && "$WT" close "$TMP/fuera-det" 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: fuera de la raíz: exit=$rc, esperado 4: [$out]"
case "$out" in *"no worktree at"*) ;; *) fail "$name: fuera de la raíz: falta 'no worktree at': [$out]" ;; esac
[ -d "$TMP/fuera-det" ] || fail "$name: se borró el worktree fuera de la raíz"
mkdir "$TMP/no-wt"
rc=0
out="$(cd "$TMP/repo" && "$WT" close "$TMP/no-wt" 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: sin worktree: exit=$rc, esperado 4: [$out]"
case "$out" in *"no worktree at"*) ;; *) fail "$name: sin worktree: falta 'no worktree at': [$out]" ;; esac
[ -d "$TMP/no-wt" ] || fail "$name: se borró el directorio sin worktree"
pass "$name"

name="close <ruta> --remote de un worktree desacoplado → exit 2"
(cd "$TMP/repo" && "$WT" new feature/rem) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-rem"
git -C "$dest" checkout -q --detach
rc=0
out="$(cd "$TMP/repo" && "$WT" close "$dest" --remote 2>&1)" || rc=$?
[ "$rc" = 2 ] || fail "$name: exit=$rc, esperado 2: [$out]"
case "$out" in *"--remote needs a branch:"*"has a detached HEAD"*) ;; *) fail "$name: mensaje inesperado: [$out]" ;; esac
pass "$name"

name="close <ruta> de un worktree desacoplado cuyo directorio ya no existe limpia el registro"
(cd "$TMP/repo" && "$WT" new feature/mis) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-mis"
git -C "$dest" checkout -q --detach
rm -rf "$dest"
out="$(cd "$TMP/repo" && "$WT" close "$dest" --json 2>/dev/null)" || fail "$name: close --json falló"
[ "$(printf '%s' "$out" | jq -c '[.branch, .missing]')" = '[null,true]' ] || fail "$name: plan=[$out]"
rc=0
out="$(cd "$TMP/repo" && "$WT" close "$dest" --yes 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
wts="$(git -C "$TMP/repo" worktree list --porcelain)"
case "$wts" in *"$dest"*) fail "$name: git worktree list aún muestra el worktree" ;; esac
pass "$name"

name="close <ruta> de una rama abierta en dos worktrees cierra el de esa ruta"
(cd "$TMP/repo" && "$WT" new feature/dup) || fail "$name: th-wt new falló"
dup_a="$HOME/.worktrees/acme/demo/feature-dup"
dup_b="$HOME/.worktrees/acme/demo/dup-b"
git -C "$TMP/repo" worktree add -q -f "$dup_b" feature/dup
out="$(cd "$TMP/repo" && "$WT" close "$dup_a" --json 2>/dev/null)" || fail "$name: close A --json falló"
[ "$(printf '%s' "$out" | jq -r '.path')" = "$dup_a" ] || fail "$name: A .path=[$(printf '%s' "$out" | jq -r '.path')], esperado [$dup_a]"
out="$(cd "$TMP/repo" && "$WT" close "$dup_b" --json 2>/dev/null)" || fail "$name: close B --json falló"
[ "$(printf '%s' "$out" | jq -r '.path')" = "$dup_b" ] || fail "$name: B .path=[$(printf '%s' "$out" | jq -r '.path')], esperado [$dup_b]"
rc=0
out="$(cd "$TMP/repo" && "$WT" close "$dup_b" --yes 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
[ -d "$dup_a" ] || fail "$name: se borró el primer worktree ($dup_a)"
[ ! -e "$dup_b" ] || fail "$name: sigue el segundo worktree ($dup_b)"
pass "$name"

name="close <ruta> fuera de la raíz de un worktree con rama → exit 4 con no worktree at"
git -C "$TMP/repo" worktree add -q -b fuera-rama "$TMP/fuera-rama"
rc=0
out="$(cd "$TMP/repo" && "$WT" close "$TMP/fuera-rama" 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$out]"
case "$out" in *"no worktree at"*) ;; *) fail "$name: falta 'no worktree at': [$out]" ;; esac
[ -d "$TMP/fuera-rama" ] || fail "$name: se borró el worktree fuera de la raíz"
pass "$name"

name="close <ruta> relativa de un worktree desacoplado cuyo directorio ya no existe lo encuentra"
(cd "$TMP/repo" && "$WT" new feature/mis-rel) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-mis-rel"
git -C "$dest" checkout -q --detach
rm -rf "$dest"
rel="../home/.worktrees/acme/demo/feature-mis-rel"
out="$(cd "$TMP/repo" && "$WT" close "$rel" --json 2>/dev/null)" || fail "$name: close --json falló"
[ "$(printf '%s' "$out" | jq -c '[.missing, .path]')" = "[true,\"$dest\"]" ] || fail "$name: plan=[$out]"
pass "$name"

name="close <ruta> --yes de un worktree de PR desacoplado quita pr-reviews/pr-<n>/ vacío, conserva review/pr-<n> y dice cómo reabrirlo"
dest="$HOME/.worktrees/acme/demo/pr-reviews/pr-9/code"
git -C "$TMP/repo" worktree add -q -b review/pr-9 "$dest" main
git -C "$dest" checkout -q --detach
rc=0
out="$(cd "$TMP/repo" && "$WT" close "$dest" --yes 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
[ ! -e "$HOME/.worktrees/acme/demo/pr-reviews/pr-9" ] || fail "$name: sigue pr-reviews/pr-9/"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/review/pr-9 || fail "$name: se borró la rama review/pr-9"
case "$out" in *"git branch -D review/pr-9"*) ;; *) fail "$name: falta 'git branch -D review/pr-9': [$out]" ;; esac
pass "$name"
