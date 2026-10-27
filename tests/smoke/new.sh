#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

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

name="new deja el checkout principal igual (rama y status)"
echo wip > "$TMP/repo/wip.txt"
before="$(git -C "$TMP/repo" rev-parse HEAD)|$(git -C "$TMP/repo" branch --show-current)|$(git -C "$TMP/repo" status --porcelain)"
(cd "$TMP/repo" && "$WT" new feature/untouched) || fail "$name: th-wt new falló"
after="$(git -C "$TMP/repo" rev-parse HEAD)|$(git -C "$TMP/repo" branch --show-current)|$(git -C "$TMP/repo" status --porcelain)"
[ "$before" = "$after" ] || fail "$name: antes=[$before] después=[$after]"
rm "$TMP/repo/wip.txt"
pass "$name"

name="new --json devuelve solo path, branch y repo"
out="$(cd "$TMP/repo" && "$WT" new feature/json --json)" || fail "$name: th-wt new falló"
expected="{\"branch\":\"feature/json\",\"path\":\"$HOME/.worktrees/acme/demo/feature-json\",\"repo\":\"acme/demo\"}"
[ "$(printf '%s' "$out" | jq -S -c .)" = "$expected" ] || fail "$name: salida=[$out]"
pass "$name"

name="new --base release/1.2 parte de origin/release/1.2"
git -C "$TMP/other" checkout -q -b release/1.2
git -C "$TMP/other" commit -q --allow-empty -m "release 1.2"
git -C "$TMP/other" push -q origin release/1.2
(cd "$TMP/repo" && "$WT" new fix/x --base release/1.2) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/fix-x"
[ "$(git -C "$dest" rev-parse HEAD)" = "$(git -C "$TMP/origin.git" rev-parse release/1.2)" ] || fail "$name: no parte de origin/release/1.2"
pass "$name"

name="new con remote https://github.com/acme/demo.git usa acme/demo"
HTTPS_URL="https://github.com/acme/demo.git"
git config --global --add "url.$TMP/origin.git.insteadOf" "$HTTPS_URL"
git clone -q "$TMP/origin.git" "$TMP/repo-https"
git -C "$TMP/repo-https" remote set-url origin "$HTTPS_URL"
(cd "$TMP/repo-https" && "$WT" new feature/https) || fail "$name: th-wt new falló"
[ -d "$HOME/.worktrees/acme/demo/feature-https" ] || fail "$name: no existe el worktree en acme/demo"
pass "$name"

name="new ejecutado desde dentro de un worktree usa el repo principal"
inside="$HOME/.worktrees/acme/demo/feature-login"
(cd "$inside" && "$WT" new feature/nested) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-nested"
[ -d "$dest" ] || fail "$name: no existe $dest"
[ "$(git -C "$dest" branch --show-current)" = "feature/nested" ] || fail "$name: rama incorrecta"
pass "$name"

name="new crea la rama sin upstream (no sigue a origin/<base>)"
(cd "$TMP/repo" && "$WT" new feature/notrack) || fail "$name: th-wt new falló"
[ -z "$(git -C "$TMP/repo" config --get "branch.feature/notrack.merge" || true)" ] || fail "$name: la rama tiene upstream"
pass "$name"

name="clon --single-branch: --base de otra rama existente en origin funciona"
git clone -q --single-branch -b main "$TMP/origin.git" "$TMP/r-sb"
git -C "$TMP/r-sb" remote set-url origin "$REMOTE_URL"
(cd "$TMP/r-sb" && "$WT" new fix/sb --base release/1.2) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/fix-sb"
[ "$(git -C "$dest" rev-parse HEAD)" = "$(git -C "$TMP/origin.git" rev-parse release/1.2)" ] || fail "$name: no parte de origin/release/1.2"
pass "$name"
