#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

name="rama inexistente → exit 4 sin crear nada; sin --remote sugiere --remote, con --remote dice que no está en origin"
dest="$HOME/.worktrees/acme/demo/feature-ghost"

rc=0
err="$(cd "$TMP/repo" && "$WT" checkout feature/ghost 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: (sin --remote) exit=$rc, esperado 4"
[ ! -e "$dest" ] || fail "$name: (sin --remote) se creó el destino"
[ -z "$(git -C "$TMP/repo" branch --list feature/ghost)" ] || fail "$name: (sin --remote) se creó la rama"
[ -z "$(git -C "$TMP/repo" config --get-regexp '^branch\.feature/ghost\.' || true)" ] || fail "$name: (sin --remote) se escribió config de la rama"
case "$err" in *"feature/ghost"*) ;; *) fail "$name: (sin --remote) el mensaje no menciona la rama: [$err]" ;; esac
case "$err" in *"--remote"*) ;; *) fail "$name: (sin --remote) el mensaje no sugiere --remote: [$err]" ;; esac

rc=0
err="$(cd "$TMP/repo" && "$WT" checkout feature/ghost --remote 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: (con --remote) exit=$rc, esperado 4"
[ ! -e "$dest" ] || fail "$name: (con --remote) se creó el destino"
[ -z "$(git -C "$TMP/repo" branch --list feature/ghost)" ] || fail "$name: (con --remote) se creó la rama"
[ -z "$(git -C "$TMP/repo" config --get-regexp '^branch\.feature/ghost\.' || true)" ] || fail "$name: (con --remote) se escribió config de la rama"
case "$err" in *"feature/ghost"*) ;; *) fail "$name: (con --remote) el mensaje no menciona la rama: [$err]" ;; esac
case "$err" in *"not found on origin"*) ;; *) fail "$name: (con --remote) el mensaje no dice 'not found on origin': [$err]" ;; esac
case "$err" in *"try --remote"*) fail "$name: (con --remote) el mensaje sugiere --remote: [$err]" ;; esac

pass "$name"

name="rama abierta en otro worktree o en el checkout principal → exit 4 con la ruta de ese worktree, sin crear nada"

# Caso 1: main en el checkout principal
rc=0
err="$(cd "$TMP/repo" && "$WT" checkout main 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: (main) exit=$rc, esperado 4"
case "$err" in *"$TMP/repo"*) ;; *) fail "$name: (main) el mensaje no menciona el repo principal: [$err]" ;; esac
[ ! -e "$HOME/.worktrees/acme/demo/main" ] || fail "$name: (main) se creó el destino"

# Caso 2: feature/busy en otro worktree fuera de la raíz
git -C "$TMP/repo" worktree add -q "$TMP/busy-wt" -b feature/busy
before_count="$(git -C "$TMP/repo" worktree list --porcelain | grep -c '^worktree ')"
rc=0
err="$(cd "$TMP/repo" && "$WT" checkout feature/busy 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: (busy) exit=$rc, esperado 4"
case "$err" in *"$TMP/busy-wt"*) ;; *) fail "$name: (busy) el mensaje no menciona la ruta del worktree: [$err]" ;; esac
[ ! -e "$HOME/.worktrees/acme/demo/feature-busy" ] || fail "$name: (busy) se creó el destino"
after_count="$(git -C "$TMP/repo" worktree list --porcelain | grep -c '^worktree ')"
[ "$before_count" = "$after_count" ] || fail "$name: (busy) cambió la cantidad de worktrees"

pass "$name"

name="destino existente → exit 4 con la ruta, sin crear ni modificar nada, también con --remote y origin inaccesible"

# Caso 1: rama local existente, destino preexistente
git -C "$TMP/repo" branch feature/taken
dest1="$HOME/.worktrees/acme/demo/feature-taken"
mkdir -p "$dest1" && touch "$dest1/marker"
rc=0
err="$(cd "$TMP/repo" && "$WT" checkout feature/taken 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: (local) exit=$rc, esperado 4"
case "$err" in *"$dest1"*) ;; *) fail "$name: (local) el mensaje no menciona la ruta: [$err]" ;; esac
[ "$(ls -A "$dest1")" = "marker" ] || fail "$name: (local) el destino cambió"

