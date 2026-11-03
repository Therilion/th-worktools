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
echo '{"number":7,"title":"t","headRefName":"h","baseRefName":"main"}' > "$TMP/gh.json"

name="pr con <n> ausente o que no es un entero positivo sin ceros a la izquierda sale con 2 sin crear nada"
for n in "" abc 0 05 1.5 -1 1a; do
  rc=0
  if [ -z "$n" ]; then err="$(cd "$TMP/repo" && "$WT" pr 2>&1)" || rc=$?
  else err="$(cd "$TMP/repo" && "$WT" pr "$n" 2>&1)" || rc=$?; fi
  [ "$rc" = 2 ] || fail "$name: n=[$n] exit=$rc, esperado 2: [$err]"
done
[ ! -e "$HOME/.worktrees" ] || fail "$name: se creó $HOME/.worktrees"
[ ! -e "$TMP/gh.calls" ] || fail "$name: llamó a gh"
[ -z "$(git -C "$TMP/repo" branch --list 'review/*')" ] || fail "$name: se creó una rama review/*"
pass "$name"

name="pr sin gh sale con 3 y no crea nada"
mkdir -p "$TMP/nogh"
for tool in env bash git jq sed awk cat; do ln -sf "$(command -v "$tool")" "$TMP/nogh/$tool"; done
rc=0
err="$(cd "$TMP/repo" && PATH="$TMP/nogh" "$WT" pr 7 2>&1)" || rc=$?
[ "$rc" = 3 ] || fail "$name: exit=$rc, esperado 3: [$err]"
case "$err" in *"th-wt: missing dependency: gh"*) ;; *) fail "$name: mensaje inesperado: [$err]" ;; esac
[ ! -e "$HOME/.worktrees" ] || fail "$name: se creó $HOME/.worktrees"
[ -z "$(git -C "$TMP/repo" branch --list 'review/*')" ] || fail "$name: se creó una rama review/*"
pass "$name"

name="pr sale con 4 y no crea nada si gh falla o devuelve algo inesperado"
nothing_created() { [ ! -e "$HOME/.worktrees" ] && [ -z "$(git -C "$TMP/repo" branch --list 'review/*')" ]; }
mkdir -p "$TMP/badgh"
printf '#!/usr/bin/env bash\necho "GraphQL: Could not resolve to a PullRequest with the number of 7." >&2\nexit 1\n' > "$TMP/badgh/gh"
chmod +x "$TMP/badgh/gh"
rc=0
err="$(cd "$TMP/repo" && PATH="$TMP/badgh:$PATH" "$WT" pr 7 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: gh fallando: exit=$rc, esperado 4: [$err]"
case "$err" in *"th-wt: PR not found, not authenticated, or no access?"*) ;; *) fail "$name: gh fallando: mensaje inesperado: [$err]" ;; esac
case "$err" in *"Could not resolve to a PullRequest"*) ;; *) fail "$name: gh fallando: falta el mensaje de gh: [$err]" ;; esac
nothing_created || fail "$name: gh fallando: se creó algo"
for bad in 'not json' '[]' '{"number":7,"title":"t","headRefName":"h"}' '{"number":"7","title":"t","headRefName":"h","baseRefName":"main"}' '{"number":7,"title":"t","headRefName":"h","baseRefName":"a..b"}' '{"number":7,"title":"t","headRefName":"h","baseRefName":""}'; do
  echo "$bad" > "$TMP/gh.json"
  rc=0
  err="$(cd "$TMP/repo" && "$WT" pr 7 2>&1)" || rc=$?
  [ "$rc" = 4 ] || fail "$name: salida [$bad]: exit=$rc, esperado 4: [$err]"
  case "$err" in *"th-wt: unexpected output from gh pr view"*) ;; *) fail "$name: salida [$bad]: mensaje inesperado: [$err]" ;; esac
  nothing_created || fail "$name: salida [$bad]: se creó algo"
done
pass "$name"

