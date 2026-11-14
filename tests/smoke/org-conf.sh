#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

# El repo de prueba versiona un .gitignore con las rutas a enlazar (sin barra final) y las tiene en el checkout principal.
printf '%s\n' .env .wiki .openspec docs/local > "$TMP/repo/.gitignore"
git -C "$TMP/repo" add .gitignore
git -C "$TMP/repo" commit -q -m "gitignore"
git -C "$TMP/repo" push -q origin main
echo "SECRETO=1" > "$TMP/repo/.env"
mkdir -p "$TMP/repo/.wiki" "$TMP/repo/docs/local"
echo nota > "$TMP/repo/.wiki/nota.md"
echo doc > "$TMP/repo/docs/local/doc.md"

CONF_ROOT="$TMP/xdg/th-worktools/repos"
ORG="$CONF_ROOT/acme.conf"
CONF="$CONF_ROOT/acme/demo.conf"
mkdir -p "$CONF_ROOT/acme"
export XDG_CONFIG_HOME="$TMP/xdg"
WTS="$HOME/.worktrees/acme/demo"

name="new con solo repos/acme.conf enlaza sus rutas y escribe 'applying repo config <org conf>'"
printf 'link .env\nlink .wiki\n' > "$ORG"
out="$(cd "$TMP/repo" && "$WT" new feature/o1 --json 2>"$TMP/o1.err")" || fail "$name: th-wt new falló: [$(cat "$TMP/o1.err")]"
[ "$(jq -c .linked <<<"$out")" = '[".env",".wiki"]' ] || fail "$name: salida=[$out]"
[ "$(readlink "$WTS/feature-o1/.env")" = "$TMP/repo/.env" ] || fail "$name: .env apunta a [$(readlink "$WTS/feature-o1/.env")]"
[ "$(readlink "$WTS/feature-o1/.wiki")" = "$TMP/repo/.wiki" ] || fail "$name: .wiki apunta a [$(readlink "$WTS/feature-o1/.wiki")]"
grep -qxF "th-wt: applying repo config $ORG" "$TMP/o1.err" || fail "$name: stderr=[$(cat "$TMP/o1.err")]"
pass "$name"

name="new con org y repo junta los enlaces (org primero) y escribe una línea 'applying repo config' por archivo"
printf 'link .env\n' > "$ORG"
printf 'link .wiki\n' > "$CONF"
out="$(cd "$TMP/repo" && "$WT" new feature/o2 --json 2>"$TMP/o2.err")" || fail "$name: th-wt new falló: [$(cat "$TMP/o2.err")]"
[ "$(jq -c .linked <<<"$out")" = '[".env",".wiki"]' ] || fail "$name: salida=[$out]"
[ "$(grep -F 'applying repo config' "$TMP/o2.err")" = "$(printf 'th-wt: applying repo config %s\nth-wt: applying repo config %s' "$ORG" "$CONF")" ] || fail "$name: stderr=[$(cat "$TMP/o2.err")]"
pass "$name"

name="una línea inválida en el org conf sale con 4 con '<org conf>:<línea>: <motivo>', sin worktree ni rama"
printf 'link .env\nlink docs/*\n' > "$ORG"
rc=0
(cd "$TMP/repo" && "$WT" new feature/o3 2>"$TMP/o3.err" >"$TMP/o3.out") || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/o3.err")]"
grep -qxF "th-wt: $ORG:2: globs are not supported: docs/*" "$TMP/o3.err" || fail "$name: stderr=[$(cat "$TMP/o3.err")]"
[ ! -e "$WTS/feature-o3" ] || fail "$name: quedó el worktree"
! git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/o3 || fail "$name: quedó la rama"
pass "$name"

