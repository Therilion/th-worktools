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

name="destino existente → exit 4 y mensaje con la ruta"
dest="$HOME/.worktrees/acme/demo/feature-exists"
mkdir -p "$dest" && touch "$dest/marker"
rc=0
err="$(cd "$TMP/repo" && "$WT" new feature/exists 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4"
case "$err" in *"$dest"*) ;; *) fail "$name: el mensaje no menciona la ruta: [$err]" ;; esac
[ -z "$(git -C "$TMP/repo" branch --list feature/exists)" ] || fail "$name: se creó la rama"
[ "$(ls -A "$dest")" = "marker" ] || fail "$name: el destino cambió"
pass "$name"

name="rama existente en local o en origin → exit 4 y mensaje con la rama"
git -C "$TMP/repo" branch feature/local-b
git -C "$TMP/other" push -q origin HEAD:refs/heads/feature/remote-b
for b in feature/local-b feature/remote-b; do
  rc=0
  err="$(cd "$TMP/repo" && "$WT" new "$b" 2>&1)" || rc=$?
  [ "$rc" = 4 ] || fail "$name: $b: exit=$rc, esperado 4"
  case "$err" in *"$b"*) ;; *) fail "$name: el mensaje no menciona $b: [$err]" ;; esac
  [ ! -e "$HOME/.worktrees/acme/demo/${b//\//-}" ] || fail "$name: $b: se creó el destino"
done
[ -z "$(git -C "$TMP/repo" branch -r --list origin/feature/remote-b)" ] || fail "$name: se hizo fetch antes de validar"
pass "$name"

name="falta git o jq → exit 3 y mensaje con la dependencia"
for dep in git jq; do
  # PATH mínimo con las herramientas de th-wt menos la que "falta".
  shim="$TMP/bin-sin-$dep"
  mkdir -p "$shim"
  for t in bash git jq awk sed; do
    [ "$t" = "$dep" ] || ln -s "$(command -v "$t")" "$shim/$t"
  done
  rc=0
  err="$(cd "$TMP/repo" && PATH="$shim" "$WT" new "feature/sin-$dep" 2>&1)" || rc=$?
  [ "$rc" = 3 ] || fail "$name: sin $dep: exit=$rc, esperado 3"
  case "$err" in *"$dep"*) ;; *) fail "$name: el mensaje no menciona $dep: [$err]" ;; esac
  [ ! -e "$HOME/.worktrees/acme/demo/feature-sin-$dep" ] || fail "$name: sin $dep: se creó el destino"
  [ -z "$(git -C "$TMP/repo" branch --list "feature/sin-$dep")" ] || fail "$name: sin $dep: se creó la rama"
done
pass "$name"

name="repo sin origin → exit 4 y mensaje"
git init -q -b main "$TMP/no-origin"
git -C "$TMP/no-origin" commit -q --allow-empty -m init
rc=0
err="$(cd "$TMP/no-origin" && "$WT" new feature/x 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4"
case "$err" in *origin*) ;; *) fail "$name: el mensaje no menciona origin: [$err]" ;; esac
[ -z "$(git -C "$TMP/no-origin" branch --list feature/x)" ] || fail "$name: se creó la rama"
[ "$(git -C "$TMP/no-origin" worktree list | wc -l | tr -d ' ')" = 1 ] || fail "$name: se creó un worktree"
pass "$name"

name="--help → exit 0; subcomando ausente o desconocido → exit 2"
out="$("$WT" --help)" || fail "$name: --help no sale con 0"
case "$out" in *Usage*) ;; *) fail "$name: --help no muestra el uso: [$out]" ;; esac
rc=0
"$WT" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "$name: sin subcomando: exit=$rc, esperado 2"
rc=0
"$WT" bogus >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "$name: subcomando desconocido: exit=$rc, esperado 2"
pass "$name"

name="new sin rama o con opción desconocida → exit 2 sin crear nada"
rc=0
(cd "$TMP/repo" && "$WT" new >/dev/null 2>&1) || rc=$?
[ "$rc" = 2 ] || fail "$name: sin rama: exit=$rc, esperado 2"
rc=0
(cd "$TMP/repo" && "$WT" new feature/bad-opt --bogus >/dev/null 2>&1) || rc=$?
[ "$rc" = 2 ] || fail "$name: opción desconocida: exit=$rc, esperado 2"
rc=0
(cd "$TMP/repo" && "$WT" new feature/bad-opt --base >/dev/null 2>&1) || rc=$?
[ "$rc" = 2 ] || fail "$name: --base sin valor: exit=$rc, esperado 2"
rc=0
(cd "$TMP/repo" && "$WT" new feature/bad-opt --base "" >/dev/null 2>&1) || rc=$?
[ "$rc" = 2 ] || fail "$name: --base vacío: exit=$rc, esperado 2"
[ -z "$(git -C "$TMP/repo" branch --list feature/bad-opt)" ] || fail "$name: se creó la rama"
[ ! -e "$HOME/.worktrees/acme/demo/feature-bad-opt" ] || fail "$name: se creó el destino"
pass "$name"

