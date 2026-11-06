#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

CFG_DIR="$HOME/.config/th-worktools"
CFG="$CFG_DIR/config"
ROOT_MSG="TH_WORKTREES_ROOT must be an absolute path or start with ~/, without '.', '..' or empty segments"

# Escribe el config global (printf con formato $1) y deja el estado limpio al terminar cada test con clean_cfg.
# shellcheck disable=SC2059 # el formato lo pone el llamante
set_cfg() { mkdir -p "$CFG_DIR"; printf "$@" > "$CFG"; }
clean_cfg() { rm -rf "$HOME/.config" "$TMP/xdg" "$HOME/wt" "$HOME/wt-home" "$HOME/wt-xdg" "$TMP/envroot"; }

name="TH_WORKTREES_ROOT=~/wt en el config: new crea en ~/wt/acme/demo/<rama>; tolera comentarios, líneas vacías y CRLF"
set_cfg '# raíz local\r\n\r\nTH_WORKTREES_ROOT=~/wt\r\n'
out="$(cd "$TMP/repo" && "$WT" new feature/cfg-new --json 2>"$TMP/cfg.err")" || fail "$name: th-wt new falló: [$(cat "$TMP/cfg.err")]"
dest="$HOME/wt/acme/demo/feature-cfg-new"
[ -d "$dest" ] || fail "$name: no existe $dest"
[ "$(jq -r .path <<<"$out")" = "$dest" ] || fail "$name: salida=[$out]"
[ ! -e "$HOME/.worktrees" ] || fail "$name: se creó ~/.worktrees"
set_cfg 'TH_WORKTREES_ROOT=~/wt/'
(cd "$TMP/repo" && "$WT" new feature/cfg-slash 2>/dev/null) || fail "$name: new con barra final falló"
[ -d "$HOME/wt/acme/demo/feature-cfg-slash" ] || fail "$name: la barra final no se quitó"
set_cfg 'TH_WORKTREES_ROOT=%s/abs' "$TMP"
(cd "$TMP/repo" && "$WT" new feature/cfg-abs 2>/dev/null) || fail "$name: new con ruta absoluta (última línea sin salto) falló"
[ -d "$TMP/abs/acme/demo/feature-cfg-abs" ] || fail "$name: no usó la ruta absoluta"
rm -rf "$TMP/abs"
clean_cfg
pass "$name"

name="con la raíz del config, checkout crea bajo ~/wt y list y close lo encuentran"
set_cfg 'TH_WORKTREES_ROOT=~/wt\n'
git -C "$TMP/repo" branch feature/cfg-co
(cd "$TMP/repo" && "$WT" checkout feature/cfg-co 2>/dev/null) || fail "$name: th-wt checkout falló"
dest="$HOME/wt/acme/demo/feature-cfg-co"
[ -d "$dest" ] || fail "$name: no existe $dest"
out="$(cd "$TMP/repo" && "$WT" list 2>&1)" || fail "$name: th-wt list falló: [$out]"
printf '%s\n' "$out" | grep -F "feature/cfg-co" | grep -qF "$dest" || fail "$name: list no lo encuentra: [$out]"
(cd "$TMP/repo" && "$WT" close feature/cfg-co --yes >/dev/null 2>&1) || fail "$name: th-wt close --yes falló"
[ ! -e "$dest" ] || fail "$name: close no borró el worktree"
clean_cfg
pass "$name"

name="el config se lee de \$XDG_CONFIG_HOME/th-worktools/config, no de ~/.config"
set_cfg 'TH_WORKTREES_ROOT=~/wt-home\n'
mkdir -p "$TMP/xdg/th-worktools"
printf 'TH_WORKTREES_ROOT=~/wt-xdg\n' > "$TMP/xdg/th-worktools/config"
(cd "$TMP/repo" && XDG_CONFIG_HOME="$TMP/xdg" "$WT" new feature/cfg-xdg 2>/dev/null) || fail "$name: th-wt new falló"
[ -d "$HOME/wt-xdg/acme/demo/feature-cfg-xdg" ] || fail "$name: no usó el config de XDG_CONFIG_HOME"
[ ! -e "$HOME/wt-home" ] || fail "$name: leyó ~/.config"
clean_cfg
pass "$name"

