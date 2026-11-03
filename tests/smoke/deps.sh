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

name="new con package-lock.json ejecuta npm ci en el worktree y devuelve deps: npm"
: > "$TMP/pm.calls"
push_branch with-npm "$TMP/other/package-lock.json"
out="$(cd "$TMP/repo" && "$WT" new feature/npm --base with-npm --json 2>/dev/null)" || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-npm"
[ "$(cat "$TMP/pm.calls")" = "$dest npm ci" ] || fail "$name: llamadas=[$(cat "$TMP/pm.calls")]"
[ "$(jq -r .deps <<<"$out")" = npm ] || fail "$name: salida=[$out]"
pass "$name"

name="new con ambos lockfiles ejecuta solo pnpm"
: > "$TMP/pm.calls"
push_branch with-both "$TMP/other/pnpm-lock.yaml" "$TMP/other/package-lock.json"
out="$(cd "$TMP/repo" && "$WT" new feature/both --base with-both --json 2>/dev/null)" || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-both"
[ "$(cat "$TMP/pm.calls")" = "$dest pnpm install --frozen-lockfile" ] || fail "$name: llamadas=[$(cat "$TMP/pm.calls")]"
[ "$(jq -r .deps <<<"$out")" = pnpm ] || fail "$name: salida=[$out]"
pass "$name"

name="new sin lockfile no ejecuta ningún gestor y devuelve deps: skipped"
: > "$TMP/pm.calls"
out="$(cd "$TMP/repo" && "$WT" new feature/nolock --json 2>/dev/null)" || fail "$name: th-wt new falló"
[ ! -s "$TMP/pm.calls" ] || fail "$name: llamadas=[$(cat "$TMP/pm.calls")]"
[ "$(jq -r .deps <<<"$out")" = skipped ] || fail "$name: salida=[$out]"
pass "$name"
