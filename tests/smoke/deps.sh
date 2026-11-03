#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

# pnpm y npm falsos: anotan "<cwd> <gestor> <args>" en $TMP/pm.calls; nunca se ejecuta un gestor real.
# FAKE_PM_OUT=1 imprime basura en stdout, FAKE_PM_STDIN=1 anota su stdin en $TMP/pm.stdin, FAKE_PM_FAIL=1 sale con 1.
mkdir -p "$TMP/bin"
for pm in pnpm npm; do
  cat > "$TMP/bin/$pm" <<EOF2
#!/usr/bin/env bash
echo "\$PWD $pm \$*" >> "$TMP/pm.calls"
[ -z "\${FAKE_PM_OUT:-}" ] || echo "junk de $pm en stdout"
[ -z "\${FAKE_PM_STDIN:-}" ] || echo "stdin=[\$(cat)]" >> "$TMP/pm.stdin"
[ -z "\${FAKE_PM_FAIL:-}" ] || exit 1
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

name="la salida del gestor va a stderr: con --json, stdout es un solo objeto JSON válido"
: > "$TMP/pm.calls"
out="$(cd "$TMP/repo" && FAKE_PM_OUT=1 "$WT" new feature/stdout --base with-pnpm --json 2>"$TMP/stdout.err")" || fail "$name: th-wt new falló"
[ -s "$TMP/pm.calls" ] || fail "$name: el gestor no se ejecutó"
[ "$(jq -s length <<<"$out")" = 1 ] && [ "$(jq -r .deps <<<"$out")" = pnpm ] || fail "$name: stdout=[$out]"
grep -q "junk de pnpm en stdout" "$TMP/stdout.err" || fail "$name: la salida del gestor no llegó a stderr: [$(cat "$TMP/stdout.err")]"
pass "$name"

name="el gestor no recibe el stdin del llamador"
: > "$TMP/pm.calls"
rm -f "$TMP/pm.stdin"
(cd "$TMP/repo" && echo "texto del llamador" | FAKE_PM_STDIN=1 "$WT" new feature/stdin --base with-pnpm 2>/dev/null) || fail "$name: th-wt new falló"
[ -s "$TMP/pm.calls" ] || fail "$name: el gestor no se ejecutó"
[ "$(cat "$TMP/pm.stdin")" = "stdin=[]" ] || fail "$name: el gestor leyó [$(cat "$TMP/pm.stdin")]"
pass "$name"

name="si el gestor falla, new sale con 0, conserva el worktree, avisa en stderr y devuelve deps: failed"
: > "$TMP/pm.calls"
rc=0
out="$(cd "$TMP/repo" && FAKE_PM_FAIL=1 "$WT" new feature/fail --base with-pnpm --json 2>"$TMP/fail.err")" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0"
[ -s "$TMP/pm.calls" ] || fail "$name: el gestor no se ejecutó"
[ -d "$HOME/.worktrees/acme/demo/feature-fail" ] || fail "$name: no se conservó el worktree"
[ "$(jq -r .deps <<<"$out")" = failed ] || fail "$name: salida=[$out]"
grep -q "warning" "$TMP/fail.err" || fail "$name: sin aviso en stderr: [$(cat "$TMP/fail.err")]"
pass "$name"

name="con lockfile y sin el gestor en PATH, new avisa en stderr y devuelve deps: skipped"
# PATH mínimo sin pnpm ni npm (en CI el npm real existe en el PATH normal).
shim="$TMP/bin-sin-gestor"
mkdir -p "$shim"
for t in bash git jq awk sed; do ln -s "$(command -v "$t")" "$shim/$t"; done
for pm in pnpm npm; do
  rc=0
  out="$(cd "$TMP/repo" && PATH="$shim" "$WT" new "feature/sin-$pm" --base "with-$pm" --json 2>"$TMP/sin-$pm.err")" || rc=$?
  [ "$rc" = 0 ] || fail "$name: $pm: exit=$rc, esperado 0"
  [ -d "$HOME/.worktrees/acme/demo/feature-sin-$pm" ] || fail "$name: $pm: no se creó el worktree"
  [ "$(jq -r .deps <<<"$out")" = skipped ] || fail "$name: $pm: salida=[$out]"
  grep -q "warning.*$pm" "$TMP/sin-$pm.err" || fail "$name: $pm: sin aviso en stderr: [$(cat "$TMP/sin-$pm.err")]"
done
pass "$name"
