#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

name="checkout de una rama local, con origin inaccesible, crea ~/.worktrees/acme/demo/feature-local en esa rama y su commit, sin tocar el checkout principal"
git -C "$TMP/repo" checkout -q -b feature/local
git -C "$TMP/repo" commit -q --allow-empty -m "commit local"
local_commit="$(git -C "$TMP/repo" rev-parse HEAD)"
git -C "$TMP/repo" checkout -q main

before_head="$(git -C "$TMP/repo" rev-parse HEAD)"
before_branch="$(git -C "$TMP/repo" branch --show-current)"
before_status="$(git -C "$TMP/repo" status --porcelain)"

mv "$TMP/origin.git" "$TMP/origin.git.bak"
rc=0
(cd "$TMP/repo" && "$WT" checkout feature/local) || rc=$?
mv "$TMP/origin.git.bak" "$TMP/origin.git"

[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0"
dest="$HOME/.worktrees/acme/demo/feature-local"
[ -d "$dest" ] || fail "$name: no existe $dest"
[ "$(git -C "$dest" branch --show-current)" = "feature/local" ] || fail "$name: rama incorrecta"
[ "$(git -C "$dest" rev-parse HEAD)" = "$local_commit" ] || fail "$name: commit incorrecto"
[ "$(git -C "$TMP/repo" rev-parse HEAD)" = "$before_head" ] || fail "$name: el HEAD principal cambió"
[ "$(git -C "$TMP/repo" branch --show-current)" = "$before_branch" ] || fail "$name: la rama principal cambió"
[ "$(git -C "$TMP/repo" status --porcelain)" = "$before_status" ] || fail "$name: el status principal cambió"
pass "$name"
