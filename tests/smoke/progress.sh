#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

# pnpm falso (anota sus llamadas en $TMP/pm.calls y falla si FAKE_PM_FAIL=1), codegraph falso (solo en los tests que lo activan) y gh falso (devuelve $TMP/gh.json).
mkdir -p "$TMP/bin"
cat > "$TMP/bin/pnpm" <<EOF2
#!/usr/bin/env bash
echo "\$PWD pnpm \$*" >> "$TMP/pm.calls"
[ -z "\${FAKE_PM_FAIL:-}" ] || exit 1
EOF2
cat > "$TMP/bin/codegraph" <<EOF2
#!/usr/bin/env bash
[ "\$1" != init ] || mkdir -p "\$3/.codegraph"
EOF2
cat > "$TMP/bin/gh" <<EOF2
#!/usr/bin/env bash
cat "$TMP/gh.json"
EOF2
chmod +x "$TMP/bin/pnpm" "$TMP/bin/codegraph" "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
: > "$TMP/pm.calls"

# main versiona un .gitignore con las rutas a enlazar, que existen en el checkout principal.
printf '%s\n' .wiki docs/local > "$TMP/repo/.gitignore"
git -C "$TMP/repo" add .gitignore
git -C "$TMP/repo" commit -q -m "gitignore"
git -C "$TMP/repo" push -q origin main
mkdir -p "$TMP/repo/.wiki" "$TMP/repo/docs/local"

# with-pnpm: main más un pnpm-lock.yaml vacío.
git clone -q "$REMOTE_URL" "$TMP/other"
git -C "$TMP/other" checkout -q -b with-pnpm origin/main
touch "$TMP/other/pnpm-lock.yaml"
git -C "$TMP/other" add .
git -C "$TMP/other" commit -q -m "lockfile"
git -C "$TMP/other" push -q origin with-pnpm
git -C "$TMP/repo" fetch -q origin

CONF="$TMP/xdg/th-worktools/repos/acme/demo.conf"
mkdir -p "${CONF%/*}"
export XDG_CONFIG_HOME="$TMP/xdg"

W="$HOME/.worktrees/acme/demo"
progress() { grep '^th-wt: ' "$1" || true; }
summary() { grep '^  ' "$1" || true; }

name="new con .conf y pnpm-lock.yaml escribe en stderr las líneas de progreso en orden: fetching, creating, applying, linked, installing"
printf 'link .wiki\n' > "$CONF"
out="$(cd "$TMP/repo" && "$WT" new feature/orden --base with-pnpm 2>"$TMP/orden.err")" || fail "$name: th-wt new falló: [$(cat "$TMP/orden.err")]"
want="th-wt: fetching origin/with-pnpm
th-wt: creating worktree $W/feature-orden (branch feature/orden)
th-wt: applying repo config $CONF
th-wt: linked .wiki
th-wt: installing dependencies (pnpm install --frozen-lockfile)"
[ "$(progress "$TMP/orden.err")" = "$want" ] || fail "$name: stderr=[$(cat "$TMP/orden.err")]"
[ -z "$out" ] || fail "$name: stdout no vacío: [$out]"
pass "$name"

name="new con codegraph en PATH y TH_CODEGRAPH=auto escribe la línea de indexado después de crear el worktree"
rm -f "$CONF"
(cd "$TMP/repo" && TH_CODEGRAPH=auto "$WT" new feature/cg 2>"$TMP/cg.err" >/dev/null) || fail "$name: th-wt new falló: [$(cat "$TMP/cg.err")]"
want="th-wt: fetching origin/main
th-wt: creating worktree $W/feature-cg (branch feature/cg)
th-wt: indexing with codegraph (may take a few minutes)"
[ "$(progress "$TMP/cg.err")" = "$want" ] || fail "$name: stderr=[$(cat "$TMP/cg.err")]"
grep -qxF "  codegraph: indexed" "$TMP/cg.err" || fail "$name: resumen sin codegraph: indexed: [$(cat "$TMP/cg.err")]"
pass "$name"