# Caso 2: rama remota, destino preexistente con origin inaccesible
dest2="$HOME/.worktrees/acme/demo/feature-taken-remote"
mkdir -p "$dest2" && touch "$dest2/marker"
mv "$TMP/origin.git" "$TMP/origin.git.bak"
rc=0
err="$(cd "$TMP/repo" && "$WT" checkout feature/taken-remote --remote 2>&1)" || rc=$?
mv "$TMP/origin.git.bak" "$TMP/origin.git"
[ "$rc" = 4 ] || fail "$name: (remote) exit=$rc, esperado 4"
case "$err" in *"$dest2"*) ;; *) fail "$name: (remote) el mensaje no menciona la ruta: [$err]" ;; esac
case "$err" in *"cannot read origin"*) fail "$name: (remote) consultó la red antes de validar el destino: [$err]" ;; esac
[ "$(ls -A "$dest2")" = "marker" ] || fail "$name: (remote) el destino cambió"
[ -z "$(git -C "$TMP/repo" branch --list feature/taken-remote)" ] || fail "$name: (remote) se creó la rama"

pass "$name"

name="--remote con origin inaccesible → exit 4 \"cannot read origin\", sin crear nada"
dest="$HOME/.worktrees/acme/demo/feature-offline"
mv "$TMP/origin.git" "$TMP/origin.git.bak"
rc=0
err="$(cd "$TMP/repo" && "$WT" checkout feature/offline --remote 2>&1)" || rc=$?
mv "$TMP/origin.git.bak" "$TMP/origin.git"
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4"
case "$err" in *"cannot read origin"*) ;; *) fail "$name: el mensaje no menciona 'cannot read origin': [$err]" ;; esac
[ ! -e "$dest" ] || fail "$name: se creó el destino"
[ -z "$(git -C "$TMP/repo" branch --list feature/offline)" ] || fail "$name: se creó la rama"
[ -z "$(git -C "$TMP/repo" config --get-regexp '^branch\.feature/offline\.' || true)" ] || fail "$name: se escribió config de la rama"
pass "$name"

name="nombre de rama inválido → exit 2 sin tocar la red ni crear nada"
mv "$TMP/origin.git" "$TMP/origin.git.bak"
for b in "bad..name" "feature/x.lock"; do
  rc=0
  err="$(cd "$TMP/repo" && "$WT" checkout "$b" --remote 2>&1)" || rc=$?
  [ "$rc" = 2 ] || fail "$name: [$b]: exit=$rc, esperado 2"
  case "$err" in *"$b"*) ;; *) fail "$name: [$b]: el mensaje no menciona el nombre: [$err]" ;; esac
  [ ! -e "$HOME/.worktrees/acme/demo/${b//\//-}" ] || fail "$name: [$b]: se creó el destino"
  [ -z "$(git -C "$TMP/repo" branch --list "$b")" ] || fail "$name: [$b]: se creó la rama"
done
mv "$TMP/origin.git.bak" "$TMP/origin.git"
pass "$name"

name="si git worktree add falla con una rama de origin, no queda la rama local y el reintento crea el worktree con upstream"
root_dir="$HOME/.worktrees/acme/demo"
dest="$root_dir/feature-retry"

git clone -q "$REMOTE_URL" "$TMP/other-retry"
git -C "$TMP/other-retry" checkout -q -b feature/retry
git -C "$TMP/other-retry" commit -q --allow-empty -m retry
git -C "$TMP/other-retry" push -q origin feature/retry
git -C "$TMP/repo" fetch -q origin
git -C "$TMP/repo" show-ref --verify --quiet refs/remotes/origin/feature/retry || fail "$name: falta refs/remotes/origin/feature/retry en el fixture"
[ -z "$(git -C "$TMP/repo" branch --list feature/retry)" ] || fail "$name: el fixture ya tenía la rama local"

# Primer intento: la raíz no es escribible, así que git worktree add falla.
mkdir -p "$root_dir"
chmod a-w "$root_dir"
rc=0
err="$(cd "$TMP/repo" && "$WT" checkout feature/retry 2>&1)" || rc=$?
chmod u+w "$root_dir"
[ "$rc" != 0 ] || fail "$name: (primer intento) esperaba fallo y salió con exit 0"
if git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/retry; then
  fail "$name: (primer intento) quedó refs/heads/feature/retry: [$err]"
fi
[ -z "$(git -C "$TMP/repo" config --get-regexp '^branch\.feature/retry\.' || true)" ] || fail "$name: (primer intento) quedó config de la rama"

# Reintento: ahora sí se puede escribir y debe quedar con upstream.
rc=0
err="$(cd "$TMP/repo" && "$WT" checkout feature/retry 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: (reintento) exit=$rc, esperado 0: [$err]"
[ -d "$dest" ] || fail "$name: (reintento) no se creó $dest"
[ "$(git -C "$TMP/repo" config --get branch.feature/retry.remote)" = "origin" ] || fail "$name: (reintento) branch.feature/retry.remote != origin"
[ "$(git -C "$TMP/repo" config --get branch.feature/retry.merge)" = "refs/heads/feature/retry" ] || fail "$name: (reintento) branch.feature/retry.merge != refs/heads/feature/retry"

pass "$name"
