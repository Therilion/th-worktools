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
