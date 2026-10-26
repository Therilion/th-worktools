#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -P "$(dirname "$0")/.." && pwd)"
WT="$ROOT/skills/th-worktree/scripts/th-wt"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/th.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# HOME aislado: ~/.worktrees y el gitconfig global caen dentro de $TMP.
export HOME="$TMP/home"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
mkdir -p "$HOME"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# origin ficticio de GitHub, redirigido a un repo bare local.
REMOTE_URL="git@github.com:acme/demo.git"
git init -q --bare -b main "$TMP/origin.git"
git config --global "url.$TMP/origin.git.insteadOf" "$REMOTE_URL"
git init -q -b main "$TMP/repo"
git -C "$TMP/repo" remote add origin "$REMOTE_URL"
git -C "$TMP/repo" commit -q --allow-empty -m init
git -C "$TMP/repo" push -q -u origin main

name="new crea el worktree en ~/.worktrees/acme/demo/feature-login con la rama feature/login"
(cd "$TMP/repo" && "$WT" new feature/login) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-login"
[ -d "$dest" ] || fail "$name: no existe $dest"
[ "$(git -C "$dest" branch --show-current)" = "feature/login" ] || fail "$name: rama incorrecta"
pass "$name"

name="new parte de la rama por defecto de origin, no del HEAD local"
git clone -q "$REMOTE_URL" "$TMP/other"
git -C "$TMP/other" commit -q --allow-empty -m "avance en origin"
git -C "$TMP/other" push -q origin main
git -C "$TMP/repo" checkout -q -b local-only
git -C "$TMP/repo" commit -q --allow-empty -m "solo local"
(cd "$TMP/repo" && "$WT" new feature/base) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-base"
[ "$(git -C "$dest" rev-parse HEAD)" = "$(git -C "$TMP/origin.git" rev-parse main)" ] || fail "$name: no parte de origin/main"
git -C "$TMP/repo" checkout -q main
pass "$name"