name="pr sale con 4 y no crea nada si origin no se puede leer, el PR no tiene head o la base no está en origin"
git -C "$TMP/origin.git" update-ref refs/pull/7/head "$(git -C "$TMP/origin.git" commit-tree -p main -m pr "main^{tree}")"
echo '{"number":7,"title":"t","headRefName":"h","baseRefName":"main"}' > "$TMP/gh.json"
mv "$TMP/origin.git" "$TMP/origin.gone"
rc=0
err="$(cd "$TMP/repo" && "$WT" pr 7 2>&1)" || rc=$?
mv "$TMP/origin.gone" "$TMP/origin.git"
[ "$rc" = 4 ] || fail "$name: origin inaccesible: exit=$rc, esperado 4: [$err]"
case "$err" in *"th-wt: fetch of PR #7 failed"*) ;; *) fail "$name: origin inaccesible: mensaje inesperado: [$err]" ;; esac
nothing_created || fail "$name: origin inaccesible: se creó algo"
echo '{"number":8,"title":"t","headRefName":"h","baseRefName":"main"}' > "$TMP/gh.json"
rc=0
err="$(cd "$TMP/repo" && "$WT" pr 8 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: PR sin head: exit=$rc, esperado 4: [$err]"
case "$err" in *"th-wt: fetch of PR #8 failed"*) ;; *) fail "$name: PR sin head: mensaje inesperado: [$err]" ;; esac
nothing_created || fail "$name: PR sin head: se creó algo"
echo '{"number":7,"title":"t","headRefName":"h","baseRefName":"gone-base"}' > "$TMP/gh.json"
rc=0
err="$(cd "$TMP/repo" && "$WT" pr 7 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: base inexistente: exit=$rc, esperado 4: [$err]"
case "$err" in *"th-wt: fetch of origin/gone-base failed"*) ;; *) fail "$name: base inexistente: mensaje inesperado: [$err]" ;; esac
nothing_created || fail "$name: base inexistente: se creó algo"
pass "$name"

name="pr sale con 4 sin llamar a gh ni modificar nada si pr-reviews/pr-<n>/code o la rama review/pr-<n> ya existen"
rm -f "$TMP/gh.calls"
echo '{"number":7,"title":"t","headRefName":"h","baseRefName":"main"}' > "$TMP/gh.json"
taken="$HOME/.worktrees/acme/demo/pr-reviews/pr-7/code"
mkdir -p "$taken"
echo mio > "$taken/notas.txt"
rc=0
err="$(cd "$TMP/repo" && "$WT" pr 7 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: ruta ocupada: exit=$rc, esperado 4: [$err]"
case "$err" in *"th-wt: destination already exists: $taken"*) ;; *) fail "$name: ruta ocupada: mensaje inesperado: [$err]" ;; esac
# lo local va antes que la dependencia: sin gh también sale 4, no 3
rc=0
err="$(cd "$TMP/repo" && PATH="$TMP/nogh" "$WT" pr 7 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: ruta ocupada sin gh: exit=$rc, esperado 4: [$err]"
[ "$(cat "$taken/notas.txt")" = mio ] || fail "$name: se modificó la ruta ocupada"
[ -z "$(git -C "$TMP/repo" branch --list 'review/*')" ] || fail "$name: se creó una rama review/*"
rm -r "$HOME/.worktrees"
git -C "$TMP/repo" branch review/pr-8 main
branch_oid="$(git -C "$TMP/repo" rev-parse review/pr-8)"
rc=0
err="$(cd "$TMP/repo" && "$WT" pr 8 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: rama existente: exit=$rc, esperado 4: [$err]"
case "$err" in *"th-wt: branch already exists: review/pr-8"*) ;; *) fail "$name: rama existente: mensaje inesperado: [$err]" ;; esac
[ "$(git -C "$TMP/repo" rev-parse review/pr-8)" = "$branch_oid" ] || fail "$name: la rama cambió"
[ ! -e "$HOME/.worktrees" ] || fail "$name: se creó $HOME/.worktrees"
[ ! -e "$TMP/gh.calls" ] || fail "$name: llamó a gh: [$(cat "$TMP/gh.calls")]"
pass "$name"
