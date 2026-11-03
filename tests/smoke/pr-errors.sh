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