name="new sin lockfile, sin .conf y con codegraph off no escribe las líneas de instalación, de config ni de indexado"
(cd "$TMP/repo" && "$WT" new feature/nada 2>"$TMP/nada.err" >/dev/null) || fail "$name: th-wt new falló: [$(cat "$TMP/nada.err")]"
want="th-wt: fetching origin/main
th-wt: creating worktree $W/feature-nada (branch feature/nada)"
[ "$(progress "$TMP/nada.err")" = "$want" ] || fail "$name: stderr=[$(cat "$TMP/nada.err")]"
pass "$name"

name="new con lockfile y TH_INSTALL_DEPS=0 no escribe la línea de instalación"
: > "$TMP/pm.calls"
(cd "$TMP/repo" && TH_INSTALL_DEPS=0 "$WT" new feature/deps-off --base with-pnpm 2>"$TMP/off.err" >/dev/null) || fail "$name: th-wt new falló: [$(cat "$TMP/off.err")]"
! grep -q "installing dependencies" "$TMP/off.err" || fail "$name: stderr=[$(cat "$TMP/off.err")]"
[ ! -s "$TMP/pm.calls" ] || fail "$name: se ejecutó el gestor: [$(cat "$TMP/pm.calls")]"
pass "$name"

name="new cuando pnpm falla escribe installing dependencies y resume deps: failed"
rc=0
(cd "$TMP/repo" && FAKE_PM_FAIL=1 "$WT" new feature/pm-fail --base with-pnpm >"$TMP/pmfail.out" 2>"$TMP/pmfail.err") || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc, esperado 0: [$(cat "$TMP/pmfail.err")]"
grep -qxF "th-wt: installing dependencies (pnpm install --frozen-lockfile)" "$TMP/pmfail.err" || fail "$name: falta installing dependencies: [$(cat "$TMP/pmfail.err")]"
grep -qxF "  deps:      failed" "$TMP/pmfail.err" || fail "$name: falta deps: failed: [$(cat "$TMP/pmfail.err")]"
[ ! -s "$TMP/pmfail.out" ] || fail "$name: stdout no vacío: [$(cat "$TMP/pmfail.out")]"
pass "$name"

name="new sin --json termina con el resumen de 5 líneas en stderr (linked: none) y stdout vacío"
want="  path:      $W/feature-nada
  branch:    feature/nada
  linked:    none
  deps:      skipped
  codegraph: not indexed"
[ "$(summary "$TMP/nada.err")" = "$want" ] || fail "$name: stderr=[$(cat "$TMP/nada.err")]"
pass "$name"

name="new sin --json con dos enlaces y pnpm resume linked separados por coma y deps: pnpm"
printf 'link .wiki\nlink docs/local\n' > "$CONF"
out="$(cd "$TMP/repo" && "$WT" new feature/resumen --base with-pnpm 2>"$TMP/res.err")" || fail "$name: th-wt new falló: [$(cat "$TMP/res.err")]"
want="  path:      $W/feature-resumen
  branch:    feature/resumen
  linked:    .wiki, docs/local
  deps:      pnpm
  codegraph: not indexed"
[ "$(summary "$TMP/res.err")" = "$want" ] || fail "$name: stderr=[$(cat "$TMP/res.err")]"
[ -z "$out" ] || fail "$name: stdout no vacío: [$out]"
pass "$name"