name="origin inalcanzable o sin rama por defecto → exit 1 con mensaje, sin crear nada"
git init -q --bare -b main "$TMP/empty.git"
git config --global "url.$TMP/missing.git.insteadOf" "git@github.com:acme/unreach.git"
git config --global "url.$TMP/empty.git.insteadOf" "git@github.com:acme/empty.git"
for r in unreach empty; do
  git init -q -b main "$TMP/r-$r"
  git -C "$TMP/r-$r" commit -q --allow-empty -m init
  git -C "$TMP/r-$r" remote add origin "git@github.com:acme/$r.git"
  rc=0
  err="$(cd "$TMP/r-$r" && "$WT" new "feature/$r" 2>&1)" || rc=$?
  [ "$rc" = 1 ] || fail "$name: $r: exit=$rc, esperado 1"
  case "$err" in *"th-wt: "*origin*) ;; *) fail "$name: $r: sin mensaje de th-wt sobre origin: [$err]" ;; esac
  [ -z "$(git -C "$TMP/r-$r" branch --list "feature/$r")" ] || fail "$name: $r: se creó la rama"
  [ ! -e "$HOME/.worktrees/acme/$r" ] || fail "$name: $r: se creó el destino"
done
pass "$name"

name="nombre de rama inválido → exit 2 antes de tocar la red"
# r-unreach tiene un origin inalcanzable: si hubiera red de por medio, saldría con 1.
for b in "bad..name" "foo bar"; do
  rc=0
  err="$(cd "$TMP/r-unreach" && "$WT" new "$b" 2>&1)" || rc=$?
  [ "$rc" = 2 ] || fail "$name: [$b]: exit=$rc, esperado 2"
  case "$err" in *"th-wt: "*"$b"*) ;; *) fail "$name: [$b]: sin mensaje con el nombre: [$err]" ;; esac
done
pass "$name"

name="fuera de un repo git → exit 4 con mensaje de repo"
mkdir "$TMP/plain"
rc=0
err="$(cd "$TMP/plain" && "$WT" new feature/nogit 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4"
case "$err" in *"not a git repository"*) ;; *) fail "$name: el mensaje no habla de repo git: [$err]" ;; esac
pass "$name"

name="new crea la rama sin upstream (no sigue a origin/<base>)"
(cd "$TMP/repo" && "$WT" new feature/notrack) || fail "$name: th-wt new falló"
[ -z "$(git -C "$TMP/repo" config --get "branch.feature/notrack.merge" || true)" ] || fail "$name: la rama tiene upstream"
pass "$name"

name="--base inexistente en origin → exit 4 con mensaje, sin crear nada"
for b in nope origin/main; do
  rc=0
  err="$(cd "$TMP/repo" && "$WT" new fix/nobase --base "$b" 2>&1)" || rc=$?
  [ "$rc" = 4 ] || fail "$name: --base $b: exit=$rc, esperado 4"
  case "$err" in *"th-wt: "*"$b"*) ;; *) fail "$name: --base $b: sin mensaje de th-wt con la base: [$err]" ;; esac
  [ -z "$(git -C "$TMP/repo" branch --list fix/nobase)" ] || fail "$name: --base $b: se creó la rama"
  [ ! -e "$HOME/.worktrees/acme/demo/fix-nobase" ] || fail "$name: --base $b: se creó el destino"
done
pass "$name"

name="conflicto de refs (conf con conf/x existente) → exit 1 con mensaje, sin crear nada"
git -C "$TMP/repo" branch conf/x
rc=0
err="$(cd "$TMP/repo" && "$WT" new conf 2>&1)" || rc=$?
[ "$rc" = 1 ] || fail "$name: exit=$rc, esperado 1"
case "$err" in *"th-wt: "*) ;; *) fail "$name: sin mensaje de th-wt: [$err]" ;; esac
[ -z "$(git -C "$TMP/repo" branch --list conf)" ] || fail "$name: se creó la rama"
[ ! -e "$HOME/.worktrees/acme/demo/conf" ] || fail "$name: se creó el destino"
pass "$name"
