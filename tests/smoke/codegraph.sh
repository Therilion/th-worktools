#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

# Estos tests sí ejercitan codegraph: lib.sh lo desactiva por defecto.
unset TH_CODEGRAPH

# codegraph falso: anota sus argumentos en $TMP/cg.calls y, en `init`, crea lo mismo que la versión 1.6.2 real.
# FAKE_CG_OUT=1 imprime basura en stdout, FAKE_CG_STDIN=1 anota su stdin en $TMP/cg.stdin, FAKE_CG_FAIL=1 sale con 1.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/codegraph" <<EOF2
#!/usr/bin/env bash
echo "\$*" >> "$TMP/cg.calls"
[ -z "\${FAKE_CG_OUT:-}" ] || echo "junk de codegraph en stdout"
[ -z "\${FAKE_CG_STDIN:-}" ] || echo "stdin=[\$(cat)]" >> "$TMP/cg.stdin"
[ -z "\${FAKE_CG_FAIL:-}" ] || exit 1
if [ "\$1" = init ]; then
  mkdir -p "\$3/.codegraph"
  printf '*\n!.gitignore\n' > "\$3/.codegraph/.gitignore"
  : > "\$3/.codegraph/codegraph.db"
fi
EOF2
chmod +x "$TMP/bin/codegraph"
export PATH="$TMP/bin:$PATH"
: > "$TMP/cg.calls"

# gh falso para pr: devuelve $TMP/gh.json.
cat > "$TMP/bin/gh" <<EOF2
#!/usr/bin/env bash
cat "$TMP/gh.json"
EOF2
chmod +x "$TMP/bin/gh"

# Abre el PR $1 cuyo head es la rama $2 de origin.
gh_pr_from() {
  git -C "$TMP/origin.git" update-ref "refs/pull/$1/head" "refs/heads/$2"
  jq -n --arg o "$(git -C "$TMP/origin.git" rev-parse "refs/pull/$1/head")" --argjson n "$1" '{number: $n, title: "PR de prueba", headRefName: "x", baseRefName: "main", headRefOid: $o}' > "$TMP/gh.json"
}

name="new con codegraph en PATH y TH_CODEGRAPH sin definir ejecuta codegraph init -y en el worktree, sin stdin y con su salida a stderr, y devuelve codegraph: true"
: > "$TMP/cg.calls"
rm -f "$TMP/cg.stdin"
out="$(cd "$TMP/repo" && echo "texto del llamador" | FAKE_CG_OUT=1 FAKE_CG_STDIN=1 "$WT" new feature/cg --json 2>"$TMP/cg.err")" || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-cg"
[ "$(cat "$TMP/cg.calls")" = "init -y $dest" ] || fail "$name: llamadas=[$(cat "$TMP/cg.calls")]"
[ "$(cat "$TMP/cg.stdin")" = "stdin=[]" ] || fail "$name: codegraph leyó [$(cat "$TMP/cg.stdin")]"
{ [ "$(jq -s length <<<"$out")" = 1 ] && [ "$(jq -r .codegraph <<<"$out")" = true ]; } || fail "$name: stdout=[$out]"
grep -q "junk de codegraph en stdout" "$TMP/cg.err" || fail "$name: la salida de codegraph no llegó a stderr: [$(cat "$TMP/cg.err")]"
pass "$name"

name="checkout y pr también indexan con codegraph y devuelven codegraph: true"
: > "$TMP/cg.calls"
git -C "$TMP/repo" branch --no-track local-cg refs/remotes/origin/main
out="$(cd "$TMP/repo" && "$WT" checkout local-cg --json 2>/dev/null)" || fail "$name: th-wt checkout falló"
dest="$HOME/.worktrees/acme/demo/local-cg"
[ "$(cat "$TMP/cg.calls")" = "init -y $dest" ] || fail "$name: checkout: llamadas=[$(cat "$TMP/cg.calls")]"
[ "$(jq -r .codegraph <<<"$out")" = true ] || fail "$name: checkout: salida=[$out]"
: > "$TMP/cg.calls"
git -C "$TMP/repo" branch --no-track review/pr-41 refs/remotes/origin/main
out="$(cd "$TMP/repo" && "$WT" checkout review/pr-41 --json 2>/dev/null)" || fail "$name: th-wt checkout review/pr-41 falló"
dest="$HOME/.worktrees/acme/demo/review-pr-41"
[ "$(cat "$TMP/cg.calls")" = "init -y $dest" ] || fail "$name: review/pr-*: llamadas=[$(cat "$TMP/cg.calls")]"
[ "$(jq -r .codegraph <<<"$out")" = true ] || fail "$name: review/pr-*: salida=[$out]"
: > "$TMP/cg.calls"
gh_pr_from 42 main
out="$(cd "$TMP/repo" && "$WT" pr 42 --json 2>/dev/null)" || fail "$name: th-wt pr falló"
dest="$HOME/.worktrees/acme/demo/pr-reviews/pr-42/code"
[ "$(cat "$TMP/cg.calls")" = "init -y $dest" ] || fail "$name: pr: llamadas=[$(cat "$TMP/cg.calls")]"
{ [ "$(jq -r .codegraph <<<"$out")" = true ] && [ "$(jq -r .pr.number <<<"$out")" = 42 ]; } || fail "$name: pr: salida=[$out]"
pass "$name"

