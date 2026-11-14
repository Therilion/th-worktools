#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

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
(cd "$TMP/repo" && "$WT" new feature/lke >/dev/null 2>&1) || fail "setup: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-lke"

# Verifica que `link <rama>` sale con 4 y "th-wt: <fragmento>" en stderr, con stdout vacío.
reject_link() {
  local name="$1" b="$2" want="$3" rc=0
  (cd "$TMP/repo" && "$WT" link "$b" --json 2>"$TMP/rej.err" >"$TMP/rej.out") || rc=$?
  [ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/rej.err")]"
  grep -qxF "th-wt: $want" "$TMP/rej.err" || fail "$name: stderr=[$(cat "$TMP/rej.err")], esperado: $want"
  [ ! -s "$TMP/rej.out" ] || fail "$name: stdout no vacío: [$(cat "$TMP/rej.out")]"
}

name="link con una ruta ocupada en el worktree (archivo o symlink a otro sitio) sale con 4, sin enlazar ninguna ni borrar nada"
printf 'link .env\nlink .wiki\nlink docs/local\n' > "$CONF"
echo mio > "$dest/.wiki"
reject_link "$name (archivo)" feature/lke "$CONF:2: .wiki already exists in the worktree (not a link to $TMP/repo/.wiki)"
[ "$(cat "$dest/.wiki")" = mio ] || fail "$name: cambió el archivo que ocupaba la ruta"
{ [ ! -e "$dest/docs/local" ] && [ ! -L "$dest/docs/local" ]; } || fail "$name: enlazó docs/local pese al error"
rm "$dest/.wiki"
ln -s "$TMP/repo/docs" "$dest/.wiki"
reject_link "$name (symlink a otro sitio)" feature/lke "$CONF:2: .wiki already exists in the worktree (not a link to $TMP/repo/.wiki)"
[ "$(readlink "$dest/.wiki")" = "$TMP/repo/docs" ] || fail "$name: cambió el symlink que ocupaba la ruta"
{ [ ! -e "$dest/docs/local" ] && [ ! -L "$dest/docs/local" ]; } || fail "$name: enlazó docs/local pese al error"
rm "$dest/.wiki"
pass "$name"

name="link con una línea inválida del .conf (node_modules) sale con 4 sin enlazar nada"
printf 'link .wiki\nlink node_modules\n' > "$CONF"
mkdir -p "$TMP/repo/node_modules"
reject_link "$name" feature/lke "$CONF:2: node_modules cannot be linked (the dependency install would write through the symlink into the main checkout): node_modules"
{ [ ! -e "$dest/.wiki" ] && [ ! -L "$dest/.wiki" ]; } || fail "$name: enlazó .wiki pese al error"
pass "$name"

name="link con una ruta no ignorada en la rama del worktree sale con 4 y el worktree y la rama siguen ahí"
echo cache > "$TMP/repo/.cache"
printf 'link .wiki\nlink .cache\n' > "$CONF"
reject_link "$name" feature/lke "$CONF:2: .cache is not ignored by git in the worktree (versioned, or missing from .gitignore)"
{ [ ! -e "$dest/.wiki" ] && [ ! -L "$dest/.wiki" ]; } || fail "$name: enlazó .wiki pese al error"
[ -d "$dest" ] || fail "$name: se borró el worktree"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/lke || fail "$name: se borró la rama"
git -C "$TMP/repo" worktree list | grep -qF "$dest" || fail "$name: git ya no registra el worktree"
pass "$name"

name="link a una rama sin worktree bajo la raíz (no abierta, solo en el checkout principal o con el directorio borrado) sale con 4"
printf 'link .env\n' > "$CONF"
git -C "$TMP/repo" branch feature/cerrada
reject_link "$name (no abierta)" feature/cerrada "no worktree for branch feature/cerrada under $HOME/.worktrees/acme/demo/"
reject_link "$name (checkout principal)" main "no worktree for branch main under $HOME/.worktrees/acme/demo/"
reject_link "$name (inexistente)" feature/nunca "no worktree for branch feature/nunca under $HOME/.worktrees/acme/demo/"
(cd "$TMP/repo" && "$WT" new feature/borrado >/dev/null 2>&1) || fail "$name: th-wt new falló"
gone="$HOME/.worktrees/acme/demo/feature-borrado"
rm -rf "$gone"
reject_link "$name (directorio borrado)" feature/borrado "worktree directory of feature/borrado no longer exists: $gone"
pass "$name"

name="link a review/pr-* sale con 4 sin enlazar nada"
git -C "$TMP/repo" branch review/pr-7 main
(cd "$TMP/repo" && "$WT" checkout review/pr-7 >/dev/null 2>&1) || fail "$name: checkout review/pr-7 falló"
reject_link "$name" review/pr-7 "review/pr-7 is a PR copy (review/pr-*): the repo .conf is never applied to PR code"
{ [ ! -e "$HOME/.worktrees/acme/demo/review-pr-7/.env" ] && [ ! -L "$HOME/.worktrees/acme/demo/review-pr-7/.env" ]; } || fail "$name: enlazó .env"
pass "$name"

name="link a una rama creada dentro del worktree de un PR sale con 4 sin enlazar nada"
prwt="$HOME/.worktrees/acme/demo/pr-reviews/pr-7/code"
git -C "$TMP/repo" worktree add -q -b fix-typo "$prwt" main
reject_link "$name" fix-typo "$prwt is a PR worktree (pr-reviews/): the repo .conf is never applied to PR code"
{ [ ! -e "$prwt/.env" ] && [ ! -L "$prwt/.env" ]; } || fail "$name: enlazó .env"
pass "$name"

name="link sin rama, con una opción desconocida o con una rama inválida sale con 2"
expect_2() {
  local rc=0
  (cd "$TMP/repo" && "$WT" "$@" >/dev/null 2>"$TMP/usage.err") || rc=$?
  [ "$rc" = 2 ] || fail "$name: $*: exit=$rc, esperado 2"
}
expect_2 link
expect_2 link --json
expect_2 link feature/lke --bogus
expect_2 link feature/lke extra
expect_2 link "mala..rama"
expect_2 link HEAD
pass "$name"
