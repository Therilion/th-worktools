#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

INSTALL="$ROOT/install.sh"
VERIFY="$ROOT/verify.sh"

# Agentes falsos: un claude/agy real del dev no debe filtrarse al PATH de los tests.
FAKE="$TMP/fakebin"
mkdir -p "$FAKE"
for a in claude agy; do
  printf '#!/bin/sh\nexit 0\n' >"$FAKE/$a"
  chmod +x "$FAKE/$a"
done
BOTH="$FAKE:/usr/bin:/bin"
# con ~/.local/bin en el PATH, verify.sh no debe avisar
BINP="$FAKE:$HOME/.local/bin:/usr/bin:/bin"

reset_home() { rm -rf "$HOME"; mkdir -p "$HOME"; }
snap() { find "$HOME" -mindepth 1 | sort; }
# run_install <PATH> <args...> y run_verify <PATH> <args...>: dejan el exit en $rc y stdout+stderr en $out
run_install() {
  local p="$1"
  shift
  rc=0
  out="$(PATH="$p" "$INSTALL" "$@" 2>&1)" || rc=$?
}
run_verify() {
  local p="$1"
  shift
  rc=0
  out="$(PATH="$p" "$VERIFY" "$@" 2>&1)" || rc=$?
}

name="tras install.sh --link-here --yes, verify.sh da ok en la ruta fija, el skill en Claude y agy, th-wt, git y jq, sale con 0 y no cambia HOME"
reset_home
run_install "$BOTH" --link-here --yes
[ "$rc" = 0 ] || fail "$name: la instalación salió con $rc: [$out]"
before="$(snap)"
run_verify "$BINP"
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
expected="$(printf '%s\n' \
  "ok     $HOME/.local/share/th-worktools" \
  "ok     $HOME/.claude/skills/th-worktree" \
  "ok     $HOME/.gemini/config/skills/th-worktree" \
  "ok     $HOME/.local/bin/th-wt" \
  "ok     git" \
  "ok     jq" \
  "verify.sh: all ok")"
[ "$out" = "$expected" ] || fail "$name: salida inesperada: [$out]"
[ "$(snap)" = "$before" ] || fail "$name: cambió $HOME"
pass "$name"

name="con --agents claude solo comprueba Claude Code"
reset_home
run_install "$BOTH" --link-here --agents claude --yes
[ "$rc" = 0 ] || fail "$name: la instalación salió con $rc: [$out]"
run_verify "$BINP" --agents claude
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
case "$out" in *"ok     $HOME/.claude/skills/th-worktree"*) ;; *) fail "$name: falta la línea de Claude: [$out]" ;; esac
case "$out" in *".gemini"*) fail "$name: comprobó agy: [$out]" ;; esac
case "$out" in *"all ok"*) ;; *) fail "$name: falta 'all ok': [$out]" ;; esac
pass "$name"

name="sin --agents, con solo agy en el PATH, comprueba solo Antigravity"
reset_home
ONLY="$TMP/onlyagy"
mkdir -p "$ONLY"
cp "$FAKE/agy" "$ONLY/agy"
run_install "$ONLY:/usr/bin:/bin" --link-here --yes
[ "$rc" = 0 ] || fail "$name: la instalación salió con $rc: [$out]"
run_verify "$ONLY:$HOME/.local/bin:/usr/bin:/bin"
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
case "$out" in *"ok     $HOME/.gemini/config/skills/th-worktree"*) ;; *) fail "$name: falta la línea de agy: [$out]" ;; esac
case "$out" in *".claude"*) fail "$name: comprobó Claude: [$out]" ;; esac
pass "$name"

name="un enlace directo al clon, sin pasar por la ruta fija, da ok"
reset_home
run_install "$BOTH" --link-here --yes
[ "$rc" = 0 ] || fail "$name: la instalación salió con $rc: [$out]"
ln -sfn "$ROOT/skills/th-worktree" "$HOME/.claude/skills/th-worktree"
run_verify "$BINP"
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
case "$out" in *"ok     $HOME/.claude/skills/th-worktree"*) ;; *) fail "$name: falta la línea ok de Claude: [$out]" ;; esac
pass "$name"

name="con ~/.local/bin fuera del PATH avisa y sale con 0"
reset_home
run_install "$BOTH" --link-here --yes
[ "$rc" = 0 ] || fail "$name: la instalación salió con $rc: [$out]"
run_verify "$BOTH"
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
case "$out" in *"warning: $HOME/.local/bin is not in PATH; th-wt will not run from the terminal"*) ;; *) fail "$name: falta el aviso: [$out]" ;; esac
case "$out" in *"all ok"*) ;; *) fail "$name: falta 'all ok': [$out]" ;; esac
pass "$name"

name="con el kit clonado como carpeta real en la ruta fija, verify.sh da ok y sale con 0"
reset_home
KIT="$HOME/.local/share/th-worktools"
mkdir -p "$KIT"
cp "$ROOT/install.sh" "$ROOT/lib.sh" "$ROOT/verify.sh" "$KIT/"
cp -R "$ROOT/skills" "$KIT/skills"
rc=0
out="$(PATH="$BOTH" "$KIT/install.sh" --yes 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: la instalación salió con $rc: [$out]"
rc=0
out="$(PATH="$BINP" "$KIT/verify.sh" 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
case "$out" in *"ok     $KIT"*"all ok"*) ;; *) fail "$name: falta ok en la ruta fija o 'all ok': [$out]" ;; esac
pass "$name"
