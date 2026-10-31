#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

# gh falso: devuelve $TMP/gh.json y anota cada llamada en $TMP/gh.calls.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<EOF2
#!/usr/bin/env bash
echo "\$*" >> "$TMP/gh.calls"
cat "$TMP/gh.json"
EOF2
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
echo '[]' > "$TMP/gh.json"
git -C "$TMP/repo" remote set-head origin main >/dev/null

# new_branch <rama>: worktree con un commit propio; deja en $dest su ruta y en $head su último commit.
new_branch() {
  (cd "$TMP/repo" && "$WT" new "$1") || fail "$name: th-wt new $1 falló"
  dest="$HOME/.worktrees/acme/demo/${1//\//-}"
  git -C "$dest" commit -q --allow-empty -m "trabajo de $1"
  head="$(git -C "$dest" rev-parse HEAD)"
}
# pr_json <rama> <número> <estado> <base> <oid>
pr_json() {
  jq -n --arg b "$1" --argjson n "$2" --arg s "$3" --arg base "$4" --arg oid "$5" \
    '[{number: $n, state: $s, baseRefName: $base, headRefName: $b, headRefOid: $oid, isCrossRepository: false}]' > "$TMP/gh.json"
}
branch_exists() { git -C "$TMP/repo" show-ref --verify --quiet "refs/heads/$1"; }
# still_there <rama>: siguen el worktree (en $dest) y la rama.
still_there() { [ -d "$dest" ] && branch_exists "$1"; }

name="close --remote de un PR mergeado con squash muestra el PR y borra worktree y rama sin --force"
new_branch feature/squash
pr_json feature/squash 12 MERGED main "$head"
git -C "$TMP/repo" pull -q --ff-only origin main
git -C "$TMP/repo" merge -q --squash feature/squash >/dev/null
git -C "$TMP/repo" commit -q --allow-empty -m "feature/squash (#12)"
git -C "$TMP/repo" push -q origin main
rm -f "$TMP/gh.calls"
out="$(cd "$TMP/repo" && "$WT" close feature/squash --remote 2>&1)" || fail "$name: dry-run falló: [$out]"
for pat in "pr: +#12 MERGED \(base main\)" "unpushed: +1 commits \(all in the PR\)" "delete: +worktree and branch"; do
  printf '%s\n' "$out" | grep -qE "$pat" || fail "$name: falta [$pat]: [$out]"
done
grep -qF -- "--head feature/squash" "$TMP/gh.calls" || fail "$name: gh no recibió --head: [$(cat "$TMP/gh.calls")]"
still_there feature/squash || fail "$name: el dry-run borró algo"
plan="$(cd "$TMP/repo" && "$WT" close feature/squash --remote --json 2>/dev/null)" || fail "$name: --json falló"
[ "$(printf '%s' "$plan" | jq -S -c '{pr, delete, unpushed}')" = '{"delete":{"branch":true,"worktree":true},"pr":{"ahead":false,"base":"main","number":12,"state":"MERGED"},"unpushed":1}' ] || fail "$name: plan=[$plan]"
(cd "$TMP/repo" && "$WT" close feature/squash --remote --yes >/dev/null 2>&1) || fail "$name: --yes falló"
[ ! -e "$dest" ] || fail "$name: sigue el directorio"
branch_exists feature/squash && fail "$name: sigue la rama"
pass "$name"

name="close --remote de un PR mergeado en una base que no es la por defecto cierra y muestra la base"
new_branch feature/other-base
pr_json feature/other-base 30 MERGED release/1.0 "$head"
out="$(cd "$TMP/repo" && "$WT" close feature/other-base --remote 2>&1)" || fail "$name: dry-run falló: [$out]"
printf '%s\n' "$out" | grep -qE "pr: +#30 MERGED \(base release/1.0, not the default branch\)" || fail "$name: falta la base: [$out]"
printf '%s\n' "$out" | grep -qE "delete: +worktree and branch" || fail "$name: no borra ambos: [$out]"
(cd "$TMP/repo" && "$WT" close feature/other-base --remote --yes >/dev/null 2>&1) || fail "$name: --yes falló"
[ ! -e "$dest" ] || fail "$name: sigue el directorio"
branch_exists feature/other-base && fail "$name: sigue la rama"
pass "$name"

name="close --remote con commits posteriores al PR, PR abierto o PR cerrado bloquea como close sin --remote"
new_branch feature/after-pr
git -C "$dest" commit -q --allow-empty -m "trabajo posterior"
pr_json feature/after-pr 15 MERGED main "$head"
for b in after-pr open-pr closed-pr; do
  if [ "$b" != after-pr ]; then
    new_branch "feature/$b"
    state=OPEN
    [ "$b" = open-pr ] || state=CLOSED
    pr_json "feature/$b" 16 "$state" main "$head"
  fi
  dest="$HOME/.worktrees/acme/demo/feature-$b"
  rc=0
  out="$(cd "$TMP/repo" && "$WT" close "feature/$b" --remote --yes 2>&1)" || rc=$?
  [ "$rc" = 4 ] || fail "$name: $b: exit=$rc, esperado 4: [$out]"
  printf '%s\n' "$out" | grep -qF "unpushed commit(s)" || fail "$name: $b: el plan no dice por qué: [$out]"
  still_there "feature/$b" || fail "$name: $b: se borró algo"