name="checkout de una rama local escribe creating y applying y termina con el resumen; stdout vacío"
printf 'link .wiki\n' > "$CONF"
git -C "$TMP/repo" branch --no-track co-local refs/remotes/origin/with-pnpm
out="$(cd "$TMP/repo" && "$WT" checkout co-local 2>"$TMP/co.err")" || fail "$name: th-wt checkout falló: [$(cat "$TMP/co.err")]"
want="th-wt: creating worktree $W/co-local (branch co-local)
th-wt: applying repo config $CONF
th-wt: linked .wiki
th-wt: installing dependencies (pnpm install --frozen-lockfile)"
[ "$(progress "$TMP/co.err")" = "$want" ] || fail "$name: progreso=[$(cat "$TMP/co.err")]"
want="  path:      $W/co-local
  branch:    co-local
  linked:    .wiki
  deps:      pnpm
  codegraph: not indexed"
[ "$(summary "$TMP/co.err")" = "$want" ] || fail "$name: resumen=[$(cat "$TMP/co.err")]"
[ -z "$out" ] || fail "$name: stdout no vacío: [$out]"
pass "$name"

name="checkout --remote de una rama solo remota escribe fetching antes de creating"
rm -f "$CONF"
git -C "$TMP/other" checkout -q -b solo-remota origin/main
git -C "$TMP/other" push -q origin solo-remota
(cd "$TMP/repo" && "$WT" checkout solo-remota --remote 2>"$TMP/rem.err" >/dev/null) || fail "$name: th-wt checkout falló: [$(cat "$TMP/rem.err")]"
want="th-wt: fetching origin/solo-remota
th-wt: creating worktree $W/solo-remota (branch solo-remota)"
[ "$(progress "$TMP/rem.err")" = "$want" ] || fail "$name: stderr=[$(cat "$TMP/rem.err")]"
pass "$name"

name="con --json, stdout es un único objeto JSON y las líneas de progreso siguen en stderr"
out="$(cd "$TMP/repo" && "$WT" new feature/json --json 2>"$TMP/json.err")" || fail "$name: th-wt new falló: [$(cat "$TMP/json.err")]"
[ "$(jq -s length <<<"$out")" = 1 ] || fail "$name: stdout=[$out]"
[ "$(jq -r .path <<<"$out")" = "$W/feature-json" ] || fail "$name: stdout=[$out]"
grep -qxF "th-wt: creating worktree $W/feature-json (branch feature/json)" "$TMP/json.err" || fail "$name: stderr=[$(cat "$TMP/json.err")]"
pass "$name"

name="pr escribe fetching del PR antes que el de la base y resume deps y codegraph al final"
git -C "$TMP/origin.git" update-ref refs/pull/51/head refs/heads/with-pnpm
jq -n --arg o "$(git -C "$TMP/origin.git" rev-parse refs/pull/51/head)" '{number: 51, title: "PR de prueba", headRefName: "feat/x", baseRefName: "main", headRefOid: $o}' > "$TMP/gh.json"
: > "$TMP/pm.calls"
out="$(cd "$TMP/repo" && "$WT" pr 51 2>"$TMP/pr.err")" || fail "$name: th-wt pr falló: [$(cat "$TMP/pr.err")]"
want="th-wt: fetching origin refs/pull/51/head
th-wt: fetching origin/main"
[ "$(grep '^th-wt: fetching' "$TMP/pr.err")" = "$want" ] || fail "$name: stderr=[$(cat "$TMP/pr.err")]"
grep -qxF "th-wt: creating worktree $W/pr-reviews/pr-51/code (branch review/pr-51)" "$TMP/pr.err" || fail "$name: sin creating: [$(cat "$TMP/pr.err")]"
! grep -q "installing dependencies" "$TMP/pr.err" || fail "$name: pr instaló: [$(cat "$TMP/pr.err")]"
want="  path:      $W/pr-reviews/pr-51/code
  PR:        #51 PR de prueba
  branch:    feat/x
  base:      main
  deps:      skipped
  codegraph: not indexed"
[ "$(summary "$TMP/pr.err")" = "$want" ] || fail "$name: resumen=[$(cat "$TMP/pr.err")]"
[ -z "$out" ] || fail "$name: stdout no vacío: [$out]"
pass "$name"
