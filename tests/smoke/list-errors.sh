#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

git -C "$TMP/repo" remote set-head origin main >/dev/null
(cd "$TMP/repo" && "$WT" new feature/x) || fail "fixture: th-wt new falló"

name="list con git worktree list fallando → exit 1, mensaje th-wt: y el error de git, sin datos en stdout"
# git falso: `worktree list` falla con el error típico de git; el resto va al git real.
shim="$TMP/bin-list-roto"
mkdir -p "$shim"
cat >"$shim/git" <<EOF2
#!/usr/bin/env bash
if [ "\${1:-}" = worktree ] && [ "\${2:-}" = list ]; then
  echo "fatal: worktree list roto" >&2
  exit 128
fi
exec "$(command -v git)" "\$@"
EOF2
chmod +x "$shim/git"
for args in "" "--json"; do
  rc=0
  # shellcheck disable=SC2086
  out="$(cd "$TMP/repo" && PATH="$shim:$PATH" "$WT" list $args 2>"$TMP/list-err")" || rc=$?
  err="$(cat "$TMP/list-err")"
  [ "$rc" = 1 ] || fail "$name: (list $args) exit=$rc, esperado 1: [$err]"
  case "$err" in *"th-wt: git worktree list failed"*) ;; *) fail "$name: (list $args) falta el mensaje th-wt: [$err]" ;; esac
  case "$err" in *"fatal: worktree list roto"*) ;; *) fail "$name: (list $args) falta el error de git: [$err]" ;; esac
  [ -z "$out" ] || fail "$name: (list $args) stdout no está vacío: [$out]"
done
pass "$name"

name="list con git worktree list fallando al leer las filas → exit 1 con mensaje th-wt:"
# git falso: la primera llamada a `worktree list` (check_root_overlap) va al git real; las siguientes fallan.
shim="$TMP/bin-list-filas"
mkdir -p "$shim"
cat >"$shim/git" <<EOF2
#!/usr/bin/env bash
if [ "\${1:-}" = worktree ] && [ "\${2:-}" = list ]; then
  if [ ! -e "$TMP/list-marca" ]; then
    : >"$TMP/list-marca"
  else
    echo "fatal: worktree list roto" >&2
    exit 128
  fi
fi
exec "$(command -v git)" "\$@"
EOF2
chmod +x "$shim/git"
rm -f "$TMP/list-marca"
rc=0
out="$(cd "$TMP/repo" && PATH="$shim:$PATH" "$WT" list 2>"$TMP/list-err")" || rc=$?
err="$(cat "$TMP/list-err")"
[ "$rc" = 1 ] || fail "$name: exit=$rc, esperado 1: [$err]"
case "$err" in *"th-wt: git worktree list failed"*) ;; *) fail "$name: falta el mensaje th-wt: [$err]" ;; esac
case "$err" in *"fatal: worktree list roto"*) ;; *) fail "$name: falta el error de git: [$err]" ;; esac
[ -z "$out" ] || fail "$name: stdout no está vacío: [$out]"
pass "$name"
