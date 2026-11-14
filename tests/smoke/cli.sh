#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

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

name="new/checkout/list/pr/close/link con --help o -h → exit 0, uso en stdout, stderr vacío, también fuera de un repo, sin crear nada"
mkdir -p "$TMP/norepo"
for dir in "$TMP/repo" "$TMP/norepo"; do
  for sub in new checkout list pr close link; do
    for flag in --help -h; do
      rc=0
      out="$(cd "$dir" && "$WT" "$sub" "$flag" 2>"$TMP/help.err")" || rc=$?
      [ "$rc" = 0 ] || fail "$name: $sub $flag en $dir: exit=$rc, esperado 0"
      case "$out" in *Usage*) ;; *) fail "$name: $sub $flag en $dir: sin uso en stdout: [$out]" ;; esac
      [ ! -s "$TMP/help.err" ] || fail "$name: $sub $flag en $dir: stderr no vacío"
    done
  done
done
rc=0
out="$(cd "$TMP/repo" && "$WT" new feature/help-arg --help 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: new <rama> --help: exit=$rc, esperado 0"
[ -z "$(git -C "$TMP/repo" branch --list feature/help-arg)" ] || fail "$name: se creó la rama"
[ ! -e "$HOME/.worktrees" ] || fail "$name: se creó algo bajo ~/.worktrees"
rc=0
out="$(cd "$TMP/repo" && "$WT" checkout feature/help-arg --help 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: checkout <rama> --help: exit=$rc, esperado 0"
[ -z "$(git -C "$TMP/repo" branch --list feature/help-arg)" ] || fail "$name: se creó la rama"
[ ! -e "$HOME/.worktrees" ] || fail "$name: se creó algo bajo ~/.worktrees"
pass "$name"

name="errores de uso nombran el argumento erróneo (stderr) y salen con 2"
expect_usage_error() { # <fragmento esperado> <args...>
  local want="$1" err rc=0
  shift
  err="$(cd "$TMP/repo" && "$WT" "$@" 2>&1 >/dev/null)" || rc=$?
  [ "$rc" = 2 ] || fail "$name: $*: exit=$rc, esperado 2"
  case "$err" in "th-wt: $want"*) ;; *) fail "$name: $*: esperado 'th-wt: $want', stderr: [$err]" ;; esac
  case "$err" in *Usage*) ;; *) fail "$name: $*: stderr sin uso" ;; esac
}
expect_usage_error "unknown subcommand: bogus" bogus
expect_usage_error "missing subcommand"
expect_usage_error "missing <branch>" new
expect_usage_error "expected <branch> first, got option: --json" new --json
expect_usage_error "unknown option: --bogus" new feature/x --bogus
expect_usage_error "unexpected argument: extra" new feature/x extra
expect_usage_error "--base requires" new feature/x --base
expect_usage_error "--base requires" new feature/x --base ""
expect_usage_error "missing <branch>" checkout
expect_usage_error "expected <branch> first, got option: --remote" checkout --remote
expect_usage_error "unknown option: --bogus" checkout feature/x --bogus
expect_usage_error "unexpected argument: extra" checkout feature/x extra
expect_usage_error "unknown option: --bogus" list --bogus
expect_usage_error "unexpected argument: extra" list extra
expect_usage_error "missing <branch>" close
expect_usage_error "unknown option: --bogus" close feature/x --bogus
expect_usage_error "unexpected argument: other" close feature/x other
expect_usage_error "missing <branch>" link
expect_usage_error "expected <branch> first, got option: --json" link --json
expect_usage_error "unknown option: --bogus" link feature/x --bogus
expect_usage_error "unexpected argument: extra" link feature/x extra
expect_usage_error "unknown option: --bogus" new feature/x --bogus --help
expect_usage_error "unexpected argument: b" close a b --help
expect_usage_error "unexpected argument: extra" list extra --help
rc=0
(cd "$TMP/repo" && "$WT" new feature/x --base --help >/dev/null 2>&1) || rc=$?
[ "$rc" != 0 ] || fail "$name: new --base --help: --help se tomó como ayuda, exit=0"
pass "$name"

name="th-wt enlazado en el PATH (symlink a la ruta del kit, que a su vez es un symlink) → misma salida y código que con la ruta completa, desde el repo y desde un worktree; th-wt --help muestra el uso"
# Instalación documentada: ~/.local/share/th-worktools -> kit, ~/.local/bin/th-wt -> .../scripts/th-wt
ln -s "$ROOT" "$TMP/share"
mkdir "$TMP/bin"
ln -s "$TMP/share/skills/th-worktree/scripts/th-wt" "$TMP/bin/th-wt"
(cd "$TMP/repo" && "$WT" new feature/terminal >/dev/null 2>&1) || fail "$name: th-wt new falló"
inside="$HOME/.worktrees/acme/demo/feature-terminal"
same_as_full_path() { # <dir> <args...>: stdout y exit de `th-wt` por nombre == ruta completa
  local dir="$1" want got want_rc=0 got_rc=0
  shift
  want="$(cd "$dir" && "$WT" "$@" 2>/dev/null)" || want_rc=$?
  got="$(cd "$dir" && PATH="$TMP/bin:$PATH" th-wt "$@" 2>/dev/null)" || got_rc=$?
  [ "$got_rc" = "$want_rc" ] || fail "$name: $* en $dir: exit=$got_rc, con la ruta completa $want_rc"
  [ "$got" = "$want" ] || fail "$name: $* en $dir: stdout distinto: [$got] vs [$want]"
}
out="$(PATH="$TMP/bin:$PATH" th-wt --help)" || fail "$name: th-wt --help no sale con 0"
case "$out" in *Usage*) ;; *) fail "$name: th-wt --help no muestra el uso: [$out]" ;; esac
for dir in "$TMP/repo" "$inside"; do
  same_as_full_path "$dir" --help
  same_as_full_path "$dir" list
  same_as_full_path "$dir" list --json
  same_as_full_path "$dir" bogus
  same_as_full_path "$dir" close feature/inexistente
done
out="$(cd "$TMP/repo" && PATH="$TMP/bin:$PATH" th-wt list --json)"
[ "$(printf '%s' "$out" | jq -r '.worktrees[] | select(.branch == "feature/terminal") | .path')" = "$inside" ] || fail "$name: list --json por nombre no muestra el worktree: [$out]"
out="$(cd "$TMP/repo" && PATH="$TMP/bin:$PATH" th-wt list)"
case "$out" in *"$inside"*) ;; *) fail "$name: list por nombre no muestra el worktree en stdout: [$out]" ;; esac
pass "$name"