name="sin codegraph en PATH: codegraph: false y ningún aviso de codegraph en stderr"
# PATH mínimo sin codegraph (el del usuario puede tenerlo instalado).
shim="$TMP/bin-sin-codegraph"
mkdir -p "$shim"
for t in bash git jq awk sed; do ln -s "$(command -v "$t")" "$shim/$t"; done
: > "$TMP/cg.calls"
rc=0
out="$(cd "$TMP/repo" && PATH="$shim" "$WT" new feature/cg-none --json 2>"$TMP/none.err")" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$(cat "$TMP/none.err")]"
[ -d "$HOME/.worktrees/acme/demo/feature-cg-none" ] || fail "$name: no se creó el worktree"
[ "$(jq -r .codegraph <<<"$out")" = false ] || fail "$name: salida=[$out]"
! grep -qi codegraph "$TMP/none.err" || fail "$name: stderr=[$(cat "$TMP/none.err")]"
pass "$name"

name="si codegraph init falla, new sale con 0, conserva el worktree, avisa en stderr y devuelve codegraph: false"
: > "$TMP/cg.calls"
rc=0
out="$(cd "$TMP/repo" && FAKE_CG_FAIL=1 "$WT" new feature/cg-fail --json 2>"$TMP/fail.err")" || rc=$?
dest="$HOME/.worktrees/acme/demo/feature-cg-fail"
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0"
[ -s "$TMP/cg.calls" ] || fail "$name: codegraph no se ejecutó"
[ -d "$dest" ] || fail "$name: no se conservó el worktree"
[ "$(jq -r .codegraph <<<"$out")" = false ] || fail "$name: salida=[$out]"
grep -qxF "th-wt: warning: codegraph init failed in $dest; run 'codegraph init -y' there manually" "$TMP/fail.err" || fail "$name: aviso incorrecto: [$(cat "$TMP/fail.err")]"
pass "$name"

name="TH_CODEGRAPH=off en el config o en el entorno: no se llama a codegraph y devuelve codegraph: false; con off en el archivo y auto en el entorno, indexa"
: > "$TMP/cg.calls"
mkdir -p "$HOME/.config/th-worktools"
printf 'TH_CODEGRAPH=off\n' > "$HOME/.config/th-worktools/config"
rc=0
out="$(cd "$TMP/repo" && "$WT" new feature/cg-off-file --json 2>"$TMP/off.err")" || rc=$?
[ "$rc" = 0 ] || fail "$name: config: exit=$rc, esperado 0: [$(cat "$TMP/off.err")]"
[ -d "$HOME/.worktrees/acme/demo/feature-cg-off-file" ] || fail "$name: config: no se creó el worktree"
[ ! -s "$TMP/cg.calls" ] || fail "$name: config: se llamó a codegraph: [$(cat "$TMP/cg.calls")]"
[ "$(jq -r .codegraph <<<"$out")" = false ] || fail "$name: config: salida=[$out]"
! grep -qi codegraph "$TMP/off.err" || fail "$name: config: stderr=[$(cat "$TMP/off.err")]"
out="$(cd "$TMP/repo" && TH_CODEGRAPH=auto "$WT" new feature/cg-env-auto --json 2>/dev/null)" || fail "$name: auto en el entorno: th-wt new falló"
[ "$(cat "$TMP/cg.calls")" = "init -y $HOME/.worktrees/acme/demo/feature-cg-env-auto" ] || fail "$name: auto en el entorno: llamadas=[$(cat "$TMP/cg.calls")]"
[ "$(jq -r .codegraph <<<"$out")" = true ] || fail "$name: auto en el entorno: salida=[$out]"
rm -rf "$HOME/.config"
: > "$TMP/cg.calls"
out="$(cd "$TMP/repo" && TH_CODEGRAPH=off "$WT" new feature/cg-off-env --json 2>/dev/null)" || fail "$name: entorno: th-wt new falló"
[ ! -s "$TMP/cg.calls" ] || fail "$name: entorno: se llamó a codegraph: [$(cat "$TMP/cg.calls")]"
[ "$(jq -r .codegraph <<<"$out")" = false ] || fail "$name: entorno: salida=[$out]"
pass "$name"
