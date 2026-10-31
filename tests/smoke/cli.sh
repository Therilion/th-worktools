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

name="new/list/close con --help o -h → exit 0, uso en stdout, stderr vacío, también fuera de un repo, sin crear nada"
mkdir -p "$TMP/norepo"
for dir in "$TMP/repo" "$TMP/norepo"; do
  for sub in new list close; do
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
expect_usage_error "unknown option: --bogus" list --bogus
expect_usage_error "unexpected argument: extra" list extra
expect_usage_error "missing <branch>" close
expect_usage_error "unknown option: --bogus" close feature/x --bogus
expect_usage_error "unexpected argument: other" close feature/x other
expect_usage_error "unknown option: --bogus" new feature/x --bogus --help
expect_usage_error "unexpected argument: b" close a b --help
expect_usage_error "unexpected argument: extra" list extra --help
rc=0
(cd "$TMP/repo" && "$WT" new feature/x --base --help >/dev/null 2>&1) || rc=$?
[ "$rc" != 0 ] || fail "$name: new --base --help: --help se tomó como ayuda, exit=0"
pass "$name"
