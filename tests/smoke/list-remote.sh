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
echo '[]' > "$TMP/gh.json"
git -C "$TMP/repo" remote set-head origin main >/dev/null

name="list --remote muestra número y estado de un PR mergeado con squash"
(cd "$TMP/repo" && "$WT" new feature/squash) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-squash"
git -C "$dest" commit -q --allow-empty -m "trabajo del PR"
head="$(git -C "$dest" rev-parse HEAD)"
git -C "$TMP/repo" pull -q --ff-only origin main
git -C "$TMP/repo" merge -q --squash feature/squash >/dev/null
git -C "$TMP/repo" commit -q --allow-empty -m "feature/squash (#12)"
git -C "$TMP/repo" push -q origin main
jq -n --arg oid "$head" '[{number: 12, state: "MERGED", baseRefName: "main", headRefName: "feature/squash", headRefOid: $oid}]' > "$TMP/gh.json"
out="$(cd "$TMP/repo" && "$WT" list --remote 2>&1)" || fail "$name: th-wt list --remote falló: [$out]"
line="$(printf '%s\n' "$out" | grep -F "feature/squash")" || fail "$name: no aparece la rama: [$out]"
case "$line" in *"PR #12 MERGED (base main)"*) ;; *) fail "$name: la línea no dice PR #12 MERGED (base main): [$line]" ;; esac
case "$line" in *"local commits after it"*) fail "$name: la línea dice local commits after it: [$line]" ;; esac
out="$(cd "$TMP/repo" && "$WT" list --remote --json 2>/dev/null)" || fail "$name: th-wt list --remote --json falló"
entry="$(printf '%s' "$out" | jq -S -c '.worktrees[] | select(.branch == "feature/squash") | {merged, pr}')"
[ "$entry" = '{"merged":false,"pr":{"ahead":false,"base":"main","number":12,"state":"MERGED"}}' ] || fail "$name: entrada=[$entry]"
pass "$name"

name="list --remote marca ahead un PR mergeado si la rama local tiene commits posteriores a su último commit"
(cd "$TMP/repo" && "$WT" new feature/after-pr) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-after-pr"
git -C "$dest" commit -q --allow-empty -m "trabajo del PR"
head="$(git -C "$dest" rev-parse HEAD)"
git -C "$dest" commit -q --allow-empty -m "trabajo posterior al PR"
jq -n --arg oid "$head" '[{number: 15, state: "MERGED", baseRefName: "main", headRefName: "feature/after-pr", headRefOid: $oid}]' > "$TMP/gh.json"
out="$(cd "$TMP/repo" && "$WT" list --remote --json 2>/dev/null)" || fail "$name: th-wt list --remote --json falló"
entry="$(printf '%s' "$out" | jq -S -c '.worktrees[] | select(.branch == "feature/after-pr") | .pr')"
[ "$entry" = '{"ahead":true,"base":"main","number":15,"state":"MERGED"}' ] || fail "$name: pr=[$entry]"
out="$(cd "$TMP/repo" && "$WT" list --remote 2>&1)" || fail "$name: th-wt list --remote falló: [$out]"
line="$(printf '%s\n' "$out" | grep -F "feature/after-pr")" || fail "$name: no aparece la rama: [$out]"
case "$line" in *"PR #15 MERGED (base main), local commits after it"*) ;; *) fail "$name: la línea no dice local commits after it: [$line]" ;; esac
pass "$name"

name="list --remote marca ahead desconocido (null) si el último commit del PR no existe en local"
(cd "$TMP/repo" && "$WT" new feature/unfetched-pr) || fail "$name: th-wt new falló"
git -C "$HOME/.worktrees/acme/demo/feature-unfetched-pr" commit -q --allow-empty -m "trabajo del PR"
jq -n '[{number: 16, state: "MERGED", baseRefName: "main", headRefName: "feature/unfetched-pr", headRefOid: "0123456789abcdef0123456789abcdef01234567"}]' > "$TMP/gh.json"
rc=0
out="$(cd "$TMP/repo" && "$WT" list --remote --json 2>"$TMP/unfetched.err")" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
entry="$(printf '%s' "$out" | jq -S -c '.worktrees[] | select(.branch == "feature/unfetched-pr") | .pr')"
[ "$entry" = '{"ahead":null,"base":"main","number":16,"state":"MERGED"}' ] || fail "$name: pr=[$entry]"
[ ! -s "$TMP/unfetched.err" ] || fail "$name: escribió a stderr: [$(cat "$TMP/unfetched.err")]"
out="$(cd "$TMP/repo" && "$WT" list --remote 2>&1)" || fail "$name: th-wt list --remote falló: [$out]"
line="$(printf '%s\n' "$out" | grep -F "feature/unfetched-pr")" || fail "$name: no aparece la rama: [$out]"
case "$line" in *"PR #16 MERGED (base main), PR head not fetched"*) ;; *) fail "$name: la línea no dice PR head not fetched: [$line]" ;; esac
pass "$name"

