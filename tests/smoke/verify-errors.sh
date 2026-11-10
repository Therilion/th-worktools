#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

INSTALL="$ROOT/install.sh"
VERIFY="$ROOT/verify.sh"
KIT="$HOME/.local/share/th-worktools"
SUGGEST="run install.sh --yes (install.sh --link-here --yes from the clone if the kit path is missing)"

# Agentes falsos: un claude/agy real del dev no debe filtrarse al PATH de los tests.
FAKE="$TMP/fakebin"
mkdir -p "$FAKE"
for a in claude agy; do
  printf '#!/bin/sh\nexit 0\n' >"$FAKE/$a"
  chmod +x "$FAKE/$a"
done
BOTH="$FAKE:/usr/bin:/bin"
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
# has <línea>: la salida contiene esa línea exacta
has() { printf '%s\n' "$out" | grep -qxF "$1"; }
installed() {
  reset_home
  run_install "$BOTH" --link-here --yes
  [ "$rc" = 0 ] || fail "$name: la instalación salió con $rc: [$out]"
}

name="ruta fija ausente o rota: sale con su causa y la sugerencia, sigue comprobando y termina con 4"
installed
mkdir -p "$TMP/otro"
rm "$KIT"
run_verify "$BINP"
[ "$rc" = 4 ] || fail "$name: (ausente) exit=$rc, esperado 4: [$out]"
has "fail   $KIT (missing)" || fail "$name: (ausente) falta la causa: [$out]"
has "fail   $HOME/.claude/skills/th-worktree (broken symlink)" || fail "$name: (ausente) no siguió con el skill: [$out]"
has "ok     git" || fail "$name: (ausente) no siguió con git: [$out]"
has "verify.sh: 4 problem(s) found; $SUGGEST" || fail "$name: (ausente) falta la sugerencia: [$out]"
ln -s "$TMP/no-existe" "$KIT"
run_verify "$BINP"
[ "$rc" = 4 ] || fail "$name: (rota) exit=$rc, esperado 4: [$out]"
has "fail   $KIT (broken symlink)" || fail "$name: (rota) falta la causa: [$out]"
rm "$KIT"
ln -s "$TMP/otro" "$KIT"
run_verify "$BINP"
[ "$rc" = 4 ] || fail "$name: (fuera) exit=$rc, esperado 4: [$out]"
has "fail   $KIT (points outside the kit: $TMP/otro)" || fail "$name: (fuera) falta la causa: [$out]"
pass "$name"

name="skill ausente, roto o fuera del kit: cada caso con su causa, el resto sigue en ok, sale con 4"
installed
mkdir -p "$TMP/otro"
rm "$HOME/.claude/skills/th-worktree"
ln -sfn "$TMP/no-existe" "$HOME/.gemini/config/skills/th-worktree"
run_verify "$BINP"
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$out]"
has "fail   $HOME/.claude/skills/th-worktree (missing)" || fail "$name: falta (missing): [$out]"
has "fail   $HOME/.gemini/config/skills/th-worktree (broken symlink)" || fail "$name: falta (broken symlink): [$out]"
has "ok     $KIT" || fail "$name: la ruta fija no sigue en ok: [$out]"
has "ok     $HOME/.local/bin/th-wt" || fail "$name: th-wt no sigue en ok: [$out]"
has "verify.sh: 2 problem(s) found; $SUGGEST" || fail "$name: falta la sugerencia: [$out]"
ln -sfn "$TMP/otro" "$HOME/.claude/skills/th-worktree"
rm "$HOME/.gemini/config/skills/th-worktree"
mkdir "$HOME/.gemini/config/skills/th-worktree"
run_verify "$BINP"
[ "$rc" = 4 ] || fail "$name: (2) exit=$rc, esperado 4: [$out]"
has "fail   $HOME/.claude/skills/th-worktree (points outside the kit: $TMP/otro)" || fail "$name: falta (points outside): [$out]"
has "fail   $HOME/.gemini/config/skills/th-worktree (not a symlink)" || fail "$name: falta (not a symlink): [$out]"
pass "$name"

