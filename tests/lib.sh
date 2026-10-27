#!/usr/bin/env bash
# Fixture compartida: se carga con `. "$(dirname "$0")/../lib.sh"` desde tests/smoke/*.sh.
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034 # lo usan los archivos que cargan este
WT="$ROOT/skills/th-worktree/scripts/th-wt"

# cd -P: en macOS $TMPDIR cuelga de /var (symlink) y git imprime /private/var.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/th.XXXXXX")"
TMP="$(cd -P "$TMP" && pwd)"
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