name="TH_WORKTREES_ROOT del entorno gana a la del config; vacía cuenta como no definida"
set_cfg 'TH_WORKTREES_ROOT=~/wt\n'
(cd "$TMP/repo" && TH_WORKTREES_ROOT="$TMP/envroot" "$WT" new feature/cfg-env 2>/dev/null) || fail "$name: th-wt new falló"
[ -d "$TMP/envroot/acme/demo/feature-cfg-env" ] || fail "$name: no usó la raíz del entorno"
[ ! -e "$HOME/wt" ] || fail "$name: usó la raíz del config"
(cd "$TMP/repo" && TH_WORKTREES_ROOT="" "$WT" new feature/cfg-empty 2>/dev/null) || fail "$name: new con variable vacía falló"
[ -d "$HOME/wt/acme/demo/feature-cfg-empty" ] || fail "$name: la variable vacía no cedió al config"
clean_cfg
pass "$name"

name="una línea inválida en el config: new sale con 4, no crea worktree ni rama y el error trae <archivo>:<línea>"
i=0
while IFS='|' read -r line reason; do
  i=$((i + 1))
  b="feature/cfg-bad-$i"
  set_cfg '# c\nTH_INSTALL_DEPS=1\n%s\n' "$line"
  rc=0
  (cd "$TMP/repo" && "$WT" new "$b" 2>"$TMP/bad.err" >"$TMP/bad.out") || rc=$?
  [ "$rc" = 4 ] || fail "$name ($line): exit=$rc, esperado 4: [$(cat "$TMP/bad.err")]"
  [ "$(cat "$TMP/bad.err")" = "th-wt: $CFG:3: $reason" ] || fail "$name ($line): stderr=[$(cat "$TMP/bad.err")], esperado [$CFG:3: $reason]"
  [ ! -s "$TMP/bad.out" ] || fail "$name ($line): stdout no vacío"
  [ ! -e "$HOME/.worktrees" ] || fail "$name ($line): se creó ~/.worktrees"
  ! git -C "$TMP/repo" show-ref --verify --quiet "refs/heads/$b" || fail "$name ($line): quedó la rama"
done <<EOL
SECRETO_X=s3cr3t|unknown key: SECRETO_X
TH_CODEGRAPH=off|unknown key: TH_CODEGRAPH
s3cr3t-sin-igual|expected KEY=value
TH_WORKTREES_ROOT=wt/rel|$ROOT_MSG: wt/rel
TH_WORKTREES_ROOT=~|$ROOT_MSG: ~
TH_WORKTREES_ROOT=~/a/../b|$ROOT_MSG: ~/a/../b
TH_WORKTREES_ROOT=/a//b|$ROOT_MSG: /a//b
TH_WORKTREES_ROOT=/a/./b|$ROOT_MSG: /a/./b
TH_INSTALL_DEPS=2|TH_INSTALL_DEPS must be 0 or 1: 2
EOL
clean_cfg
pass "$name"

