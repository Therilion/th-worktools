#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

git -C "$TMP/repo" remote set-head origin main >/dev/null

CONF_DIR="$TMP/xdg/th-worktools/repos/acme"
CONF="$CONF_DIR/demo.conf"
mkdir -p "$CONF_DIR"
export XDG_CONFIG_HOME="$TMP/xdg"

name="close --yes de una rama mergeada declarada con keep develop borra el worktree, conserva la rama y avisa por qué"
printf 'keep develop\n' > "$CONF"
(cd "$TMP/repo" && "$WT" new develop >/dev/null 2>&1) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/develop"
rc=0
err="$(cd "$TMP/repo" && "$WT" close develop --yes 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$err]"
[ ! -e "$dest" ] || fail "$name: sigue el directorio"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/develop || fail "$name: se borró la rama develop"
printf '%s\n' "$err" | grep -qxF "th-wt: branch develop kept: it is a long-lived branch (keep develop)" || fail "$name: falta el aviso exacto: [$err]"
pass "$name"

name="close sin --yes de una rama keep: el plan dice branch kept y --json trae delete: {worktree: true, branch: false}"
printf 'keep develop\n' > "$CONF"
(cd "$TMP/repo" && "$WT" checkout develop >/dev/null 2>&1) || fail "$name: th-wt checkout develop falló"
dest="$HOME/.worktrees/acme/demo/develop"
err="$(cd "$TMP/repo" && "$WT" close develop 2>&1)" || fail "$name: th-wt close falló: [$err]"
printf '%s\n' "$err" | grep -qF "  delete:    worktree only (branch kept: it is a long-lived branch (keep develop))" || fail "$name: plan inesperado: [$err]"
out="$(cd "$TMP/repo" && "$WT" close develop --json 2>/dev/null)" || fail "$name: th-wt close --json falló"
[ "$(printf '%s' "$out" | jq -c .delete)" = '{"worktree":true,"branch":false}' ] || fail "$name: delete=[$out]"
[ -d "$dest" ] || fail "$name: se borró el directorio en el dry-run"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/develop || fail "$name: se borró la rama en el dry-run"
pass "$name"

name="con keep release/*, close --yes conserva release/1.0 y release/1.0/fix y borra feature/a mergeada"
printf 'keep release/*\n' > "$CONF"
(cd "$TMP/repo" && "$WT" new release/1.0 >/dev/null 2>&1) || fail "$name: new release/1.0 falló"
dest="$HOME/.worktrees/acme/demo/release-1.0"
rc=0
err="$(cd "$TMP/repo" && "$WT" close release/1.0 --yes 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: (release/1.0) exit=$rc, esperado 0: [$err]"
[ ! -e "$dest" ] || fail "$name: (release/1.0) sigue el directorio"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/release/1.0 || fail "$name: se borró release/1.0"
printf '%s\n' "$err" | grep -qxF "th-wt: branch release/1.0 kept: it is a long-lived branch (keep release/*)" || fail "$name: (release/1.0) aviso inesperado: [$err]"
git -C "$TMP/repo" branch -q -D release/1.0

(cd "$TMP/repo" && "$WT" new release/1.0/fix >/dev/null 2>&1) || fail "$name: new release/1.0/fix falló"
dest="$HOME/.worktrees/acme/demo/release-1.0-fix"
rc=0
err="$(cd "$TMP/repo" && "$WT" close release/1.0/fix --yes 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: (release/1.0/fix) exit=$rc, esperado 0: [$err]"
[ ! -e "$dest" ] || fail "$name: (release/1.0/fix) sigue el directorio"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/release/1.0/fix || fail "$name: se borró release/1.0/fix"
printf '%s\n' "$err" | grep -qxF "th-wt: branch release/1.0/fix kept: it is a long-lived branch (keep release/*)" || fail "$name: (release/1.0/fix) aviso inesperado: [$err]"

(cd "$TMP/repo" && "$WT" new feature/a >/dev/null 2>&1) || fail "$name: new feature/a falló"
dest="$HOME/.worktrees/acme/demo/feature-a"
rc=0
err="$(cd "$TMP/repo" && "$WT" close feature/a --yes 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: (feature/a) exit=$rc, esperado 0: [$err]"
[ ! -e "$dest" ] || fail "$name: (feature/a) sigue el directorio"
! git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/a || fail "$name: no se borró feature/a"
pass "$name"

name="close con una línea keep inválida (sin valor, dos palabras, nombre inválido, dos *) sale con 4 con la línea y el motivo, sin borrar nada"
rm -f "$CONF"
(cd "$TMP/repo" && "$WT" new feature/inv >/dev/null 2>&1) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-inv"
i=0
while IFS='|' read -r line_no content reason; do
  i=$((i + 1))
  printf '%b' "$content" > "$CONF"
  rc=0
  (cd "$TMP/repo" && "$WT" close feature/inv --yes 2>"$TMP/inv-$i.err" >"$TMP/inv-$i.out") || rc=$?
  [ "$rc" = 4 ] || fail "$name (caso $i): exit=$rc, esperado 4: [$(cat "$TMP/inv-$i.err")]"
  grep -qxF "th-wt: $CONF:$line_no: $reason" "$TMP/inv-$i.err" || fail "$name (caso $i): stderr=[$(cat "$TMP/inv-$i.err")], esperado línea $line_no: $reason"
  [ ! -s "$TMP/inv-$i.out" ] || fail "$name (caso $i): stdout no vacío: [$(cat "$TMP/inv-$i.out")]"
  [ -d "$dest" ] || fail "$name (caso $i): se borró el directorio"
  git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/inv || fail "$name (caso $i): se borró la rama"
done <<'EOL'
1|keep\n|expected 'keep <branch>'
2|# comentario\nkeep a b\n|expected 'keep <branch>'
1|keep bad..name\n|keep must be a branch name or a pattern with a single '*': bad..name
1|keep a/*/*\n|keep must be a branch name or a pattern with a single '*': a/*/*
EOL
pass "$name"

name="new con un .conf con keep y link crea el worktree y enlaza (keep no es acción desconocida)"
printf '%s\n' .env > "$TMP/repo/.gitignore"
git -C "$TMP/repo" add .gitignore
git -C "$TMP/repo" commit -q -m "gitignore"
git -C "$TMP/repo" push -q origin main
echo "SECRETO=1" > "$TMP/repo/.env"
printf 'keep develop\nkeep release/*\nlink .env\n' > "$CONF"
out="$(cd "$TMP/repo" && "$WT" new feature/with-keep --json 2>"$TMP/wk.err")" || fail "$name: th-wt new falló: [$(cat "$TMP/wk.err")]"
dest="$HOME/.worktrees/acme/demo/feature-with-keep"
[ -L "$dest/.env" ] || fail "$name: .env no es symlink"
[ "$(readlink "$dest/.env")" = "$TMP/repo/.env" ] || fail "$name: .env apunta a [$(readlink "$dest/.env")]"
[ "$(jq -c .linked <<<"$out")" = '[".env"]' ] || fail "$name: salida=[$out]"
pass "$name"
