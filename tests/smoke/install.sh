#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

INSTALL="$ROOT/install.sh"
KIT="$HOME/.local/share/th-worktools"

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

name="--link-here sin --yes muestra el plan y no crea nada"
reset_home
before="$(snap)"
run_install "$BOTH" --link-here
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
[ "$(snap)" = "$before" ] || fail "$name: cambió $HOME"
case "$out" in *"create $KIT -> $ROOT"*) ;; *) fail "$name: falta la línea de la ruta fija: [$out]" ;; esac
case "$out" in *"create $HOME/.claude/skills/th-worktree -> $KIT/skills/th-worktree"*) ;; *) fail "$name: falta la línea de Claude: [$out]" ;; esac
case "$out" in *"create $HOME/.gemini/config/skills/th-worktree -> $KIT/skills/th-worktree"*) ;; *) fail "$name: falta la línea de agy: [$out]" ;; esac
case "$out" in *"create $HOME/.local/bin/th-wt -> $KIT/skills/th-worktree/scripts/th-wt"*) ;; *) fail "$name: falta la línea de th-wt: [$out]" ;; esac
case "$out" in *"dry run, nothing changed"*) ;; *) fail "$name: falta el aviso de dry-run: [$out]" ;; esac
pass "$name"

name="--link-here --yes crea la ruta fija, el skill en Claude y agy y th-wt, todo a través de la ruta fija"
reset_home
run_install "$BOTH" --link-here --yes
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
[ "$(readlink "$HOME/.local/share/th-worktools")" = "$ROOT" ] || fail "$name: ruta fija no apunta al clon"
[ "$(readlink "$HOME/.claude/skills/th-worktree")" = "$HOME/.local/share/th-worktools/skills/th-worktree" ] || fail "$name: skill de Claude mal enlazado"
[ "$(readlink "$HOME/.gemini/config/skills/th-worktree")" = "$HOME/.local/share/th-worktools/skills/th-worktree" ] || fail "$name: skill de agy mal enlazado"
[ "$(readlink "$HOME/.local/bin/th-wt")" = "$HOME/.local/share/th-worktools/skills/th-worktree/scripts/th-wt" ] || fail "$name: th-wt mal enlazado"
[ -x "$HOME/.local/bin/th-wt" ] || fail "$name: th-wt no resuelve a un ejecutable"
case "$out" in *"done"*) ;; *) fail "$name: falta 'done': [$out]" ;; esac
pass "$name"

name="repetir la instalación deja todo ok y no cambia ningún enlace"
l1="$(find "$HOME" -mindepth 1 -type l -exec sh -c 'for f; do echo "$f -> $(readlink "$f")"; done' _ {} + | sort)"
run_install "$BOTH" --link-here --yes
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
printf '%s\n' "$out" | grep -qE '^(create|fix|skip) ' && fail "$name: hubo cambios en la repetición: [$out]"
case "$out" in *"ok     $HOME/.claude/skills/th-worktree"*) ;; *) fail "$name: falta la línea ok: [$out]" ;; esac
l2="$(find "$HOME" -mindepth 1 -type l -exec sh -c 'for f; do echo "$f -> $(readlink "$f")"; done' _ {} + | sort)"
[ "$l1" = "$l2" ] || fail "$name: cambiaron los enlaces"
pass "$name"

name="--agents claude enlaza solo Claude Code; la ruta fija y th-wt se instalan igual"
reset_home
run_install "$BOTH" --link-here --agents claude --yes
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
[ "$(readlink "$HOME/.claude/skills/th-worktree")" = "$HOME/.local/share/th-worktools/skills/th-worktree" ] || fail "$name: skill de Claude mal enlazado"
{ [ ! -e "$HOME/.gemini/config/skills/th-worktree" ] && [ ! -L "$HOME/.gemini/config/skills/th-worktree" ]; } || fail "$name: se enlazó agy"
[ "$(readlink "$HOME/.local/share/th-worktools")" = "$ROOT" ] || fail "$name: falta la ruta fija"
[ -L "$HOME/.local/bin/th-wt" ] || fail "$name: falta th-wt"
pass "$name"