name="list --remote usa el PR más reciente cuando la rama tiene varios, sin importar el orden de gh"
(cd "$TMP/repo" && "$WT" new feature/many-prs) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-many-prs"
git -C "$dest" commit -q --allow-empty -m "trabajo con dos PRs"
head="$(git -C "$dest" rev-parse HEAD)"
jq -n --arg oid "$head" '[
  {number: 3, state: "MERGED", baseRefName: "main", headRefName: "feature/many-prs", headRefOid: $oid},
  {number: 7, state: "OPEN", baseRefName: "main", headRefName: "feature/many-prs", headRefOid: $oid},
  {number: 5, state: "CLOSED", baseRefName: "main", headRefName: "feature/many-prs", headRefOid: $oid}
]' > "$TMP/gh.json"
out="$(cd "$TMP/repo" && "$WT" list --remote --json 2>/dev/null)" || fail "$name: th-wt list --remote --json falló"
entry="$(printf '%s' "$out" | jq -S -c '.worktrees[] | select(.branch == "feature/many-prs") | .pr')"
[ "$entry" = '{"ahead":false,"base":"main","number":7,"state":"OPEN"}' ] || fail "$name: pr=[$entry]"
pass "$name"

name="list --remote deja pr en null si la rama no tiene PR, y no cruza PR para ramas ya contenidas"
(cd "$TMP/repo" && "$WT" new feature/contained-pr) || fail "$name: th-wt new falló"
(cd "$TMP/repo" && "$WT" new feature/no-pr) || fail "$name: th-wt new falló"
git -C "$HOME/.worktrees/acme/demo/feature-no-pr" commit -q --allow-empty -m "trabajo sin PR"
head="$(git -C "$HOME/.worktrees/acme/demo/feature-contained-pr" rev-parse HEAD)"
jq -n --arg oid "$head" '[{number: 20, state: "MERGED", baseRefName: "main", headRefName: "feature/contained-pr", headRefOid: $oid}]' > "$TMP/gh.json"
out="$(cd "$TMP/repo" && "$WT" list --remote --json 2>/dev/null)" || fail "$name: th-wt list --remote --json falló"
for b in feature/contained-pr feature/no-pr; do
  entry="$(printf '%s' "$out" | jq -c --arg b "$b" '.worktrees[] | select(.branch == $b) | .pr')"
  [ "$entry" = null ] || fail "$name: $b: pr=[$entry], esperado null"
done
out="$(cd "$TMP/repo" && "$WT" list --remote 2>&1)" || fail "$name: th-wt list --remote falló: [$out]"
for b in feature/contained-pr feature/no-pr; do
  line="$(printf '%s\n' "$out" | grep -F "$b")" || fail "$name: no aparece $b: [$out]"
  case "$line" in *"PR #"*) fail "$name: $b: la línea muestra un PR: [$line]" ;; esac
done
pass "$name"

name="list --remote refleja un avance de origin/main que el clon no tenía; list sin --remote no"
(cd "$TMP/repo" && "$WT" new feature/stale) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-stale"
git -C "$dest" commit -q --allow-empty -m "trabajo integrado desde otro clon"
# Push por ruta (no por el remote): origin avanza sin que se actualice refs/remotes/origin/main local.
git -C "$dest" push -q "$TMP/origin.git" HEAD:main
echo '[]' > "$TMP/gh.json"
out="$(cd "$TMP/repo" && "$WT" list 2>&1)" || fail "$name: th-wt list falló: [$out]"
line="$(printf '%s\n' "$out" | grep -F "feature/stale")" || fail "$name: no aparece la rama: [$out]"
case "$line" in *"not contained in origin/main"*) ;; *) fail "$name: sin --remote debería decir not contained (datos locales): [$line]" ;; esac
out="$(cd "$TMP/repo" && "$WT" list --remote 2>&1)" || fail "$name: th-wt list --remote falló: [$out]"
line="$(printf '%s\n' "$out" | grep -F "feature/stale")" || fail "$name: no aparece la rama: [$out]"
case "$line" in *"not contained"*) fail "$name: con --remote dice not contained: [$line]" ;; esac
case "$line" in *"contained in origin/main"*) ;; *) fail "$name: con --remote no dice contained in origin/main: [$line]" ;; esac
pass "$name"

name="list --remote repara un origin/HEAD ausente: merged deja de ser desconocido"
git -C "$TMP/repo" remote set-head origin -d >/dev/null
git -C "$TMP/repo" symbolic-ref -q refs/remotes/origin/HEAD >/dev/null && fail "$name: origin/HEAD debería estar ausente antes de la prueba"
out="$(cd "$TMP/repo" && "$WT" list --json 2>/dev/null)" || fail "$name: th-wt list --json falló"
[ "$(printf '%s' "$out" | jq -c '.worktrees[] | select(.branch == "feature/stale") | .merged')" = null ] || fail "$name: sin --remote merged debería ser null: [$out]"
out="$(cd "$TMP/repo" && "$WT" list --remote --json 2>/dev/null)" || fail "$name: th-wt list --remote --json falló"
[ "$(printf '%s' "$out" | jq -c '.worktrees[] | select(.branch == "feature/stale") | .merged')" = true ] || fail "$name: con --remote merged debería ser true: [$out]"
[ "$(git -C "$TMP/repo" symbolic-ref --short refs/remotes/origin/HEAD)" = origin/main ] || fail "$name: origin/HEAD no quedó apuntando a origin/main"
pass "$name"
