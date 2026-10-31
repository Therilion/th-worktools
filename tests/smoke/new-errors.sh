#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

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

git clone -q "$REMOTE_URL" "$TMP/other"

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

name="ls-remote --heads falla tras el --symref → exit 4 \"cannot read origin\", sin crear nada"
# git falso: solo la consulta de ramas de origin falla; todo lo demás va al git real.
shim="$TMP/bin-lsremote-falla"
mkdir -p "$shim"
cat >"$shim/git" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = ls-remote ] && [ "\${2:-}" = --heads ]; then echo "fatal: simulated failure" >&2; exit 128; fi
exec "$(command -v git)" "\$@"
EOF
chmod +x "$shim/git"
rc=0
err="$(cd "$TMP/repo" && PATH="$shim:$PATH" "$WT" new feature/lsfail 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4"
case "$err" in *"cannot read origin"*) ;; *) fail "$name: el mensaje no es 'cannot read origin': [$err]" ;; esac
[ -z "$(git -C "$TMP/repo" branch --list feature/lsfail)" ] || fail "$name: se creó la rama"
[ ! -e "$HOME/.worktrees/acme/demo/feature-lsfail" ] || fail "$name: se creó el destino"
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

name="origin inalcanzable o sin rama por defecto → exit 4 con mensaje, sin crear nada"
git init -q --bare -b main "$TMP/empty.git"
git config --global "url.$TMP/missing.git.insteadOf" "git@github.com:acme/unreach.git"
git config --global "url.$TMP/empty.git.insteadOf" "git@github.com:acme/empty.git"
for r in unreach empty; do
  want="cannot read origin"
  [ "$r" != empty ] || want="cannot determine origin's default branch"
  git init -q -b main "$TMP/r-$r"
  git -C "$TMP/r-$r" commit -q --allow-empty -m init
  git -C "$TMP/r-$r" remote add origin "git@github.com:acme/$r.git"
  rc=0
  err="$(cd "$TMP/r-$r" && "$WT" new "feature/$r" 2>&1)" || rc=$?
  [ "$rc" = 4 ] || fail "$name: $r: exit=$rc, esperado 4"
  case "$err" in *"th-wt: $want"*) ;; *) fail "$name: $r: esperaba '$want': [$err]" ;; esac
  [ -z "$(git -C "$TMP/r-$r" branch --list "feature/$r")" ] || fail "$name: $r: se creó la rama"
  [ ! -e "$HOME/.worktrees/acme/$r" ] || fail "$name: $r: se creó el destino"
done
pass "$name"

name="nombre de rama inválido → exit 2 antes de tocar la red"
# r-unreach tiene un origin inalcanzable: si hubiera red de por medio, saldría con 4.
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

name="origin con forma no soportada → exit 4 sin crear nada; subgrupos de GitLab sí"
# Hosts .invalid: nunca resuelven, así que el test no toca la red.
git init -q -b main "$TMP/r-bad"
git -C "$TMP/r-bad" commit -q --allow-empty -m init
git -C "$TMP/r-bad" remote add origin placeholder
for u in "git@example.invalid:../../x.git" "ssh://git@example.invalid/acme/demo.git" "https://example.invalid/acme/demo/"; do
  git -C "$TMP/r-bad" config remote.origin.url "$u"
  rc=0
  err="$(cd "$TMP/r-bad" && "$WT" new feature/bad-url 2>&1)" || rc=$?
  [ "$rc" = 4 ] || fail "$name: [$u]: exit=$rc, esperado 4"
  case "$err" in *"th-wt: "*"$u"*) ;; *) fail "$name: [$u]: sin mensaje con la URL: [$err]" ;; esac
  [ -z "$(git -C "$TMP/r-bad" branch --list feature/bad-url)" ] || fail "$name: [$u]: se creó la rama"
done
[ ! -e "$TMP/x" ] || fail "$name: se escribió fuera de ~/.worktrees"
git config --global --add "url.$TMP/origin.git.insteadOf" "git@gitlab.com:group/sub/repo.git"
git clone -q "$TMP/origin.git" "$TMP/r-gl"
git -C "$TMP/r-gl" remote set-url origin "git@gitlab.com:group/sub/repo.git"
(cd "$TMP/r-gl" && "$WT" new feature/gl) || fail "$name: GitLab con subgrupos falló"
[ -d "$HOME/.worktrees/group/sub/repo/feature-gl" ] || fail "$name: no existe el worktree en group/sub/repo"
pass "$name"

name="--base con expresión de revisión (main~1, main^, main@{1}) → exit 2 sin crear nada"
for b in "main~1" "main^" "main@{1}"; do
  rc=0
  err="$(cd "$TMP/repo" && "$WT" new fix/badbase --base "$b" 2>&1)" || rc=$?
  [ "$rc" = 2 ] || fail "$name: --base $b: exit=$rc, esperado 2"
  case "$err" in *"th-wt: "*"$b"*) ;; *) fail "$name: --base $b: sin mensaje de th-wt con la base: [$err]" ;; esac
  [ -z "$(git -C "$TMP/repo" branch --list fix/badbase)" ] || fail "$name: --base $b: se creó la rama"
  [ ! -e "$HOME/.worktrees/acme/demo/fix-badbase" ] || fail "$name: --base $b: se creó el destino"
done
pass "$name"
