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
