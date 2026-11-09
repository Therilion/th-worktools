#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

git -C "$TMP/repo" remote set-head origin main >/dev/null

# codegraph falso: anota "$*" en $TMP/cg.calls y CODEGRAPH_TELEMETRY / CODEGRAPH_NO_UPDATE_CHECK en $TMP/cg.env; uninit borra <ruta>/.codegraph. FAKE_CG_FAIL=1 sale con 1 sin borrar nada.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/codegraph" <<EOF2
#!/usr/bin/env bash
echo "\$*" >> "$TMP/cg.calls"
echo "\${CODEGRAPH_TELEMETRY:-unset} \${CODEGRAPH_NO_UPDATE_CHECK:-unset}" >> "$TMP/cg.env"
[ -z "\${FAKE_CG_FAIL:-}" ] || exit 1
if [ "\${1:-}" = uninit ]; then rm -rf "\${3:?}/.codegraph"; fi
EOF2
chmod +x "$TMP/bin/codegraph"
: > "$TMP/cg.calls"

# Imita lo que deja codegraph 1.6.2 en el worktree $1: .gitignore propio y la base de datos.
index_wt() {
  mkdir -p "$1/.codegraph"
  printf '*\n!.gitignore\n' > "$1/.codegraph/.gitignore"
  echo db > "$1/.codegraph/codegraph.db"
}

name="list, en texto y en JSON, muestra limpio un worktree que solo tiene .codegraph/; un archivo real sin trackear al lado sí lo ensucia"
(cd "$TMP/repo" && "$WT" new feature/cg) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-cg"
index_wt "$dest"
out="$(cd "$TMP/repo" && "$WT" list 2>&1)" || fail "$name: th-wt list falló: [$out]"
line="$(printf '%s\n' "$out" | grep -F "feature/cg")" || fail "$name: no aparece la rama: [$out]"
case "$line" in *clean*) ;; *) fail "$name: la línea no dice clean: [$line]" ;; esac
case "$line" in *dirty*) fail "$name: la línea dice dirty: [$line]" ;; esac
out="$(cd "$TMP/repo" && "$WT" list --json 2>/dev/null)" || fail "$name: th-wt list --json falló"
[ "$(jq -r '.worktrees[] | select(.branch == "feature/cg") | .dirty' <<<"$out")" = false ] || fail "$name: dirty != false: [$out]"
echo nuevo > "$dest/real.txt"
out="$(cd "$TMP/repo" && "$WT" list --json 2>/dev/null)" || fail "$name: th-wt list --json falló"
[ "$(jq -r '.worktrees[] | select(.branch == "feature/cg") | .dirty' <<<"$out")" = true ] || fail "$name: con real.txt dirty != true: [$out]"
pass "$name"

name="close --yes de un worktree indexado y limpio llama a codegraph uninit -f, lo elimina sin --force y borra la rama; el dry-run no muestra .codegraph entre los ignorados"
(cd "$TMP/repo" && "$WT" new feature/idx) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-idx"
index_wt "$dest"
out="$(cd "$TMP/repo" && "$WT" close feature/idx 2>&1)" || fail "$name: dry-run falló: [$out]"
case "$out" in *codegraph*) fail "$name: el dry-run menciona codegraph: [$out]" ;; esac
printf '%s\n' "$out" | grep -qE 'ignored: +none' || fail "$name: ignored != none: [$out]"
out="$(cd "$TMP/repo" && "$WT" close feature/idx --json 2>/dev/null)" || fail "$name: dry-run --json falló"
[ "$(jq -c .ignored <<<"$out")" = '[]' ] || fail "$name: ignored=[$(jq -c .ignored <<<"$out")]"
[ -d "$dest/.codegraph" ] || fail "$name: el dry-run borró .codegraph"
[ ! -s "$TMP/cg.calls" ] || fail "$name: el dry-run llamó a codegraph: [$(cat "$TMP/cg.calls")]"
: > "$TMP/cg.env"
rc=0
out="$(cd "$TMP/repo" && PATH="$TMP/bin:$PATH" "$WT" close feature/idx --yes 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
[ "$(cat "$TMP/cg.calls")" = "uninit -f $dest" ] || fail "$name: llamadas=[$(cat "$TMP/cg.calls")]"
[ "$(cat "$TMP/cg.env")" = "0 1" ] || fail "$name: telemetría y comprobación de updates sin desactivar: env=[$(cat "$TMP/cg.env")]"
[ ! -e "$dest" ] || fail "$name: sigue el directorio"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/idx && fail "$name: sigue la rama"
pass "$name"

name="close --yes con .codegraph/ y sin codegraph en PATH elimina el worktree igualmente"
(cd "$TMP/repo" && "$WT" new feature/nocg) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-nocg"
index_wt "$dest"
# PATH mínimo: solo las herramientas que usa el kit, sin codegraph
mkdir -p "$TMP/minbin"
for t in git jq bash env dirname cat sed awk grep tr find rmdir rm mkdir head tail sort uniq mktemp date wc cut basename readlink; do
  p="$(command -v "$t" 2>/dev/null || true)"
  [ -z "$p" ] || ln -sf "$p" "$TMP/minbin/$t"
