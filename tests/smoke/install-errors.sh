#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

INSTALL="$ROOT/install.sh"

# Agentes falsos: un claude/agy real del dev no debe filtrarse al PATH de los tests.
FAKE="$TMP/fakebin"
mkdir -p "$FAKE"
for a in claude agy; do
  printf '#!/bin/sh\nexit 0\n' >"$FAKE/$a"
  chmod +x "$FAKE/$a"
done
BOTH="$FAKE:/usr/bin:/bin"

reset_home() { rm -rf "$HOME"; mkdir -p "$HOME"; }
snap() { find "$HOME" -mindepth 1 | sort; }
# run_install <PATH> <args...>: deja el exit en $rc y stdout+stderr en $out
run_install() {
  local p="$1"
  shift
  rc=0
  out="$(PATH="$p" "$INSTALL" "$@" 2>&1)" || rc=$?
}

name="agente no soportado → exit 2 con mensaje, sin crear nada"
reset_home
before="$(snap)"
run_install "$BOTH" --agents codex --link-here --yes
[ "$rc" = 2 ] || fail "$name: exit=$rc, esperado 2: [$out]"
case "$out" in *"unsupported agent: codex (supported: claude, agy)"*) ;; *) fail "$name: mensaje inesperado: [$out]" ;; esac
[ "$(snap)" = "$before" ] || fail "$name: cambió $HOME"
pass "$name"

name="--agents agy sin agy en el PATH → exit 3 con mensaje, sin crear nada"
reset_home
before="$(snap)"
NOAGY="$TMP/onlyclaude"
mkdir -p "$NOAGY"
cp "$FAKE/claude" "$NOAGY/claude"
run_install "$NOAGY:/usr/bin:/bin" --agents agy --link-here --yes
[ "$rc" = 3 ] || fail "$name: exit=$rc, esperado 3: [$out]"
case "$out" in *"agent not found in PATH: agy"*) ;; *) fail "$name: mensaje inesperado: [$out]" ;; esac
[ "$(snap)" = "$before" ] || fail "$name: cambió $HOME"
pass "$name"

name="--agents sin valor o con lista vacía → exit 2, sin crear nada"
reset_home
before="$(snap)"
run_install "$BOTH" --yes --agents
[ "$rc" = 2 ] || fail "$name: (sin valor) exit=$rc, esperado 2: [$out]"
case "$out" in *"--agents needs a comma-separated list of agents"*) ;; *) fail "$name: (sin valor) mensaje inesperado: [$out]" ;; esac
for v in "" ","; do
  run_install "$BOTH" --yes --agents "$v"
  [ "$rc" = 2 ] || fail "$name: [$v] exit=$rc, esperado 2: [$out]"
  case "$out" in *"--agents needs a comma-separated list of agents"*) ;; *) fail "$name: [$v] mensaje inesperado: [$out]" ;; esac
done
[ "$(snap)" = "$before" ] || fail "$name: cambió $HOME"
pass "$name"

name="opción desconocida → exit 2 con el uso"
run_install "$BOTH" --nope
[ "$rc" = 2 ] || fail "$name: exit=$rc, esperado 2: [$out]"
case "$out" in *"unknown option: --nope"*"Usage: install.sh"*) ;; *) fail "$name: mensaje inesperado: [$out]" ;; esac
pass "$name"

name="sin --link-here y sin ruta fija → exit 4 que sugiere --link-here, sin crear nada"
reset_home
before="$(snap)"
run_install "$BOTH" --yes
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$out]"
case "$out" in *"kit path not found: $HOME/.local/share/th-worktools"*"--link-here"*) ;; *) fail "$name: mensaje inesperado: [$out]" ;; esac
[ "$(snap)" = "$before" ] || fail "$name: cambió $HOME"
pass "$name"

name="--link-here con la ruta fija apuntando a otro sitio → exit 4 'is not this clone', sin crear nada más"
reset_home
mkdir -p "$TMP/otherclone" "$HOME/.local/share"
ln -s "$TMP/otherclone" "$HOME/.local/share/th-worktools"
before="$(snap)"
run_install "$BOTH" --link-here --yes
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$out]"
case "$out" in *"kit path $HOME/.local/share/th-worktools is not this clone"*) ;; *) fail "$name: mensaje inesperado: [$out]" ;; esac
[ "$(snap)" = "$before" ] || fail "$name: cambió $HOME"
[ "$(readlink "$HOME/.local/share/th-worktools")" = "$TMP/otherclone" ] || fail "$name: se tocó la ruta fija"
pass "$name"

name="destinos ocupados por algo que no es del kit: no se tocan, se informan, el resto se instala y sale 4"
reset_home
mkdir -p "$HOME/.claude/skills" "$HOME/.gemini/config/skills/th-worktree" "$HOME/.local/bin" "$TMP/elsewhere"
echo mine >"$HOME/.claude/skills/th-worktree"
echo keep >"$HOME/.gemini/config/skills/th-worktree/marker"
ln -s "$TMP/elsewhere" "$HOME/.local/bin/th-wt"
run_install "$BOTH" --link-here --yes
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$out]"
[ "$(cat "$HOME/.claude/skills/th-worktree")" = "mine" ] || fail "$name: se tocó el archivo"
[ ! -L "$HOME/.claude/skills/th-worktree" ] || fail "$name: el archivo ahora es symlink"
{ [ -d "$HOME/.gemini/config/skills/th-worktree" ] && [ ! -L "$HOME/.gemini/config/skills/th-worktree" ]; } || fail "$name: se tocó el directorio"
[ "$(cat "$HOME/.gemini/config/skills/th-worktree/marker")" = "keep" ] || fail "$name: cambió el contenido del directorio"
[ "$(readlink "$HOME/.local/bin/th-wt")" = "$TMP/elsewhere" ] || fail "$name: se tocó el symlink"
case "$out" in *"skip   $HOME/.claude/skills/th-worktree"*) ;; *) fail "$name: falta skip del archivo: [$out]" ;; esac
case "$out" in *"skip   $HOME/.gemini/config/skills/th-worktree"*) ;; *) fail "$name: falta skip del directorio: [$out]" ;; esac
case "$out" in *"skip   $HOME/.local/bin/th-wt"*) ;; *) fail "$name: falta skip del symlink: [$out]" ;; esac
case "$out" in *"left 3 path(s) untouched: not part of the kit"*) ;; *) fail "$name: falta el resumen: [$out]" ;; esac
[ "$(readlink "$HOME/.local/share/th-worktools")" = "$ROOT" ] || fail "$name: no se creó la ruta fija"
pass "$name"
