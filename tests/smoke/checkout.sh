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

name="checkout sin --remote de una rama remota ya traída funciona con origin inaccesible y queda con upstream"
git -C "$TMP/other" checkout -q -b feature/fetched
git -C "$TMP/other" commit -q --allow-empty -m "fetched commit"
git -C "$TMP/other" push -q origin feature/fetched

git -C "$TMP/repo" fetch -q origin
if git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/fetched; then
  fail "$name: ya existe refs/heads/feature/fetched en repo"
fi
if ! git -C "$TMP/repo" show-ref --verify --quiet refs/remotes/origin/feature/fetched; then
  fail "$name: no existe refs/remotes/origin/feature/fetched en repo"
fi

remote_commit="$(git -C "$TMP/repo" rev-parse refs/remotes/origin/feature/fetched)"

mv "$TMP/origin.git" "$TMP/origin.git.bak"
rc=0
(cd "$TMP/repo" && "$WT" checkout feature/fetched) || rc=$?
mv "$TMP/origin.git.bak" "$TMP/origin.git"

[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0"
dest="$HOME/.worktrees/acme/demo/feature-fetched"
[ -d "$dest" ] || fail "$name: no existe $dest"
[ "$(git -C "$dest" branch --show-current)" = "feature/fetched" ] || fail "$name: rama incorrecta"
[ "$(git -C "$dest" rev-parse HEAD)" = "$remote_commit" ] || fail "$name: commit incorrecto"
[ "$(git -C "$TMP/repo" config --get branch.feature/fetched.remote || true)" = "origin" ] || fail "$name: upstream remote incorrecto"
[ "$(git -C "$TMP/repo" config --get branch.feature/fetched.merge || true)" = "refs/heads/feature/fetched" ] || fail "$name: upstream merge incorrecto"
pass "$name"

name="clon --single-branch: checkout --remote trae la rama y git push desde el worktree llega a origin/<rama>"
git -C "$TMP/other" checkout -q -b feature/sb
git -C "$TMP/other" commit -q --allow-empty -m "sb commit"
git -C "$TMP/other" push -q origin feature/sb
origin_commit="$(git -C "$TMP/origin.git" rev-parse refs/heads/feature/sb)"

git clone -q --single-branch -b main "$TMP/origin.git" "$TMP/r-sb"
git -C "$TMP/r-sb" remote set-url origin "$REMOTE_URL"

rc=0
(cd "$TMP/r-sb" && "$WT" checkout feature/sb --remote) || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0"
dest="$HOME/.worktrees/acme/demo/feature-sb"
[ -d "$dest" ] || fail "$name: no existe $dest"
[ "$(git -C "$dest" branch --show-current)" = "feature/sb" ] || fail "$name: rama incorrecta"
[ "$(git -C "$dest" rev-parse HEAD)" = "$origin_commit" ] || fail "$name: commit incorrecto"

git -C "$dest" commit -q --allow-empty -m "sb worktree commit"
new_head="$(git -C "$dest" rev-parse HEAD)"
git -C "$dest" push -q || fail "$name: git push falló"
[ "$(git -C "$TMP/origin.git" rev-parse refs/heads/feature/sb)" = "$new_head" ] || fail "$name: push no llegó a origin"
pass "$name"

name="checkout --json devuelve solo path, branch, repo y deps"
git -C "$TMP/repo" branch feature/json-co
out="$(cd "$TMP/repo" && "$WT" checkout feature/json-co --json)" || fail "$name: th-wt checkout falló"
expected="{\"branch\":\"feature/json-co\",\"deps\":\"skipped\",\"path\":\"$HOME/.worktrees/acme/demo/feature-json-co\",\"repo\":\"acme/demo\"}"
[ "$(printf '%s' "$out" | jq -S -c .)" = "$expected" ] || fail "$name: salida=[$out]"
pass "$name"

name="checkout de una rama de origin funciona aunque exista una rama local llamada origin/<rama>"
git clone -q "$REMOTE_URL" "$TMP/other-amb"
git -C "$TMP/other-amb" checkout -q -b feature/amb
git -C "$TMP/other-amb" commit -q --allow-empty -m "amb commit"
git -C "$TMP/other-amb" push -q origin feature/amb
origin_commit="$(git -C "$TMP/origin.git" rev-parse refs/heads/feature/amb)"
git -C "$TMP/repo" fetch -q origin
git -C "$TMP/repo" branch origin/feature/amb main

rc=0
err="$(cd "$TMP/repo" && "$WT" checkout feature/amb 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$err]"
dest="$HOME/.worktrees/acme/demo/feature-amb"
[ "$(git -C "$dest" branch --show-current)" = "feature/amb" ] || fail "$name: rama incorrecta"
[ "$(git -C "$dest" rev-parse HEAD)" = "$origin_commit" ] || fail "$name: no parte del commit de origin"
pass "$name"
