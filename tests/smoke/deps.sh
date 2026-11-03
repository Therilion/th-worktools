#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

# pnpm y npm falsos: anotan "<cwd> <args>" en $TMP/pm.calls; nunca se ejecuta un gestor real.
mkdir -p "$TMP/bin"
for pm in pnpm npm; do
  cat > "$TMP/bin/$pm" <<EOF2
#!/usr/bin/env bash
echo "\$PWD $pm \$*" >> "$TMP/pm.calls"
EOF2
  chmod +x "$TMP/bin/$pm"
done
export PATH="$TMP/bin:$PATH"
: > "$TMP/pm.calls"

# Publica en origin la rama $1 con los archivos $2... (vacíos) en su raíz.
git clone -q "$REMOTE_URL" "$TMP/other"
push_branch() {
  local b="$1"
  shift
  git -C "$TMP/other" checkout -q -b "$b" origin/main
  touch "$@"
  git -C "$TMP/other" add .
  git -C "$TMP/other" commit -q -m "lockfiles de $b"
  git -C "$TMP/other" push -q origin "$b"
}

name="new con pnpm-lock.yaml ejecuta pnpm install --frozen-lockfile en el worktree y devuelve deps: pnpm"
push_branch with-pnpm "$TMP/other/pnpm-lock.yaml"
out="$(cd "$TMP/repo" && "$WT" new feature/pnpm --base with-pnpm --json 2>/dev/null)" || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-pnpm"
[ "$(cat "$TMP/pm.calls")" = "$dest pnpm install --frozen-lockfile" ] || fail "$name: llamadas=[$(cat "$TMP/pm.calls")]"
[ "$(jq -r .deps <<<"$out")" = pnpm ] || fail "$name: salida=[$out]"
pass "$name"