name="entrypoint ausente, roto o fuera del kit: cada caso con su causa, sale con 4"
installed
mkdir -p "$TMP/otro"
th="$HOME/.local/bin/th-wt"
rm "$th"
run_verify "$BINP"
[ "$rc" = 4 ] || fail "$name: (ausente) exit=$rc, esperado 4: [$out]"
has "fail   $th (missing)" || fail "$name: falta (missing): [$out]"
has "ok     $HOME/.claude/skills/th-worktree" || fail "$name: el skill no sigue en ok: [$out]"
has "verify.sh: 1 problem(s) found; $SUGGEST" || fail "$name: falta la sugerencia: [$out]"
ln -s "$TMP/no-existe" "$th"
run_verify "$BINP"
[ "$rc" = 4 ] || fail "$name: (roto) exit=$rc, esperado 4: [$out]"
has "fail   $th (broken symlink)" || fail "$name: falta (broken symlink): [$out]"
rm "$th"
printf '#!/bin/sh\n' >"$TMP/otro/th-wt"
ln -s "$TMP/otro/th-wt" "$th"
run_verify "$BINP"
[ "$rc" = 4 ] || fail "$name: (fuera) exit=$rc, esperado 4: [$out]"
has "fail   $th (points outside the kit: $TMP/otro/th-wt)" || fail "$name: falta (points outside): [$out]"
rm "$th"
printf '#!/bin/sh\n' >"$th"
run_verify "$BINP"
[ "$rc" = 4 ] || fail "$name: (archivo) exit=$rc, esperado 4: [$out]"
has "fail   $th (not a symlink)" || fail "$name: falta (not a symlink): [$out]"
pass "$name"

name="name del SKILL.md distinto de su carpeta (en una copia del kit): sale con 4"
reset_home
mkdir -p "$TMP/kit"
cp "$ROOT/install.sh" "$ROOT/lib.sh" "$ROOT/verify.sh" "$TMP/kit/"
cp -R "$ROOT/skills" "$TMP/kit/skills"
rc=0
out="$(PATH="$BOTH" "$TMP/kit/install.sh" --link-here --yes 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: la instalación salió con $rc: [$out]"
sed 's/^name: th-worktree$/name: otro/' "$TMP/kit/skills/th-worktree/SKILL.md" >"$TMP/skill.md"
cp "$TMP/skill.md" "$TMP/kit/skills/th-worktree/SKILL.md"
rc=0
out="$(PATH="$BINP" "$TMP/kit/verify.sh" 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$out]"
has "fail   $HOME/.claude/skills/th-worktree (name 'otro' does not match its folder)" || fail "$name: falta la causa en Claude: [$out]"
has "fail   $HOME/.gemini/config/skills/th-worktree (name 'otro' does not match its folder)" || fail "$name: falta la causa en agy: [$out]"
has "ok     $HOME/.local/bin/th-wt" || fail "$name: th-wt no sigue en ok: [$out]"
pass "$name"

name="sin jq en el PATH: nombra jq y sale con 3, aunque además haya un enlace roto"
installed
NOJQ="$TMP/nojq"
mkdir -p "$NOJQ"
for f in /usr/bin/* /bin/*; do
  b="${f##*/}"
  if [ "$b" != jq ] && [ ! -e "$NOJQ/$b" ] && [ ! -L "$NOJQ/$b" ]; then ln -s "$f" "$NOJQ/$b"; fi
done
rm "$HOME/.local/bin/th-wt"
ln -s "$TMP/no-existe" "$HOME/.local/bin/th-wt"
run_verify "$FAKE:$HOME/.local/bin:$NOJQ"
[ "$rc" = 3 ] || fail "$name: exit=$rc, esperado 3: [$out]"
has "fail   jq (not found in PATH)" || fail "$name: falta jq: [$out]"
has "ok     git" || fail "$name: git debería seguir en ok: [$out]"
has "fail   $HOME/.local/bin/th-wt (broken symlink)" || fail "$name: falta el enlace roto: [$out]"
has "verify.sh: 1 problem(s) found; $SUGGEST" || fail "$name: falta el resumen: [$out]"
pass "$name"

name="agente no soportado en --agents: sale con 2 sin ninguna línea ok"
installed
run_verify "$BINP" --agents codex
[ "$rc" = 2 ] || fail "$name: exit=$rc, esperado 2: [$out]"
case "$out" in *"unsupported agent: codex (supported: claude, agy)"*) ;; *) fail "$name: mensaje inesperado: [$out]" ;; esac
if printf '%s\n' "$out" | grep -q '^ok '; then fail "$name: comprobó algo: [$out]"; fi
pass "$name"