name="un origin anidado (grupo/sub/demo) lee repos/grupo/sub.conf como org conf"
mkdir -p "$CONF_ROOT/grupo"
printf 'link .env\n' > "$CONF_ROOT/grupo/sub.conf"
printf 'link .wiki\n' > "$ORG"
git -C "$TMP/repo" remote set-url origin git@gitlab.com:grupo/sub/demo.git
git config --global --add "url.$TMP/origin.git.insteadOf" "git@gitlab.com:grupo/sub/demo.git"
out="$(cd "$TMP/repo" && "$WT" new feature/o4 --json 2>"$TMP/o4.err")" || fail "$name: th-wt new falló: [$(cat "$TMP/o4.err")]"
[ "$(jq -r .repo <<<"$out")" = "grupo/sub/demo" ] || fail "$name: salida=[$out]"
[ "$(jq -c .linked <<<"$out")" = '[".env"]' ] || fail "$name: salida=[$out]"
grep -qxF "th-wt: applying repo config $CONF_ROOT/grupo/sub.conf" "$TMP/o4.err" || fail "$name: stderr=[$(cat "$TMP/o4.err")]"
git -C "$TMP/repo" remote set-url origin "$REMOTE_URL"
pass "$name"

name="link? con la ruta ausente en el checkout principal: sale 0, no enlaza y no aparece en linked ni en stderr"
printf 'link? .openspec\nlink .env\n' > "$ORG"
rm -f "$CONF"
out="$(cd "$TMP/repo" && "$WT" new feature/o5 --json 2>"$TMP/o5.err")" || fail "$name: th-wt new falló: [$(cat "$TMP/o5.err")]"
[ "$(jq -c .linked <<<"$out")" = '[".env"]' ] || fail "$name: salida=[$out]"
{ [ ! -e "$WTS/feature-o5/.openspec" ] && [ ! -L "$WTS/feature-o5/.openspec" ]; } || fail "$name: se creó .openspec"
! grep -q "openspec" "$TMP/o5.err" || fail "$name: stderr=[$(cat "$TMP/o5.err")]"
pass "$name"

name="link? con la ruta presente se enlaza como link"
mkdir -p "$TMP/repo/.openspec"
echo spec > "$TMP/repo/.openspec/spec.md"
out="$(cd "$TMP/repo" && "$WT" new feature/o6 --json 2>"$TMP/o6.err")" || fail "$name: th-wt new falló: [$(cat "$TMP/o6.err")]"
[ "$(jq -c .linked <<<"$out")" = '[".openspec",".env"]' ] || fail "$name: salida=[$out]"
[ "$(readlink "$WTS/feature-o6/.openspec")" = "$TMP/repo/.openspec" ] || fail "$name: .openspec apunta a [$(readlink "$WTS/feature-o6/.openspec")]"
grep -qxF "th-wt: linked .openspec" "$TMP/o6.err" || fail "$name: stderr=[$(cat "$TMP/o6.err")]"
pass "$name"

name="link? con la ruta presente pero no ignorada por git en el worktree sale con 4, sin worktree ni rama"
mkdir -p "$TMP/repo/docs/other"
printf 'link? docs/other\n' > "$ORG"
rc=0
(cd "$TMP/repo" && "$WT" new feature/o7 2>"$TMP/o7.err" >"$TMP/o7.out") || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/o7.err")]"
grep -qxF "th-wt: $ORG:1: docs/other is not ignored by git in the worktree (versioned, or missing from .gitignore)" "$TMP/o7.err" || fail "$name: stderr=[$(cat "$TMP/o7.err")]"
[ ! -e "$WTS/feature-o7" ] || fail "$name: quedó el worktree"
! git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/o7 || fail "$name: quedó la rama"
rmdir "$TMP/repo/docs/other"
pass "$name"

