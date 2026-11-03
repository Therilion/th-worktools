#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

# gh falso: devuelve $TMP/gh.json y anota cada llamada en $TMP/gh.calls.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/gh.calls"
cat "$TMP/gh.json"
EOF
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

# Crea un commit hijo de main directamente en origin (sin tocar las refs remotas del clon) y lo apunta con $2.
origin_commit() { git -C "$TMP/origin.git" update-ref "$2" "$(git -C "$TMP/origin.git" commit-tree -p "$1" -m "$3" "$1^{tree}")"; }

name="pr <n> abre un PR del repo en pr-reviews/pr-<n>/code, en review/pr-<n> sin upstream, y actualiza origin/<base>"
origin_commit main refs/pull/7/head "trabajo del PR"
pr_oid="$(git -C "$TMP/origin.git" rev-parse refs/pull/7/head)"
origin_commit main refs/heads/main "main avanzó"
main_oid="$(git -C "$TMP/origin.git" rev-parse main)"
echo '{"number":7,"title":"Arreglar el login","headRefName":"fix/login","baseRefName":"main"}' > "$TMP/gh.json"
heads_before="$(git -C "$TMP/repo" for-each-ref refs/heads)"
head_before="$(git -C "$TMP/repo" rev-parse HEAD)"
out="$(cd "$TMP/repo" && "$WT" pr 7 --json 2>/dev/null)" || fail "$name: th-wt pr falló"
dest="$HOME/.worktrees/acme/demo/pr-reviews/pr-7/code"
expected="{\"path\":\"$dest\",\"branch\":\"review/pr-7\",\"repo\":\"acme/demo\",\"pr\":{\"number\":7,\"title\":\"Arreglar el login\",\"head\":\"fix/login\",\"base\":\"main\"}}"
[ "$(printf '%s' "$out" | jq -S -c .)" = "$(printf '%s' "$expected" | jq -S -c .)" ] || fail "$name: salida=[$out]"
[ "$(git -C "$dest" rev-parse HEAD)" = "$pr_oid" ] || fail "$name: el worktree no está en el último commit del PR"
[ "$(git -C "$dest" symbolic-ref --short HEAD)" = review/pr-7 ] || fail "$name: rama incorrecta"
[ -z "$(git -C "$TMP/repo" config --get-regexp '^branch\.review/pr-7\.' || true)" ] || fail "$name: la rama tiene upstream"
[ "$(git -C "$TMP/repo" rev-parse refs/remotes/origin/main)" = "$main_oid" ] || fail "$name: origin/main no se actualizó"
[ "$(git -C "$TMP/repo" for-each-ref refs/heads | grep -v 'refs/heads/review/pr-7$')" = "$heads_before" ] || fail "$name: cambiaron otras ramas"
[ "$(git -C "$TMP/repo" rev-parse HEAD)" = "$head_before" ] || fail "$name: cambió el checkout principal"
pass "$name"

name="pr <n> abre un PR de un fork (su commit no está en ninguna rama de origin) sin escribir refs del PR"
origin_commit main refs/pull/8/head "trabajo desde un fork"
fork_oid="$(git -C "$TMP/origin.git" rev-parse refs/pull/8/head)"
[ -z "$(git -C "$TMP/origin.git" branch --contains "$fork_oid")" ] || fail "$name: el commit del fork está en una rama de origin"
echo '{"number":8,"title":"Desde un fork","headRefName":"patch-1","baseRefName":"main"}' > "$TMP/gh.json"
refs_before="$(git -C "$TMP/repo" for-each-ref --format='%(refname)')"
(cd "$TMP/repo" && "$WT" pr 8) || fail "$name: th-wt pr falló"
dest="$HOME/.worktrees/acme/demo/pr-reviews/pr-8/code"
[ "$(git -C "$dest" rev-parse HEAD)" = "$fork_oid" ] || fail "$name: el worktree no está en el último commit del PR"
[ "$(git -C "$TMP/repo" for-each-ref --format='%(refname)' | grep -vx 'refs/heads/review/pr-8')" = "$refs_before" ] || fail "$name: se escribieron otras refs"
pass "$name"

name="pr <n> sin --json informa ruta, título, rama del PR y base por stderr"
origin_commit main refs/pull/9/head "trabajo del PR 9"
echo '{"number":9,"title":"Añadir exportación","headRefName":"feat/export","baseRefName":"main"}' > "$TMP/gh.json"
out="$(cd "$TMP/repo" && "$WT" pr 9 2>"$TMP/pr9.err")" || fail "$name: th-wt pr falló"
[ -z "$out" ] || fail "$name: escribió a stdout: [$out]"
err="$(cat "$TMP/pr9.err")"
for want in "$HOME/.worktrees/acme/demo/pr-reviews/pr-9/code" "Añadir exportación" "feat/export" "main"; do
  case "$err" in *"$want"*) ;; *) fail "$name: stderr no incluye [$want]: [$err]" ;; esac
done
pass "$name"
