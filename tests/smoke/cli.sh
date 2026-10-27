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