done
: > "$TMP/cg.calls"
rc=0
out="$(cd "$TMP/repo" && PATH="$TMP/minbin" "$WT" close feature/nocg --yes 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
[ ! -e "$dest" ] || fail "$name: sigue el directorio"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/nocg && fail "$name: sigue la rama"
case "$out" in *warning*) fail "$name: hay aviso sin que uninit fallara: [$out]" ;; esac
pass "$name"

name="close --yes con codegraph uninit fallando avisa con el mensaje exacto y elimina el worktree igualmente"
(cd "$TMP/repo" && "$WT" new feature/cgfail) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-cgfail"
index_wt "$dest"
: > "$TMP/cg.calls"
rc=0
out="$(cd "$TMP/repo" && PATH="$TMP/bin:$PATH" FAKE_CG_FAIL=1 "$WT" close feature/cgfail --yes 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
[ "$(cat "$TMP/cg.calls")" = "uninit -f $dest" ] || fail "$name: llamadas=[$(cat "$TMP/cg.calls")]"
printf '%s\n' "$out" | grep -qxF "th-wt: warning: codegraph uninit failed in $dest; removing .codegraph/" || fail "$name: falta el aviso exacto: [$out]"
[ ! -e "$dest" ] || fail "$name: sigue el directorio"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/cgfail && fail "$name: sigue la rama"
pass "$name"

# A partir de aquí main versiona .codegraph/.gitignore (el propio de codegraph: invita a commitearlo).
mkdir -p "$TMP/repo/.codegraph"
printf '*\n!.gitignore\n' > "$TMP/repo/.codegraph/.gitignore"
git -C "$TMP/repo" add .codegraph/.gitignore
git -C "$TMP/repo" commit -q -m "codegraph gitignore"
git -C "$TMP/repo" push -q origin main

name="con .codegraph/.gitignore versionado, list lo muestra limpio con la base de datos ignorada y close --yes lo elimina sin --force y sin llamar a codegraph uninit"
(cd "$TMP/repo" && "$WT" new feature/trk) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-trk"
[ -f "$dest/.codegraph/.gitignore" ] || fail "$name: el worktree no trae el .gitignore versionado"
echo db > "$dest/.codegraph/codegraph.db"
out="$(cd "$TMP/repo" && "$WT" list --json 2>/dev/null)" || fail "$name: th-wt list --json falló"
[ "$(jq -r '.worktrees[] | select(.branch == "feature/trk") | .dirty' <<<"$out")" = false ] || fail "$name: dirty != false: [$out]"
out="$(cd "$TMP/repo" && "$WT" list 2>&1)" || fail "$name: th-wt list falló"
line="$(printf '%s\n' "$out" | grep -F "feature/trk")" || fail "$name: no aparece la rama: [$out]"
case "$line" in *clean*) ;; *) fail "$name: la línea no dice clean: [$line]" ;; esac
: > "$TMP/cg.calls"
rc=0
out="$(cd "$TMP/repo" && PATH="$TMP/bin:$PATH" "$WT" close feature/trk --yes 2>&1)" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$out]"
[ ! -s "$TMP/cg.calls" ] || fail "$name: se llamó a codegraph: [$(cat "$TMP/cg.calls")]"
[ ! -e "$dest" ] || fail "$name: sigue el directorio"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/trk && fail "$name: sigue la rama"
pass "$name"

name="modificar o borrar el .codegraph/.gitignore versionado ensucia el worktree: list dice dirty y close sin --force sale con 4 y lo conserva todo"
(cd "$TMP/repo" && "$WT" new feature/trk-dirty) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-trk-dirty"
echo db > "$dest/.codegraph/codegraph.db"
: > "$TMP/cg.calls"
for change in modificar borrar; do
  git -C "$dest" checkout -q -- .codegraph/.gitignore
  if [ "$change" = modificar ]; then echo "# local" >> "$dest/.codegraph/.gitignore"; else rm "$dest/.codegraph/.gitignore"; fi
  out="$(cd "$TMP/repo" && "$WT" list --json 2>/dev/null)" || fail "$name: $change: th-wt list --json falló"
  [ "$(jq -r '.worktrees[] | select(.branch == "feature/trk-dirty") | .dirty' <<<"$out")" = true ] || fail "$name: $change: dirty != true: [$out]"
  rc=0
  out="$(cd "$TMP/repo" && PATH="$TMP/bin:$PATH" "$WT" close feature/trk-dirty --yes 2>&1)" || rc=$?
  [ "$rc" = 4 ] || fail "$name: $change: exit=$rc, esperado 4: [$out]"
  [ ! -s "$TMP/cg.calls" ] || fail "$name: $change: se llamó a codegraph: [$(cat "$TMP/cg.calls")]"
  [ -f "$dest/.codegraph/codegraph.db" ] || fail "$name: $change: se borró la base de datos"
  git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/trk-dirty || fail "$name: $change: se borró la rama"
done
pass "$name"