name="link? sin ruta sale con 4 con \"expected 'link? <path>'\""
printf 'link?\n' > "$ORG"
rc=0
(cd "$TMP/repo" && "$WT" new feature/o7b 2>"$TMP/o7b.err" >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/o7b.err")]"
grep -qxF "th-wt: $ORG:1: expected 'link? <path>'" "$TMP/o7b.err" || fail "$name: stderr=[$(cat "$TMP/o7b.err")]"
pass "$name"

name="org 'link .wiki' + repo 'link? .wiki' sin .wiki en el principal: gana el repo (opcional) y sale 0; sin el repo falla en el org"
mv "$TMP/repo/.wiki" "$TMP/repo/.wiki.off"
printf 'link .wiki\nlink .env\n' > "$ORG"
printf 'link? .wiki\n' > "$CONF"
out="$(cd "$TMP/repo" && "$WT" new feature/o8 --json 2>"$TMP/o8.err")" || fail "$name: th-wt new falló: [$(cat "$TMP/o8.err")]"
[ "$(jq -c .linked <<<"$out")" = '[".env"]' ] || fail "$name: salida=[$out]"
rm "$CONF"
rc=0
(cd "$TMP/repo" && "$WT" new feature/o8b 2>"$TMP/o8b.err" >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "$name: sin el repo, exit=$rc, esperado 4: [$(cat "$TMP/o8b.err")]"
grep -qxF "th-wt: $ORG:1: .wiki does not exist in the main checkout ($TMP/repo)" "$TMP/o8b.err" || fail "$name: stderr=[$(cat "$TMP/o8b.err")]"
pass "$name"

name="org 'link? .wiki' + repo 'link .wiki' sin .wiki en el principal: gana el repo (obligatorio) y el error nombra el repo conf"
printf 'link? .wiki\n' > "$ORG"
printf 'link .env\nlink .wiki\n' > "$CONF"
rc=0
(cd "$TMP/repo" && "$WT" new feature/o8c 2>"$TMP/o8c.err" >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/o8c.err")]"
grep -qxF "th-wt: $CONF:2: .wiki does not exist in the main checkout ($TMP/repo)" "$TMP/o8c.err" || fail "$name: stderr=[$(cat "$TMP/o8c.err")]"
mv "$TMP/repo/.wiki.off" "$TMP/repo/.wiki"
pass "$name"

name="la misma ruta en org y repo (distinta mayúscula incluida): el repo reemplaza al org en su posición"
# solo existe la grafía del repo (.Notas): en Linux .notas sería otra ruta, inexistente
mkdir "$TMP/repo/.Notas"
echo .Notas >> "$TMP/repo/.git/info/exclude"
printf 'link .notas\nlink .env\n' > "$ORG"
printf 'link .Notas\n' > "$CONF"
out="$(cd "$TMP/repo" && "$WT" new feature/o8d --json 2>"$TMP/o8d.err")" || fail "$name: th-wt new falló: [$(cat "$TMP/o8d.err")]"
[ "$(jq -c .linked <<<"$out")" = '[".Notas",".env"]' ] || fail "$name: salida=[$out]"
pass "$name"

name="un solape no idéntico entre org y repo sale con 4 y nombra '<org conf>:<línea>' (en ambas direcciones)"
printf 'link docs\n' > "$ORG"
printf 'link docs/local\n' > "$CONF"
rc=0
(cd "$TMP/repo" && "$WT" new feature/o9 2>"$TMP/o9.err" >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/o9.err")]"
grep -qxF "th-wt: $CONF:1: docs/local overlaps docs ($ORG:1)" "$TMP/o9.err" || fail "$name: stderr=[$(cat "$TMP/o9.err")]"
printf 'link .env\nlink docs/local\n' > "$ORG"
printf 'link docs\n' > "$CONF"
rc=0
(cd "$TMP/repo" && "$WT" new feature/o9b 2>"$TMP/o9b.err" >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "$name: (inversa) exit=$rc, esperado 4: [$(cat "$TMP/o9b.err")]"
grep -qxF "th-wt: $CONF:1: docs overlaps docs/local ($ORG:2)" "$TMP/o9b.err" || fail "$name: (inversa) stderr=[$(cat "$TMP/o9b.err")]"
[ ! -e "$WTS/feature-o9" ] || fail "$name: quedó un worktree"
pass "$name"

name="un link? del org ausente en el principal no choca con un link del repo que lo contiene"
printf 'link? .wiki/falta\n' > "$ORG"
printf 'link .wiki\n' > "$CONF"
out="$(cd "$TMP/repo" && "$WT" new feature/o9d --json 2>"$TMP/o9d.err")" || fail "$name: th-wt new falló: [$(cat "$TMP/o9d.err")]"
[ "$(jq -c .linked <<<"$out")" = '[".wiki"]' ] || fail "$name: salida=[$out]"
pass "$name"

name="un duplicado dentro del mismo archivo sigue siendo un error con 'line <n>'"
printf 'link .env\nlink .env\n' > "$CONF"
rm "$ORG"
rc=0
(cd "$TMP/repo" && "$WT" new feature/o9c 2>"$TMP/o9c.err" >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/o9c.err")]"
grep -qxF "th-wt: $CONF:2: .env overlaps .env (line 1)" "$TMP/o9c.err" || fail "$name: stderr=[$(cat "$TMP/o9c.err")]"
pass "$name"

# pnpm falso y dos prefijos falsos: anotan "<cwd> <programa> <args>" en $TMP/pm.calls y ejecutan el resto.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/pnpm" <<EOF2
#!/usr/bin/env bash
echo "\$PWD pnpm \$*" >> "$TMP/pm.calls"
EOF2
for prog in with-org with-repo; do
  cat > "$TMP/bin/$prog" <<EOF2
#!/usr/bin/env bash
echo "\$PWD $prog \$*" >> "$TMP/pm.calls"
exec "\$@"
EOF2
done
chmod +x "$TMP/bin/pnpm" "$TMP/bin/with-org" "$TMP/bin/with-repo"
export PATH="$TMP/bin:$PATH"
git clone -q "$REMOTE_URL" "$TMP/other"
git -C "$TMP/other" checkout -q -b with-pnpm origin/main
touch "$TMP/other/pnpm-lock.yaml"
git -C "$TMP/other" add .
git -C "$TMP/other" commit -q -m "lockfile"
git -C "$TMP/other" push -q origin with-pnpm

name="deps-prefix en org y repo: instala con el del repo"
: > "$TMP/pm.calls"
printf 'deps-prefix with-org\n' > "$ORG"
printf 'deps-prefix with-repo\n' > "$CONF"
(cd "$TMP/repo" && "$WT" new feature/o10 --base with-pnpm >/dev/null 2>"$TMP/o10.err") || fail "$name: th-wt new falló: [$(cat "$TMP/o10.err")]"
dest="$WTS/feature-o10"
[ "$(cat "$TMP/pm.calls")" = "$(printf '%s\n%s' "$dest with-repo pnpm install --frozen-lockfile" "$dest pnpm install --frozen-lockfile")" ] || fail "$name: llamadas=[$(cat "$TMP/pm.calls")]"
pass "$name"

name="deps-prefix solo en el org: instala con ese prefijo"
: > "$TMP/pm.calls"
rm "$CONF"
(cd "$TMP/repo" && "$WT" new feature/o11 --base with-pnpm >/dev/null 2>"$TMP/o11.err") || fail "$name: th-wt new falló: [$(cat "$TMP/o11.err")]"
dest="$WTS/feature-o11"
[ "$(cat "$TMP/pm.calls")" = "$(printf '%s\n%s' "$dest with-org pnpm install --frozen-lockfile" "$dest pnpm install --frozen-lockfile")" ] || fail "$name: llamadas=[$(cat "$TMP/pm.calls")]"
pass "$name"

name="dos deps-prefix en el mismo archivo siguen siendo un error con 'line <n>'"
printf 'deps-prefix with-org\ndeps-prefix with-repo\n' > "$ORG"
rc=0
(cd "$TMP/repo" && "$WT" new feature/o11b 2>"$TMP/o11b.err" >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/o11b.err")]"
grep -qxF "th-wt: $ORG:2: duplicate deps-prefix (line 1)" "$TMP/o11b.err" || fail "$name: stderr=[$(cat "$TMP/o11b.err")]"
pass "$name"

git -C "$TMP/repo" remote set-head origin main >/dev/null
rm -f "$CONF"

name="close --yes conserva las ramas que coinciden con un keep del org y con uno del repo (unión)"
printf 'keep develop\n' > "$ORG"
printf 'keep release/*\n' > "$CONF"
for b in develop release/1.0 feature/o12; do
  (cd "$TMP/repo" && "$WT" new "$b" >/dev/null 2>&1) || fail "$name: th-wt new $b falló"
  err="$(cd "$TMP/repo" && "$WT" close "$b" --yes 2>&1)" || fail "$name: th-wt close $b falló: [$err]"
done
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/develop || fail "$name: se borró develop (keep del org)"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/release/1.0 || fail "$name: se borró release/1.0 (keep del repo)"
! git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/o12 || fail "$name: no se borró feature/o12"
pass "$name"

name="close no falla con un link? ausente en el principal"
rm -rf "$TMP/repo/.openspec"
printf 'link .env\n' > "$ORG"
(cd "$TMP/repo" && "$WT" new feature/o13 >/dev/null 2>&1) || fail "$name: th-wt new falló"
printf 'link .env\nlink? .openspec\n' > "$ORG"
err="$(cd "$TMP/repo" && "$WT" close feature/o13 --yes 2>&1)" || fail "$name: th-wt close falló: [$err]"
[ ! -e "$WTS/feature-o13" ] || fail "$name: sigue el directorio"
pass "$name"

name="th-wt link <rama> crea un enlace nuevo del org conf y omite un link? ausente"
printf 'link .env\n' > "$ORG"
(cd "$TMP/repo" && "$WT" new feature/o14 >/dev/null 2>&1) || fail "$name: th-wt new falló"
printf 'link .env\nlink .wiki\nlink? .openspec\n' > "$ORG"
out="$(cd "$TMP/repo" && "$WT" link feature/o14 --json 2>"$TMP/o14.err")" || fail "$name: th-wt link falló: [$(cat "$TMP/o14.err")]"
[ "$(jq -c .linked <<<"$out")" = '[".wiki"]' ] || fail "$name: salida=[$out]"
[ "$(readlink "$WTS/feature-o14/.wiki")" = "$TMP/repo/.wiki" ] || fail "$name: .wiki apunta a [$(readlink "$WTS/feature-o14/.wiki")]"
{ [ ! -e "$WTS/feature-o14/.openspec" ] && [ ! -L "$WTS/feature-o14/.openspec" ]; } || fail "$name: se creó .openspec"
grep -qxF "th-wt: applying repo config $ORG" "$TMP/o14.err" || fail "$name: stderr=[$(cat "$TMP/o14.err")]"
pass "$name"

# gh falso para pr: devuelve $TMP/gh.json.
cat > "$TMP/bin/gh" <<EOF2
#!/usr/bin/env bash
cat "$TMP/gh.json"
EOF2
chmod +x "$TMP/bin/gh"
git -C "$TMP/origin.git" update-ref refs/pull/42/head refs/heads/main
jq -n --arg o "$(git -C "$TMP/origin.git" rev-parse refs/pull/42/head)" '{number: 42, title: "PR de prueba", headRefName: "x", baseRefName: "main", headRefOid: $o}' > "$TMP/gh.json"

name="pr con org conf no enlaza nada (pasa sin cambios: pr nunca lee el .conf)"
printf 'link .env\n' > "$ORG"
out="$(cd "$TMP/repo" && "$WT" pr 42 --json 2>"$TMP/o15.err")" || fail "$name: pr falló: [$(cat "$TMP/o15.err")]"
dest="$WTS/pr-reviews/pr-42/code"
{ [ ! -e "$dest/.env" ] && [ ! -L "$dest/.env" ]; } || fail "$name: pr enlazó .env"
[ "$(jq -c .linked <<<"$out")" = '[]' ] || fail "$name: salida=[$out]"
! grep -q "applying repo config" "$TMP/o15.err" || fail "$name: stderr=[$(cat "$TMP/o15.err")]"
pass "$name"

# Una rama que versiona .wiki (que el checkout principal sí tiene): el org no puede saberlo.
git -C "$TMP/other" checkout -q -b with-wiki origin/main
mkdir -p "$TMP/other/.wiki"
echo versionada > "$TMP/other/.wiki/nota.md"
git -C "$TMP/other" add -f .wiki
git -C "$TMP/other" commit -q -m "wiki"
git -C "$TMP/other" push -q origin with-wiki
rm -f "$CONF"

name="link? de una ruta versionada en la rama se omite en new: sale 0 y no aparece en linked"
printf 'link? .wiki\nlink .env\n' > "$ORG"
out="$(cd "$TMP/repo" && "$WT" new feature/o16 --base with-wiki --json 2>"$TMP/o16.err")" || fail "$name: th-wt new falló: [$(cat "$TMP/o16.err")]"
[ "$(jq -c .linked <<<"$out")" = '[".env"]' ] || fail "$name: salida=[$out]"
{ [ -d "$WTS/feature-o16/.wiki" ] && [ ! -L "$WTS/feature-o16/.wiki" ]; } || fail "$name: .wiki no es el directorio versionado"
! grep -q "\.wiki" "$TMP/o16.err" || fail "$name: stderr=[$(cat "$TMP/o16.err")]"
pass "$name"

name="un link (no opcional) de una ruta versionada sigue fallando con 4"
printf 'link .wiki\nlink .env\n' > "$ORG"
rc=0
(cd "$TMP/repo" && "$WT" new feature/o16b --base with-wiki 2>"$TMP/o16b.err" >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/o16b.err")]"
grep -qxF "th-wt: $ORG:1: .wiki is not ignored by git in the worktree (versioned, or missing from .gitignore)" "$TMP/o16b.err" || fail "$name: stderr=[$(cat "$TMP/o16b.err")]"
pass "$name"

name="th-wt link <rama> omite un link? de una ruta versionada"
printf 'link .env\n' > "$ORG"
(cd "$TMP/repo" && "$WT" new feature/o17 --base with-wiki >/dev/null 2>&1) || fail "$name: th-wt new falló"
printf 'link? .wiki\n' > "$ORG"
out="$(cd "$TMP/repo" && "$WT" link feature/o17 --json 2>"$TMP/o17.err")" || fail "$name: th-wt link falló: [$(cat "$TMP/o17.err")]"
[ "$(jq -c .linked <<<"$out")" = '[]' ] || fail "$name: salida=[$out]"
[ ! -L "$WTS/feature-o17/.wiki" ] || fail "$name: .wiki es un enlace"
pass "$name"

# El checkout principal versiona .spec/x e ignora .spec/local (que existe): el org no puede saberlo.
mkdir -p "$TMP/repo/.spec/local"
echo x > "$TMP/repo/.spec/x"
echo l > "$TMP/repo/.spec/local/l"
echo .spec/local >> "$TMP/repo/.gitignore"
git -C "$TMP/repo" add .gitignore .spec/x
git -C "$TMP/repo" commit -q -m "spec"
git -C "$TMP/repo" push -q origin main

name="un link? del org versionado no choca con un link del repo a una subruta ignorada"
printf 'link? .spec\n' > "$ORG"
printf 'link .spec/local\n' > "$CONF"
out="$(cd "$TMP/repo" && "$WT" new feature/o18 --json 2>"$TMP/o18.err")" || fail "$name: th-wt new falló: [$(cat "$TMP/o18.err")]"
[ "$(jq -c .linked <<<"$out")" = '[".spec/local"]' ] || fail "$name: salida=[$out]"
(cd "$TMP/repo" && "$WT" close feature/o18 >/dev/null 2>"$TMP/o18c.err") || fail "$name: th-wt close falló: [$(cat "$TMP/o18c.err")]"
pass "$name"
