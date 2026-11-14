#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

# El repo de prueba versiona un .gitignore con las rutas a enlazar (sin barra final) y las tiene en el checkout principal.
printf '%s\n' .env .wiki docs/local > "$TMP/repo/.gitignore"
git -C "$TMP/repo" add .gitignore
git -C "$TMP/repo" commit -q -m "gitignore"
git -C "$TMP/repo" push -q origin main
echo "SECRETO=1" > "$TMP/repo/.env"
mkdir -p "$TMP/repo/.wiki" "$TMP/repo/docs/local"
echo nota > "$TMP/repo/.wiki/nota.md"
echo doc > "$TMP/repo/docs/local/doc.md"

CONF_DIR="$TMP/xdg/th-worktools/repos/acme"
CONF="$CONF_DIR/demo.conf"
mkdir -p "$CONF_DIR"
export XDG_CONFIG_HOME="$TMP/xdg"

printf 'link .env\n' > "$CONF"
(cd "$TMP/repo" && "$WT" new feature/lk >/dev/null 2>&1) || fail "setup: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-lk"

name="link agrega el enlace de una línea nueva del .conf a un worktree abierto, sin tocar los que ya estaban"
printf 'link .env\nlink .wiki\n' > "$CONF"
out="$(cd "$TMP/repo" && "$WT" link feature/lk --json 2>/dev/null)" || fail "$name: th-wt link falló"
[ "$(jq -c .linked <<<"$out")" = '[".wiki"]' ] || fail "$name: salida=[$out]"
[ "$(jq -r .path <<<"$out")" = "$dest" ] || fail "$name: path de la salida: [$out]"
[ "$(jq -r .branch <<<"$out")" = "feature/lk" ] || fail "$name: branch de la salida: [$out]"
[ "$(jq -r .repo <<<"$out")" = "acme/demo" ] || fail "$name: repo de la salida: [$out]"
[ "$(readlink "$dest/.wiki")" = "$TMP/repo/.wiki" ] || fail "$name: .wiki apunta a [$(readlink "$dest/.wiki")]"
[ "$(readlink "$dest/.env")" = "$TMP/repo/.env" ] || fail "$name: .env apunta a [$(readlink "$dest/.env")]"
[ -z "$(git -C "$dest" status --porcelain)" ] || fail "$name: git status no está limpio: [$(git -C "$dest" status --porcelain)]"
pass "$name"

name="link sin entradas nuevas sale con 0 y linked [] (repetirlo es seguro)"
out="$(cd "$TMP/repo" && "$WT" link feature/lk --json 2>/dev/null)" || fail "$name: th-wt link falló"
[ "$(jq -c .linked <<<"$out")" = '[]' ] || fail "$name: salida=[$out]"
[ "$(readlink "$dest/.wiki")" = "$TMP/repo/.wiki" ] || fail "$name: .wiki apunta a [$(readlink "$dest/.wiki")]"
pass "$name"

name="en texto, stderr nombra cada ruta enlazada y el resumen, y stdout queda vacío"
printf 'link .env\nlink .wiki\nlink docs/local\n' > "$CONF"
(cd "$TMP/repo" && "$WT" link feature/lk 2>"$TMP/txt.err" >"$TMP/txt.out") || fail "$name: th-wt link falló"
[ ! -s "$TMP/txt.out" ] || fail "$name: stdout no vacío: [$(cat "$TMP/txt.out")]"
grep -qxF "th-wt: linked docs/local" "$TMP/txt.err" || fail "$name: stderr=[$(cat "$TMP/txt.err")]"
! grep -qxF "th-wt: linked .env" "$TMP/txt.err" || fail "$name: nombró un enlace que ya existía: [$(cat "$TMP/txt.err")]"
grep -qxF "  path:      $dest" "$TMP/txt.err" || fail "$name: stderr=[$(cat "$TMP/txt.err")]"
grep -qxF "  branch:    feature/lk" "$TMP/txt.err" || fail "$name: stderr=[$(cat "$TMP/txt.err")]"
grep -qxF "  linked:    docs/local" "$TMP/txt.err" || fail "$name: stderr=[$(cat "$TMP/txt.err")]"
(cd "$TMP/repo" && "$WT" link feature/lk 2>"$TMP/txt.err" >/dev/null) || fail "$name: th-wt link (repetido) falló"
grep -qxF "  linked:    none" "$TMP/txt.err" || fail "$name: sin nuevos, stderr=[$(cat "$TMP/txt.err")]"
pass "$name"

name="repo sin .conf: sale con 0, linked [] y avisa de que no hay nada que enlazar"
rm "$CONF"
out="$(cd "$TMP/repo" && "$WT" link feature/lk --json 2>"$TMP/none.err")" || fail "$name: th-wt link falló"
[ "$(jq -c .linked <<<"$out")" = '[]' ] || fail "$name: salida=[$out]"
grep -qxF "th-wt: no repo config ($CONF); nothing to link" "$TMP/none.err" || fail "$name: stderr=[$(cat "$TMP/none.err")]"
pass "$name"

name="link con la rama abierta en dos worktrees bajo la raíz sale con 0 y enlaza en el primero"
printf 'link .wiki\n' > "$CONF"
rm -f "$dest/.wiki"
other="$HOME/.worktrees/acme/demo/otro-lk"
git -C "$TMP/repo" worktree add -f -q "$other" feature/lk
rc=0
out="$(cd "$TMP/repo" && "$WT" link feature/lk --json 2>"$TMP/two.err")" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc: [$(cat "$TMP/two.err")]"
[ "$(jq -r .path <<<"$out")" = "$dest" ] || fail "$name: path de la salida: [$out]"
[ "$(readlink "$dest/.wiki")" = "$TMP/repo/.wiki" ] || fail "$name: .wiki apunta a [$(readlink "$dest/.wiki")]"
{ [ ! -e "$other/.wiki" ] && [ ! -L "$other/.wiki" ]; } || fail "$name: enlazó en el segundo worktree"
pass "$name"