done
out="$(cd "$TMP/repo" && "$WT" close feature/closed-pr --remote 2>&1)" || fail "$name: dry-run falló: [$out]"
printf '%s\n' "$out" | grep -qE "pr: +#16 CLOSED" || fail "$name: no muestra el PR: [$out]"
pr_json feature/after-pr 15 MERGED main "$(git -C "$HOME/.worktrees/acme/demo/feature-after-pr" rev-parse HEAD~1)"
out="$(cd "$TMP/repo" && "$WT" close feature/after-pr --remote 2>&1)" || fail "$name: dry-run falló"
printf '%s\n' "$out" | grep -qF "local commits after it" || fail "$name: after-pr: no dice que hay commits posteriores: [$out]"
git -C "$HOME/.worktrees/acme/demo/feature-after-pr" push -q origin HEAD:refs/heads/feature/after-pr
out="$(cd "$TMP/repo" && "$WT" close feature/after-pr --remote 2>&1)" || fail "$name: after-pr pusheada: dry-run falló"
printf '%s\n' "$out" | grep -qF "branch kept: not contained in origin/main and it has local commits after its merged PR #15" || fail "$name: after-pr: el motivo no cita el PR mergeado: [$out]"
pass "$name"

name="close --remote con cambios sin commitear en un PR mergeado bloquea sin --force"
new_branch feature/dirty
pr_json feature/dirty 17 MERGED main "$head"
echo x > "$dest/nuevo.txt"
rc=0
out="$(cd "$TMP/repo" && "$WT" close feature/dirty --remote --yes 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$out]"
printf '%s\n' "$out" | grep -qF "uncommitted changes" || fail "$name: no dice por qué: [$out]"
still_there feature/dirty || fail "$name: se borró algo"
pass "$name"

name="close --remote sin PR y sin commits sin push cierra el worktree y conserva la rama, diciendo por qué"
new_branch feature/no-pr
git -C "$dest" push -q origin feature/no-pr
echo '[]' > "$TMP/gh.json"
out="$(cd "$TMP/repo" && "$WT" close feature/no-pr --remote 2>&1)" || fail "$name: dry-run falló: [$out]"
printf '%s\n' "$out" | grep -qE "pr: +none" || fail "$name: no dice que no hay PR: [$out]"
printf '%s\n' "$out" | grep -qF "branch kept: not contained in origin/main and it has no PR" || fail "$name: no dice por qué se conserva: [$out]"
(cd "$TMP/repo" && "$WT" close feature/no-pr --remote --yes >/dev/null 2>&1) || fail "$name: --yes falló"
[ ! -e "$dest" ] || fail "$name: sigue el directorio"
branch_exists feature/no-pr || fail "$name: se borró la rama"
pass "$name"

name="close --remote sin gh → exit 3, con origin inaccesible o gh fallando → exit 4; no se borra nada y close sin --remote sigue funcionando"
new_branch feature/errs
pr_json feature/errs 18 MERGED main "$head"
mkdir -p "$TMP/nogh"
for tool in env bash git jq sed awk cat; do ln -sf "$(command -v "$tool")" "$TMP/nogh/$tool"; done
rc=0
err="$(cd "$TMP/repo" && PATH="$TMP/nogh" "$WT" close feature/errs --remote --yes 2>&1)" || rc=$?
[ "$rc" = 3 ] || fail "$name: sin gh: exit=$rc, esperado 3: [$err]"
case "$err" in *"th-wt: missing dependency: gh"*) ;; *) fail "$name: sin gh: mensaje inesperado: [$err]" ;; esac
mkdir -p "$TMP/badgh"
printf '#!/usr/bin/env bash\necho "gh: HTTP 401: Bad credentials" >&2\nexit 1\n' > "$TMP/badgh/gh"
chmod +x "$TMP/badgh/gh"
rc=0
err="$(cd "$TMP/repo" && PATH="$TMP/badgh:$PATH" "$WT" close feature/errs --remote --yes 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: gh fallando: exit=$rc, esperado 4: [$err]"
case "$err" in *"th-wt: gh pr list failed"*"Bad credentials"*|*"Bad credentials"*"th-wt: gh pr list failed"*) ;; *) fail "$name: gh fallando: mensaje inesperado: [$err]" ;; esac
mv "$TMP/origin.git" "$TMP/origin.gone"
rc=0
err="$(cd "$TMP/repo" && "$WT" close feature/errs --remote --yes 2>&1)" || rc=$?
mv "$TMP/origin.gone" "$TMP/origin.git"
[ "$rc" = 4 ] || fail "$name: origin inaccesible: exit=$rc, esperado 4: [$err]"
case "$err" in *"th-wt: cannot read origin"*) ;; *) fail "$name: origin inaccesible: mensaje inesperado: [$err]" ;; esac
still_there feature/errs || fail "$name: se borró algo"
out="$(cd "$TMP/repo" && PATH="$TMP/nogh" "$WT" close feature/errs --json 2>/dev/null)" || fail "$name: close sin --remote falló sin gh"
[ "$(printf '%s' "$out" | jq -c 'has("pr")')" = false ] || fail "$name: close sin --remote trae la clave pr: [$out]"
pass "$name"

name="close sin --remote no llama a gh"
rm -f "$TMP/gh.calls"
(cd "$TMP/repo" && "$WT" close feature/errs >/dev/null 2>&1) || fail "$name: close falló"
[ ! -e "$TMP/gh.calls" ] || fail "$name: llamó a gh: [$(cat "$TMP/gh.calls")]"
pass "$name"

name="close --remote de una rama ya contenida en la rama por defecto dice que no consultó el PR"
new_branch feature/contained
git -C "$dest" push -q origin HEAD:main
pr_json feature/contained 60 MERGED main "$head"
out="$(cd "$TMP/repo" && "$WT" close feature/contained --remote 2>&1)" || fail "$name: dry-run falló: [$out]"
printf '%s\n' "$out" | grep -qE "pr: +not checked \(already contained in main\)" || fail "$name: [$out]"
printf '%s\n' "$out" | grep -qE "delete: +worktree and branch" || fail "$name: no borra ambos: [$out]"
pass "$name"
