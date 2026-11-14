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

name="close --yes de una rama keep no contenida en origin/main borra el worktree y la conserva con el motivo keep"
printf 'keep develop\n' > "$CONF"
dest="$HOME/.worktrees/acme/demo/develop"
if [ ! -d "$dest" ]; then
  (cd "$TMP/repo" && "$WT" checkout develop >/dev/null 2>&1) || fail "$name: th-wt checkout develop falló"
fi
echo "dev" > "$dest/dev.txt"
git -C "$dest" add dev.txt
git -C "$dest" commit -q -m "commit en develop"
git -C "$dest" push -q origin HEAD:develop
rc=0
(cd "$TMP/repo" && "$WT" close develop --yes 2>"$TMP/knc.err" >"$TMP/knc.out") || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$(cat "$TMP/knc.err")]"
[ ! -s "$TMP/knc.out" ] || fail "$name: stdout no vacío: [$(cat "$TMP/knc.out")]"
[ ! -e "$dest" ] || fail "$name: sigue el directorio"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/develop || fail "$name: se borró la rama develop"
grep -qxF "th-wt: branch develop kept: it is a long-lived branch (keep develop)" "$TMP/knc.err" || fail "$name: falta el aviso exacto: [$(cat "$TMP/knc.err")]"
pass "$name"

name="close --yes --force de una rama keep con cambios sin commitear borra el worktree y conserva la rama"
printf 'keep develop\n' > "$CONF"
(cd "$TMP/repo" && "$WT" checkout develop >/dev/null 2>&1) || fail "$name: th-wt checkout develop falló"
dest="$HOME/.worktrees/acme/demo/develop"
echo "dirty" > "$dest/sucio.txt"
rc=0
(cd "$TMP/repo" && "$WT" close develop --yes --force 2>"$TMP/kf.err" >"$TMP/kf.out") || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$(cat "$TMP/kf.err")]"
[ ! -s "$TMP/kf.out" ] || fail "$name: stdout no vacío: [$(cat "$TMP/kf.out")]"
[ ! -e "$dest" ] || fail "$name: sigue el directorio"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/develop || fail "$name: se borró la rama develop"
grep -qxF "th-wt: branch develop kept: it is a long-lived branch (keep develop)" "$TMP/kf.err" || fail "$name: falta el aviso exacto: [$(cat "$TMP/kf.err")]"
pass "$name"

name="close --remote con una línea keep inválida sale con 4 y la línea del .conf sin consultar origin"
rm -f "$CONF"
(cd "$TMP/repo" && "$WT" checkout develop >/dev/null 2>&1) || fail "$name: th-wt checkout develop falló"
dest="$HOME/.worktrees/acme/demo/develop"
printf 'keep bad..name\n' > "$CONF"
mv "$TMP/origin.git" "$TMP/origin.off"
rc=0
(cd "$TMP/repo" && "$WT" close develop --remote 2>"$TMP/kr.err" >"$TMP/kr.out") || rc=$?
mv "$TMP/origin.off" "$TMP/origin.git"
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/kr.err")]"
grep -qxF "th-wt: $CONF:1: keep must be a branch name or a pattern with a single '*': bad..name" "$TMP/kr.err" || fail "$name: stderr=[$(cat "$TMP/kr.err")]"
[ ! -s "$TMP/kr.out" ] || fail "$name: stdout no vacío: [$(cat "$TMP/kr.out")]"
[ -d "$dest" ] || fail "$name: se borró el directorio"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/develop || fail "$name: se borró la rama develop"
pass "$name"

# gh falso: devuelve $TMP/gh.json (solo lo usa `pr`; close no consulta GitHub).
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<EOF2
#!/usr/bin/env bash
cat "$TMP/gh.json"
EOF2
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

# Abre el PR $1 (un commit hijo de main solo en refs/pull/$1/head) y deja un report.md al lado del código.
open_pr() {
  git -C "$TMP/origin.git" update-ref "refs/pull/$1/head" "$(git -C "$TMP/origin.git" commit-tree -p main -m "trabajo del PR $1" "main^{tree}")"
  jq -n --arg o "$(git -C "$TMP/origin.git" rev-parse "refs/pull/$1/head")" --argjson n "$1" '{number: $n, title: "PR \($n)", headRefName: "feat/x\($n)", baseRefName: "main", headRefOid: $o}' > "$TMP/gh.json"
  (cd "$TMP/repo" && "$WT" pr "$1" 2>/dev/null) || fail "th-wt pr $1 falló"
  echo "notas" > "$HOME/.worktrees/acme/demo/pr-reviews/pr-$1/report.md"
}

name="con keep review/*, close review/pr-<n> --yes borra igual la rama del PR"
printf 'keep review/*\n' > "$CONF"
open_pr 7
dest="$HOME/.worktrees/acme/demo/pr-reviews/pr-7/code"
rc=0
(cd "$TMP/repo" && "$WT" close review/pr-7 --yes 2>"$TMP/kpr.err" >"$TMP/kpr.out") || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$(cat "$TMP/kpr.err")]"
[ ! -s "$TMP/kpr.out" ] || fail "$name: stdout no vacío: [$(cat "$TMP/kpr.out")]"
[ ! -e "$dest" ] || fail "$name: sigue el directorio $dest"
! git -C "$TMP/repo" show-ref --verify --quiet refs/heads/review/pr-7 || fail "$name: sigue la rama review/pr-7"
pass "$name"

name="close con un link cuya ruta ya no existe en el checkout principal sale con 4 sin borrar nada"
printf 'link .env\n' > "$CONF"
(cd "$TMP/repo" && "$WT" new feature/missing-link >/dev/null 2>&1) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-missing-link"
rm "$TMP/repo/.env"
rc=0
(cd "$TMP/repo" && "$WT" close feature/missing-link --yes 2>"$TMP/ml.err" >"$TMP/ml.out") || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/ml.err")]"
[ "$(cat "$TMP/ml.err")" = "th-wt: $CONF:1: .env does not exist in the main checkout ($TMP/repo)" ] || fail "$name: stderr=[$(cat "$TMP/ml.err")]"
[ ! -s "$TMP/ml.out" ] || fail "$name: stdout no vacío: [$(cat "$TMP/ml.out")]"
[ -d "$dest" ] || fail "$name: se borró el directorio"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/missing-link || fail "$name: se borró la rama"
echo "SECRETO=1" > "$TMP/repo/.env"
pass "$name"