name="TH_WORKTREES_ROOT inválida en el entorno: sale con 4 y el error nombra la variable"
rc=0
(cd "$TMP/repo" && TH_WORKTREES_ROOT="rel/wt" "$WT" new feature/env-bad-root 2>"$TMP/envbad.err" >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/envbad.err")]"
[ "$(cat "$TMP/envbad.err")" = "th-wt: TH_WORKTREES_ROOT (environment): $ROOT_MSG: rel/wt" ] || fail "$name: stderr=[$(cat "$TMP/envbad.err")]"
! git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/env-bad-root || fail "$name: quedó la rama"
pass "$name"

name="TH_INSTALL_DEPS inválida en el entorno: sale con 4 y nombra la variable"
rc=0
(cd "$TMP/repo" && TH_INSTALL_DEPS="yes" "$WT" new feature/env-bad-deps 2>"$TMP/envbad.err" >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/envbad.err")]"
[ "$(cat "$TMP/envbad.err")" = "th-wt: TH_INSTALL_DEPS (environment): TH_INSTALL_DEPS must be 0 or 1: yes" ] || fail "$name: stderr=[$(cat "$TMP/envbad.err")]"
! git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/env-bad-deps || fail "$name: quedó la rama"
[ ! -e "$HOME/.worktrees/acme/demo/feature-env-bad-deps" ] || fail "$name: quedó el worktree"
pass "$name"

name="config inválido: close --yes sale con 4 y no borra el worktree ni la rama"
(cd "$TMP/repo" && "$WT" new feature/cfg-close >/dev/null 2>&1) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-cfg-close"
set_cfg 'TH_INSTALL_DEPS=2\n'
rc=0
(cd "$TMP/repo" && "$WT" close feature/cfg-close --yes 2>"$TMP/cl.err" >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/cl.err")]"
grep -qxF "th-wt: $CFG:1: TH_INSTALL_DEPS must be 0 or 1: 2" "$TMP/cl.err" || fail "$name: stderr=[$(cat "$TMP/cl.err")]"
[ -d "$dest" ] || fail "$name: se borró el worktree"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/cfg-close || fail "$name: se borró la rama"
clean_cfg
pass "$name"

name="raíz cuyo ancestro no se puede resolver: new sale con 4 y no crea nada"
if [ "$(id -u)" = 0 ]; then
  pass "$name (omitido: corre como root, chmod 000 no impide cd)"
else
  mkdir -p "$TMP/sin-acceso"
  chmod 000 "$TMP/sin-acceso"
  rc=0
  (cd "$TMP/repo" && TH_WORKTREES_ROOT="$TMP/sin-acceso/wt" "$WT" new feature/cfg-noroot 2>"$TMP/noroot.err" >"$TMP/noroot.out") || rc=$?
  chmod 755 "$TMP/sin-acceso"
  [ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/noroot.err")]"
  grep -qxF "th-wt: cannot resolve the worktrees root: $TMP/sin-acceso/wt" "$TMP/noroot.err" || fail "$name: stderr=[$(cat "$TMP/noroot.err")]"
  [ ! -s "$TMP/noroot.out" ] || fail "$name: stdout no vacío"
  [ ! -e "/acme" ] || fail "$name: se creó /acme en la raíz del sistema"
  [ -z "$(ls -A "$TMP/sin-acceso")" ] || fail "$name: se creó algo bajo la raíz"
  ! git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/cfg-noroot || fail "$name: quedó la rama"
  rmdir "$TMP/sin-acceso"
  pass "$name"
fi

name="raíz dentro del checkout principal: new sale con 4 y no crea nada"
rc=0
(cd "$TMP/repo" && TH_WORKTREES_ROOT="$TMP/repo" "$WT" new feature/cfg-overlap 2>"$TMP/ovl.err" >"$TMP/ovl.out") || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/ovl.err")]"
grep -qxF "th-wt: worktrees root $TMP/repo/acme/demo overlaps the main checkout $TMP/repo" "$TMP/ovl.err" || fail "$name: stderr=[$(cat "$TMP/ovl.err")]"
[ ! -s "$TMP/ovl.out" ] || fail "$name: stdout no vacío"
[ ! -e "$TMP/repo/acme" ] || fail "$name: se creó acme dentro del repo"
! git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/cfg-overlap || fail "$name: quedó la rama"
pass "$name"

name="checkout principal dentro de la raíz del repo: list sale con 4"
git clone -q "$REMOTE_URL" "$TMP/rootov/acme/demo"
rc=0
(cd "$TMP/rootov/acme/demo" && TH_WORKTREES_ROOT="$TMP/rootov" "$WT" list 2>"$TMP/ovl2.err" >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/ovl2.err")]"
grep -qxF "th-wt: worktrees root $TMP/rootov/acme/demo overlaps the main checkout $TMP/rootov/acme/demo" "$TMP/ovl2.err" || fail "$name: stderr=[$(cat "$TMP/ovl2.err")]"
pass "$name"

name="con HOME terminado en /, TH_WORKTREES_ROOT=~/wt funciona"
# shellcheck disable=SC2088 # la tilde literal es lo que se prueba
(cd "$TMP/repo" && HOME="$HOME/" TH_WORKTREES_ROOT='~/wt' "$WT" new feature/cfg-home-slash 2>"$TMP/hs.err") || fail "$name: th-wt new falló: [$(cat "$TMP/hs.err")]"
[ -d "$HOME/wt/acme/demo/feature-cfg-home-slash" ] || fail "$name: no existe el worktree bajo ~/wt"
(cd "$TMP/repo" && HOME="$HOME/" "$WT" new feature/cfg-home-default 2>"$TMP/hs.err") || fail "$name: new con la raíz por defecto falló: [$(cat "$TMP/hs.err")]"
[ -d "$HOME/.worktrees/acme/demo/feature-cfg-home-default" ] || fail "$name: no existe el worktree bajo ~/.worktrees"
clean_cfg
pass "$name"

name="una clave que no parece un nombre de variable no se imprime"
set_cfg 'c2VjcmV0+dG9rZW4/x=\n'
rc=0
(cd "$TMP/repo" && "$WT" new feature/cfg-badkey 2>"$TMP/bk.err" >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/bk.err")]"
! grep -qF "c2VjcmV0" "$TMP/bk.err" || fail "$name: el stderr contiene la clave: [$(cat "$TMP/bk.err")]"
[ "$(cat "$TMP/bk.err")" = "th-wt: $CFG:1: invalid key (not shown)" ] || fail "$name: stderr=[$(cat "$TMP/bk.err")]"
clean_cfg
pass "$name"

name="una clave en minúsculas o mixta no se imprime"
set_cfg 'dG9rZW4tc2VjcmV0==\n'
rc=0
(cd "$TMP/repo" && "$WT" new feature/cfg-lowkey 2>"$TMP/lk.err" >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/lk.err")]"
! grep -qF "dG9rZW4" "$TMP/lk.err" || fail "$name: el stderr contiene la clave: [$(cat "$TMP/lk.err")]"
[ "$(cat "$TMP/lk.err")" = "th-wt: $CFG:1: invalid key (not shown)" ] || fail "$name: stderr=[$(cat "$TMP/lk.err")]"
clean_cfg
pass "$name"

name="raíz bajo un symlink roto: new sale con 4 y no crea nada"
ln -s "$TMP/no-existe" "$TMP/rota"
rc=0
(cd "$TMP/repo" && TH_WORKTREES_ROOT="$TMP/rota/wt" "$WT" new feature/cfg-broken 2>"$TMP/br.err" >"$TMP/br.out") || rc=$?
rm -f "$TMP/rota"
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/br.err")]"
grep -qxF "th-wt: cannot resolve the worktrees root: $TMP/rota/wt" "$TMP/br.err" || fail "$name: stderr=[$(cat "$TMP/br.err")]"
[ ! -e "$TMP/no-existe" ] || fail "$name: se creó el destino del symlink"
! git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/cfg-broken || fail "$name: quedó la rama"
pass "$name"

name="TH_WORKTREES_ROOT del entorno con salto de línea sale con 4"
rc=0
(cd "$TMP/repo" && TH_WORKTREES_ROOT="$TMP/envroot
x" "$WT" new feature/cfg-ctrl 2>"$TMP/ct.err" >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/ct.err")]"
[ "$(cat "$TMP/ct.err")" = "th-wt: TH_WORKTREES_ROOT (environment): TH_WORKTREES_ROOT must not contain control characters" ] || fail "$name: stderr=[$(cat "$TMP/ct.err")]"
! git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/cfg-ctrl || fail "$name: quedó la rama"
pass "$name"