name="por defecto, con solo agy en el PATH, enlaza solo Antigravity"
reset_home
ONLY="$TMP/onlyagy"
mkdir -p "$ONLY"
cp "$FAKE/agy" "$ONLY/agy"
run_install "$ONLY:/usr/bin:/bin" --link-here --yes
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
[ -L "$HOME/.gemini/config/skills/th-worktree" ] || fail "$name: falta el skill de agy"
[ ! -e "$HOME/.claude" ] || fail "$name: se creó ~/.claude"
pass "$name"

name="un symlink que apunta directo al clon se reapunta a la ruta fija"
reset_home
mkdir -p "$HOME/.claude/skills"
ln -s "$ROOT/skills/th-worktree" "$HOME/.claude/skills/th-worktree"
run_install "$BOTH" --link-here --yes
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
case "$out" in *"fix    $HOME/.claude/skills/th-worktree -> $HOME/.local/share/th-worktools/skills/th-worktree"*) ;; *) fail "$name: falta la línea fix: [$out]" ;; esac
[ "$(readlink "$HOME/.claude/skills/th-worktree")" = "$HOME/.local/share/th-worktools/skills/th-worktree" ] || fail "$name: no se reapuntó"
pass "$name"

name="un directorio que no es th-* en skills/ no se enlaza"
reset_home
mkdir -p "$TMP/kit"
cp "$ROOT/install.sh" "$TMP/kit/install.sh"
cp -R "$ROOT/skills" "$TMP/kit/skills"
mkdir -p "$TMP/kit/skills/system/scripts"
printf -- '---\nname: system\n---\n' >"$TMP/kit/skills/system/SKILL.md"
printf '#!/bin/sh\n' >"$TMP/kit/skills/system/scripts/foo"
chmod +x "$TMP/kit/skills/system/scripts/foo"
rc=0
out="$(PATH="$BOTH" "$TMP/kit/install.sh" --link-here --yes 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
[ "$(readlink "$HOME/.local/share/th-worktools")" = "$TMP/kit" ] || fail "$name: la ruta fija no apunta a la copia"
[ -L "$HOME/.claude/skills/th-worktree" ] || fail "$name: th-worktree no se enlazó"
{ [ ! -e "$HOME/.claude/skills/system" ] && [ ! -L "$HOME/.claude/skills/system" ]; } || fail "$name: system enlazado en Claude"
{ [ ! -e "$HOME/.gemini/config/skills/system" ] && [ ! -L "$HOME/.gemini/config/skills/system" ]; } || fail "$name: system enlazado en agy"
{ [ ! -e "$HOME/.local/bin/foo" ] && [ ! -L "$HOME/.local/bin/foo" ]; } || fail "$name: foo enlazado en bin"
pass "$name"

name="un symlink que pasa por la ruta fija aún inexistente es del kit: el dry-run dice fix y --yes lo corrige"
reset_home
mkdir -p "$HOME/.claude/skills"
ln -s "$HOME/.local/share/th-worktools/skills/th-worktree/" "$HOME/.claude/skills/th-worktree"
run_install "$BOTH" --link-here
[ "$rc" = 0 ] || fail "$name: dry-run exit=$rc, esperado 0: [$out]"
printf '%s\n' "$out" | grep -qF "fix    $HOME/.claude/skills/th-worktree -> $HOME/.local/share/th-worktools/skills/th-worktree" || fail "$name: falta la línea fix en el dry-run: [$out]"
run_install "$BOTH" --link-here --yes
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
[ "$(readlink "$HOME/.claude/skills/th-worktree")" = "$HOME/.local/share/th-worktools/skills/th-worktree" ] || fail "$name: no se reapuntó"
pass "$name"
