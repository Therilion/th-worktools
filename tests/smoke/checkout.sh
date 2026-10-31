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

name="checkout --remote de una rama que existe en local y en origin usa la local tal cual: no hace fetch ni la mueve"
git -C "$TMP/repo" checkout -q -b feature/both
git -C "$TMP/repo" commit -q --allow-empty -m "local both"
git -C "$TMP/repo" push -q -u origin feature/both
git -C "$TMP/repo" checkout -q main

git clone -q "$REMOTE_URL" "$TMP/other"
git -C "$TMP/other" checkout -q feature/both
git -C "$TMP/other" commit -q --allow-empty -m "origin both advanced"
git -C "$TMP/other" push -q origin feature/both

local_commit="$(git -C "$TMP/repo" rev-parse refs/heads/feature/both)"
remote_ref_before="$(git -C "$TMP/repo" rev-parse refs/remotes/origin/feature/both)"

rc=0
(cd "$TMP/repo" && "$WT" checkout feature/both --remote) || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0"
dest="$HOME/.worktrees/acme/demo/feature-both"
[ -d "$dest" ] || fail "$name: no existe $dest"
[ "$(git -C "$dest" branch --show-current)" = "feature/both" ] || fail "$name: rama incorrecta"
[ "$(git -C "$dest" rev-parse HEAD)" = "$local_commit" ] || fail "$name: commit incorrecto"
[ "$(git -C "$TMP/repo" rev-parse refs/heads/feature/both)" = "$local_commit" ] || fail "$name: la rama local se movió"
[ "$(git -C "$TMP/repo" rev-parse refs/remotes/origin/feature/both)" = "$remote_ref_before" ] || fail "$name: refs/remotes/origin/feature/both cambió"
pass "$name"

name="checkout --remote de una rama que solo está en origin y nunca se trajo crea la rama local en el commit de origin, con upstream origin/<rama>"
git -C "$TMP/other" checkout -q -b feature/remote-only
git -C "$TMP/other" commit -q --allow-empty -m "remote only commit"
git -C "$TMP/other" push -q origin feature/remote-only

if git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/remote-only; then
  fail "$name: ya existe refs/heads/feature/remote-only en repo"
fi
if git -C "$TMP/repo" show-ref --verify --quiet refs/remotes/origin/feature/remote-only; then
  fail "$name: ya existe refs/remotes/origin/feature/remote-only en repo"
fi

origin_commit="$(git -C "$TMP/origin.git" rev-parse refs/heads/feature/remote-only)"

rc=0
(cd "$TMP/repo" && "$WT" checkout feature/remote-only --remote) || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0"
dest="$HOME/.worktrees/acme/demo/feature-remote-only"
[ -d "$dest" ] || fail "$name: no existe $dest"
[ "$(git -C "$dest" branch --show-current)" = "feature/remote-only" ] || fail "$name: rama incorrecta"
[ "$(git -C "$dest" rev-parse HEAD)" = "$origin_commit" ] || fail "$name: commit incorrecto"
[ "$(git -C "$TMP/repo" config --get branch.feature/remote-only.remote || true)" = "origin" ] || fail "$name: upstream remote incorrecto"
[ "$(git -C "$TMP/repo" config --get branch.feature/remote-only.merge || true)" = "refs/heads/feature/remote-only" ] || fail "$name: upstream merge incorrecto"
pass "$name"
