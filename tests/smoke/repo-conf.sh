#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

# El repo de prueba versiona un .gitignore con las rutas a enlazar (sin barra final) y las tiene en el checkout principal.
printf '%s\n' .env .wiki docs/local > "$TMP/repo/.gitignore"
git -C "$TMP/repo" add .gitignore
git -C "$TMP/repo" commit -q -m "gitignore"
git -C "$TMP/repo" push -q origin main
echo "SECRETO=1" > "$TMP/repo/.env"
mkdir -p "$TMP/repo/.wiki" "$TMP/repo/docs/local"
echo nota > "$TMP/repo/.wiki/nota.md"
echo doc > "$TMP/repo/docs/local/doc.md"

CONF_DIR="$TMP/xdg/th-worktools/repos/acme"
CONF="$CONF_DIR/demo.conf"
mkdir -p "$CONF_DIR"
export XDG_CONFIG_HOME="$TMP/xdg"

name="new con .conf bajo XDG_CONFIG_HOME enlaza archivo, directorio y subdirectorio como symlinks absolutos; ignora comentarios y líneas vacías"
cat > "$CONF" <<'EOC'
# contexto local

link .env
   # comentario con sangría
link .wiki
link docs/local
EOC
out="$(cd "$TMP/repo" && "$WT" new feature/links --json 2>/dev/null)" || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-links"
for p in .env .wiki docs/local; do
  [ -L "$dest/$p" ] || fail "$name: $p no es un symlink"
  [ "$(readlink "$dest/$p")" = "$TMP/repo/$p" ] || fail "$name: $p apunta a [$(readlink "$dest/$p")]"
done
[ -z "$(git -C "$dest" status --porcelain)" ] || fail "$name: git status no está limpio: [$(git -C "$dest" status --porcelain)]"
[ "$(jq -c .linked <<<"$out")" = '[".env",".wiki","docs/local"]' ] || fail "$name: salida=[$out]"
pass "$name"

name="sin XDG_CONFIG_HOME, new lee el .conf de ~/.config/th-worktools/repos/<owner>/<repo>.conf"
mkdir -p "$HOME/.config/th-worktools/repos/acme"
printf 'link .env\n' > "$HOME/.config/th-worktools/repos/acme/demo.conf"
out="$(cd "$TMP/repo" && env -u XDG_CONFIG_HOME "$WT" new feature/home-conf --json 2>/dev/null)" || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-home-conf"
[ "$(readlink "$dest/.env")" = "$TMP/repo/.env" ] || fail "$name: .env apunta a [$(readlink "$dest/.env")]"
[ "$(jq -c .linked <<<"$out")" = '[".env"]' ] || fail "$name: salida=[$out]"
rm -r "$HOME/.config"
pass "$name"

name="checkout de una rama local con .conf enlaza y devuelve linked (última línea sin salto de línea incluida)"
git -C "$TMP/repo" branch feature/co-links
printf 'link .env\nlink .wiki' > "$CONF"
out="$(cd "$TMP/repo" && "$WT" checkout feature/co-links --json 2>/dev/null)" || fail "$name: th-wt checkout falló"
dest="$HOME/.worktrees/acme/demo/feature-co-links"
[ "$(readlink "$dest/.env")" = "$TMP/repo/.env" ] || fail "$name: .env apunta a [$(readlink "$dest/.env")]"
[ "$(readlink "$dest/.wiki")" = "$TMP/repo/.wiki" ] || fail "$name: .wiki apunta a [$(readlink "$dest/.wiki")]"
[ -z "$(git -C "$dest" status --porcelain)" ] || fail "$name: git status no está limpio"
[ "$(jq -c .linked <<<"$out")" = '[".env",".wiki"]' ] || fail "$name: salida=[$out]"
pass "$name"

name="en texto, stderr nombra las rutas enlazadas; con --json, stdout es un único objeto JSON"
printf 'link .env\nlink docs/local\n' > "$CONF"
git -C "$TMP/repo" branch feature/txt
(cd "$TMP/repo" && "$WT" checkout feature/txt 2>"$TMP/txt.err" >"$TMP/txt.out") || fail "$name: checkout en texto falló"
grep -qxF "th-wt: linked .env" "$TMP/txt.err" || fail "$name: stderr=[$(cat "$TMP/txt.err")]"
grep -qxF "th-wt: linked docs/local" "$TMP/txt.err" || fail "$name: stderr=[$(cat "$TMP/txt.err")]"
out="$(cd "$TMP/repo" && "$WT" new feature/json-links --json 2>/dev/null)" || fail "$name: new --json falló"
{ [ "$(jq -s length <<<"$out")" = 1 ] && [ "$(jq -c .linked <<<"$out")" = '[".env","docs/local"]' ]; } || fail "$name: stdout=[$out]"
pass "$name"

name="repo sin .conf: no enlaza nada, linked es [] y stderr no menciona enlaces"
rm "$CONF"
out="$(cd "$TMP/repo" && "$WT" new feature/sin-conf --json 2>"$TMP/sin.err")" || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-sin-conf"
[ ! -e "$dest/.env" ] || fail "$name: se creó .env"
[ "$(jq -c .linked <<<"$out")" = '[]' ] || fail "$name: salida=[$out]"
! grep -qi "link" "$TMP/sin.err" || fail "$name: stderr=[$(cat "$TMP/sin.err")]"
pass "$name"

name="checkout review/pr-* y pr con .conf no enlazan nada (linked: [])"
printf 'link .env\n' > "$CONF"
git -C "$TMP/repo" branch review/pr-41 main
out="$(cd "$TMP/repo" && "$WT" checkout review/pr-41 --json 2>"$TMP/rpr.err")" || fail "$name: checkout review/pr-41 falló"
dest="$HOME/.worktrees/acme/demo/review-pr-41"
{ [ ! -e "$dest/.env" ] && [ ! -L "$dest/.env" ]; } || fail "$name: checkout enlazó .env"
[ "$(jq -c .linked <<<"$out")" = '[]' ] || fail "$name: salida=[$out]"
! grep -q "linked" "$TMP/rpr.err" || fail "$name: stderr=[$(cat "$TMP/rpr.err")]"

# gh falso para pr: devuelve $TMP/gh.json.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<EOF2
#!/usr/bin/env bash
cat "$TMP/gh.json"
EOF2
chmod +x "$TMP/bin/gh"
git -C "$TMP/origin.git" update-ref refs/pull/42/head refs/heads/main
jq -n --arg o "$(git -C "$TMP/origin.git" rev-parse refs/pull/42/head)" '{number: 42, title: "PR de prueba", headRefName: "x", baseRefName: "main", headRefOid: $o}' > "$TMP/gh.json"
out="$(cd "$TMP/repo" && PATH="$TMP/bin:$PATH" "$WT" pr 42 --json 2>/dev/null)" || fail "$name: pr falló"
dest="$HOME/.worktrees/acme/demo/pr-reviews/pr-42/code"
{ [ ! -e "$dest/.env" ] && [ ! -L "$dest/.env" ]; } || fail "$name: pr enlazó .env"
[ "$(jq -c .linked <<<"$out")" = '[]' ] || fail "$name: salida=[$out]"
pass "$name"

# Verifica que `new <rama> --base <base>` con el .conf actual sale con 4 y "th-wt: <conf>:<línea>: <motivo>", sin worktree ni rama.
reject_new() {
  local name="$1" b="$2" n="$3" reason="$4" base="${5-main}" rc=0
  # base vacío: sin --base
  (cd "$TMP/repo" && "$WT" new "$b" ${base:+--base "$base"} 2>"$TMP/rej.err" >"$TMP/rej.out") || rc=$?
  [ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/rej.err")]"
  grep -qxF "th-wt: $CONF:$n: $reason" "$TMP/rej.err" || fail "$name: stderr=[$(cat "$TMP/rej.err")], esperado la línea $n: $reason"
  [ ! -s "$TMP/rej.out" ] || fail "$name: stdout no vacío: [$(cat "$TMP/rej.out")]"
  [ ! -e "$HOME/.worktrees/acme/demo/${b//\//-}" ] || fail "$name: quedó el worktree de $b"
  ! git -C "$TMP/repo" show-ref --verify --quiet "refs/heads/$b" || fail "$name: quedó la rama $b"
  [ "$(git -C "$TMP/repo" worktree list | grep -c "${b//\//-}")" = 0 ] || fail "$name: git aún registra el worktree de $b"
}

# Como reject_new pero sin --base y con origin inaccesible: el .conf debe rechazarse antes de consultarlo.
reject_new_offline() {
  mv "$TMP/origin.git" "$TMP/origin.off"
  reject_new "$1" "$2" "$3" "$4" ""
  mv "$TMP/origin.off" "$TMP/origin.git"
}

name="new con una acción distinta de link (copy u otra) sale con 4 con la línea y el motivo, sin worktree ni rama"
printf '# c\nlink .env\ncopy .env\n' > "$CONF"
reject_new "$name" feature/bad-copy 3 "unknown action 'copy' (only 'link' and 'deps-prefix' are supported)"
printf 'move .env\n' > "$CONF"
reject_new "$name" feature/bad-move 1 "unknown action 'move' (only 'link' and 'deps-prefix' are supported)"
printf 'link\n' > "$CONF"
reject_new "$name" feature/bad-nopath 1 "expected 'link <path>'"
printf 'link .env .wiki\n' > "$CONF"
reject_new "$name" feature/bad-extra 1 "expected 'link <path>'"
pass "$name"

name="new con ruta absoluta, con .., con glob, con barra final, ./ o // sale con 4, sin worktree ni rama"
rel="path must be relative, without '.', '..' or empty segments and without a trailing slash"
i=0
while IFS='|' read -r p reason; do
  i=$((i + 1))
  printf 'link .env\nlink %s\n' "$p" > "$CONF"
  reject_new "$name ($p)" "feature/bad-path-$i" 2 "$reason: $p"
done <<EOL
/etc/passwd|$rel
../repo|$rel
docs/../.env|$rel
.|$rel
./.env|$rel
docs//local|$rel
docs/local/|$rel
*.env|globs are not supported
.e?v|globs are not supported
.[e]nv|globs are not supported
EOL
pass "$name"

name="new con entradas duplicadas o solapadas sale con 4, sin worktree ni rama"
printf 'link .env\nlink .env\n' > "$CONF"
reject_new "$name" feature/bad-dup 2 ".env overlaps .env (line 1)"
printf 'link docs/local\nlink docs/local/doc.md\n' > "$CONF"
reject_new "$name" feature/bad-sub 2 "docs/local/doc.md overlaps docs/local (line 1)"
printf 'link docs/local/doc.md\nlink docs/local\n' > "$CONF"
reject_new "$name" feature/bad-sup 2 "docs/local overlaps docs/local/doc.md (line 1)"
pass "$name"

name="new con entradas que solo difieren en mayúsculas (.wiki y .WIKI, .wiki y .WIKI/sub) se rechazan como solapadas, sin escribir en el checkout principal"
before="$(ls -A "$TMP/repo/.wiki")"
printf 'link .wiki\nlink .WIKI\n' > "$CONF"
reject_new "$name" feature/bad-case 2 ".WIKI overlaps .wiki (line 1)"
printf 'link .wiki\nlink .WIKI/sub\n' > "$CONF"
reject_new "$name" feature/bad-case-sub 2 ".WIKI/sub overlaps .wiki (line 1)"
[ "$(ls -A "$TMP/repo/.wiki")" = "$before" ] || fail "$name: el checkout principal cambió: [$(ls -A "$TMP/repo/.wiki")]"
pass "$name"

name="new con una ruta que no existe en el checkout principal sale con 4, sin worktree ni rama"
printf 'link .env\nlink .wiki\nlink nope\n' > "$CONF"
reject_new "$name" feature/bad-missing 3 "nope does not exist in the main checkout ($TMP/repo)"
pass "$name"

name="new con una ruta no ignorada por el .gitignore de la rama abierta (solo ignorada en el checkout principal, o versionada) sale con 4"
not_ignored="is not ignored by git in the worktree (versioned, or missing from .gitignore)"
echo cache > "$TMP/repo/.cache"
echo ".cache" >> "$TMP/repo/.gitignore"
printf 'link .cache\n' > "$CONF"
reject_new "$name" feature/bad-main-only 1 ".cache $not_ignored"
git -C "$TMP/repo" checkout -q .gitignore
echo '{}' > "$TMP/repo/settings.json"
git clone -q "$REMOTE_URL" "$TMP/other"
git -C "$TMP/other" checkout -q -b with-tracked origin/main
echo '{}' > "$TMP/other/settings.json"
git -C "$TMP/other" add settings.json
git -C "$TMP/other" commit -q -m "versiona settings.json"
git -C "$TMP/other" push -q origin with-tracked
printf 'link settings.json\n' > "$CONF"
reject_new "$name" feature/bad-tracked 1 "settings.json $not_ignored" with-tracked
pass "$name"

name="new con .wiki/ (con barra) en el .gitignore sale con 4, explica la barra final y no toca .git/info/exclude"
git -C "$TMP/other" checkout -q -b with-slash origin/main
printf '%s\n' .env '.wiki/' docs/local > "$TMP/other/.gitignore"
git -C "$TMP/other" commit -q -am "ignora .wiki/ con barra"
git -C "$TMP/other" push -q origin with-slash
mkdir -p "$TMP/repo/.git/info"
echo "# excluidos" > "$TMP/repo/.git/info/exclude"
printf 'link .wiki\n' > "$CONF"
reject_new "$name" feature/bad-slash 1 ".wiki is ignored only as a directory ('.wiki/'); git sees a symlink as a file, so ignore '.wiki' without the trailing slash" with-slash
[ "$(cat "$TMP/repo/.git/info/exclude")" = "# excluidos" ] || fail "$name: cambió .git/info/exclude: [$(cat "$TMP/repo/.git/info/exclude")]"
pass "$name"

name="new con un padre de la ruta que es un archivo o un symlink en el worktree sale con 4, sin escribir fuera de él"
git -C "$TMP/other" checkout -q -b with-docs-file origin/main
echo "no soy un directorio" > "$TMP/other/docs"
git -C "$TMP/other" add docs
git -C "$TMP/other" commit -q -m "docs es un archivo"
git -C "$TMP/other" push -q origin with-docs-file
git -C "$TMP/other" checkout -q -b with-docs-link origin/main
mkdir -p "$TMP/afuera"
ln -s "$TMP/afuera" "$TMP/other/docs"
git -C "$TMP/other" add docs
git -C "$TMP/other" commit -q -m "docs es un symlink"
git -C "$TMP/other" push -q origin with-docs-link
printf 'link docs/local\n' > "$CONF"
reject_new "$name" feature/bad-parent-file 1 "docs/local: parent docs in the worktree is not a directory" with-docs-file
reject_new "$name" feature/bad-parent-link 1 "docs/local: parent docs in the worktree is not a directory" with-docs-link
[ -z "$(ls -A "$TMP/afuera")" ] || fail "$name: se escribió fuera del worktree: [$(ls -A "$TMP/afuera")]"
pass "$name"

name="new con un .conf inválido (acción desconocida, solape, ruta inexistente en el checkout principal) sale con 4 antes de consultar origin, sin worktree ni rama"
printf 'link .env\ncopy .env\n' > "$CONF"
reject_new_offline "$name" feature/off-copy 2 "unknown action 'copy' (only 'link' and 'deps-prefix' are supported)"
printf 'link docs/local\nlink docs/local/doc.md\n' > "$CONF"
reject_new_offline "$name" feature/off-sub 2 "docs/local/doc.md overlaps docs/local (line 1)"
printf 'link .env\nlink nope\n' > "$CONF"
reject_new_offline "$name" feature/off-missing 2 "nope does not exist in the main checkout ($TMP/repo)"
pass "$name"

name="checkout --remote de una rama solo remota con un .conf inválido sale con 4 y la línea del .conf sin consultar origin, sin worktree ni rama ni branch.<rama>.*"
git -C "$TMP/other" checkout -q -b feature/co-off-remote origin/main
git -C "$TMP/other" commit -q --allow-empty -m "rama solo remota"
git -C "$TMP/other" push -q origin feature/co-off-remote
printf 'link .env\ncopy .env\n' > "$CONF"
mv "$TMP/origin.git" "$TMP/origin.off"
rc=0
(cd "$TMP/repo" && "$WT" checkout feature/co-off-remote --remote 2>"$TMP/off.err" >"$TMP/off.out") || rc=$?
mv "$TMP/origin.off" "$TMP/origin.git"
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/off.err")]"
grep -qxF "th-wt: $CONF:2: unknown action 'copy' (only 'link' and 'deps-prefix' are supported)" "$TMP/off.err" || fail "$name: stderr=[$(cat "$TMP/off.err")]"
[ ! -s "$TMP/off.out" ] || fail "$name: stdout no vacío: [$(cat "$TMP/off.out")]"
[ ! -e "$HOME/.worktrees/acme/demo/feature-co-off-remote" ] || fail "$name: quedó el worktree"
! git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/co-off-remote || fail "$name: quedó la rama local"
[ -z "$(git -C "$TMP/repo" config --get-regexp '^branch\.feature/co-off-remote\.' || true)" ] || fail "$name: quedó config branch.*"
pass "$name"

name="new con link node_modules (también con otras mayúsculas), link packages/a/node_modules o link node_modules/.bin sale con 4 con la línea y el motivo, sin worktree ni rama"
reason_nm="node_modules cannot be linked (the dependency install would write through the symlink into the main checkout)"
printf 'link .env\nlink node_modules\n' > "$CONF"
reject_new "$name" feature/nm-root 2 "$reason_nm: node_modules"
printf 'link Node_Modules\n' > "$CONF"
reject_new "$name" feature/nm-case 1 "$reason_nm: Node_Modules"
printf 'link packages/a/node_modules\n' > "$CONF"
reject_new "$name" feature/nm-nested 1 "$reason_nm: packages/a/node_modules"
printf 'link .env\nlink node_modules/.bin\n' > "$CONF"
reject_new "$name" feature/nm-under 2 "$reason_nm: node_modules/.bin"
pass "$name"

name="checkout de una rama review/pr-* con un .conf inválido no lo lee y crea el worktree"
printf 'copy .env\n' > "$CONF"
git -C "$TMP/repo" branch review/pr-43 main
out="$(cd "$TMP/repo" && "$WT" checkout review/pr-43 --json 2>"$TMP/rpr43.err")" || fail "$name: checkout review/pr-43 falló: [$(cat "$TMP/rpr43.err")]"
[ -d "$HOME/.worktrees/acme/demo/review-pr-43" ] || fail "$name: no se creó el worktree"
[ "$(jq -c .linked <<<"$out")" = '[]' ] || fail "$name: salida=[$out]"
pass "$name"

name="checkout de una rama local con una entrada inválida sale con 4, deshace el worktree y conserva la rama en el mismo commit"
git -C "$TMP/repo" branch feature/co-bad-local
before="$(git -C "$TMP/repo" rev-parse feature/co-bad-local)"
printf 'link .env\nlink .cache\n' > "$CONF"
rc=0
(cd "$TMP/repo" && "$WT" checkout feature/co-bad-local 2>"$TMP/co.err" >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/co.err")]"
grep -qxF "th-wt: $CONF:2: .cache $not_ignored" "$TMP/co.err" || fail "$name: stderr=[$(cat "$TMP/co.err")]"
[ ! -e "$HOME/.worktrees/acme/demo/feature-co-bad-local" ] || fail "$name: quedó el worktree"
[ "$(git -C "$TMP/repo" worktree list | grep -c co-bad-local)" = 0 ] || fail "$name: git aún registra el worktree"
[ "$(git -C "$TMP/repo" rev-parse -q --verify feature/co-bad-local)" = "$before" ] || fail "$name: la rama local cambió o desapareció"
pass "$name"

name="checkout de una rama solo remota con una entrada inválida sale con 4, deshace worktree y rama y no deja branch.<rama>.* en la config"
git -C "$TMP/other" checkout -q -b feature/co-bad-remote origin/main
git -C "$TMP/other" commit -q --allow-empty -m "rama remota"
git -C "$TMP/other" push -q origin feature/co-bad-remote
git -C "$TMP/repo" fetch -q origin
rc=0
(cd "$TMP/repo" && "$WT" checkout feature/co-bad-remote 2>"$TMP/co2.err" >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/co2.err")]"
grep -qxF "th-wt: $CONF:2: .cache $not_ignored" "$TMP/co2.err" || fail "$name: stderr=[$(cat "$TMP/co2.err")]"
[ ! -e "$HOME/.worktrees/acme/demo/feature-co-bad-remote" ] || fail "$name: quedó el worktree"
! git -C "$TMP/repo" show-ref --verify --quiet refs/heads/feature/co-bad-remote || fail "$name: quedó la rama local"
[ -z "$(git -C "$TMP/repo" config --get-regexp '^branch\.feature/co-bad-remote\.' || true)" ] || fail "$name: quedó config branch.*"
pass "$name"

name="new con una ruta que empieza por - (link -secrets) la enlaza y stdout es un único objeto JSON con linked"
echo "x" > "$TMP/repo/-secrets"
echo "-secrets" >> "$TMP/repo/.gitignore"
git -C "$TMP/repo" commit -q -am "ignora -secrets"
git -C "$TMP/repo" push -q origin main
printf 'link -secrets\n' > "$CONF"
rc=0
out="$(cd "$TMP/repo" && "$WT" new feature/dash --json 2>"$TMP/dash.err")" || rc=$?
[ "$rc" = 0 ] || fail "$name: exit=$rc: [$(cat "$TMP/dash.err")]"
dest="$HOME/.worktrees/acme/demo/feature-dash"
[ "$(readlink "$dest/-secrets")" = "$TMP/repo/-secrets" ] || fail "$name: -secrets apunta a [$(readlink "$dest/-secrets" || true)]"
{ [ "$(jq -s length <<<"$out")" = 1 ] && [ "$(jq -c .linked <<<"$out")" = '["-secrets"]' ]; } || fail "$name: stdout=[$out]"
pass "$name"

name="checkout de una rama local con un .conf inválido ignora un created_start heredado del entorno y conserva la rama"
git -C "$TMP/repo" branch feature/co-env
before="$(git -C "$TMP/repo" rev-parse feature/co-env)"
printf 'link .cache\n' > "$CONF"
rc=0
(cd "$TMP/repo" && created_start="$before" "$WT" checkout feature/co-env 2>"$TMP/env.err" >/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4: [$(cat "$TMP/env.err")]"
[ "$(git -C "$TMP/repo" rev-parse -q --verify feature/co-env)" = "$before" ] || fail "$name: la rama local cambió o desapareció"
pass "$name"

name="un .conf con finales de línea CRLF enlaza sus entradas"
printf 'link .env\r\n# c\r\nlink .wiki\r\n' > "$CONF"
out="$(cd "$TMP/repo" && "$WT" new feature/crlf --json 2>"$TMP/crlf.err")" || fail "$name: th-wt new falló: [$(cat "$TMP/crlf.err")]"
dest="$HOME/.worktrees/acme/demo/feature-crlf"
{ [ -L "$dest/.env" ] && [ -L "$dest/.wiki" ]; } || fail "$name: no se enlazaron"
[ "$(jq -c .linked <<<"$out")" = '[".env",".wiki"]' ] || fail "$name: salida=[$out]"
pass "$name"

name="close --json de un worktree con enlaces no lista los symlinks en ignored"
printf 'link .env\nlink .wiki\nlink docs/local\n' > "$CONF"
(cd "$TMP/repo" && "$WT" new feature/close-links >/dev/null 2>&1) || fail "$name: th-wt new falló"
dest="$HOME/.worktrees/acme/demo/feature-close-links"
echo basura > "$dest/build.log"
echo "build.log" >> "$TMP/repo/.git/info/exclude"
out="$(cd "$TMP/repo" && "$WT" close feature/close-links --json 2>/dev/null)" || fail "$name: close falló"
[ "$(jq -c .ignored <<<"$out")" = '["build.log"]' ] || fail "$name: ignored=[$(jq -c .ignored <<<"$out")]"
(cd "$TMP/repo" && "$WT" close feature/close-links --yes >/dev/null 2>&1) || fail "$name: close --yes falló"
[ ! -e "$dest" ] || fail "$name: quedó el worktree"
{ [ "$(cat "$TMP/repo/.env")" = "SECRETO=1" ] && [ -f "$TMP/repo/.wiki/nota.md" ] && [ -f "$TMP/repo/docs/local/doc.md" ]; } || fail "$name: close borró archivos del checkout principal"
pass "$name"

name="deps-prefix inválido en el .conf (sin valor, dos palabras, con /, repetido) sale con 4 con la línea y el motivo, sin worktree ni rama"
printf 'deps-prefix\n' > "$CONF"
reject_new "$name" feature/bad-dp-empty 1 "expected 'deps-prefix <command>'"
printf 'link .env\ndeps-prefix with-token extra\n' > "$CONF"
reject_new "$name" feature/bad-dp-two 2 "expected 'deps-prefix <command>'"
printf 'deps-prefix ./with-token\n' > "$CONF"
reject_new "$name" feature/bad-dp-slash 1 "deps-prefix must be a command name in PATH, without '/': ./with-token"
printf 'deps-prefix /usr/bin/with-token\n' > "$CONF"
reject_new "$name" feature/bad-dp-abs 1 "deps-prefix must be a command name in PATH, without '/': /usr/bin/with-token"
printf '# c\ndeps-prefix with-token\nlink .env\ndeps-prefix otro\n' > "$CONF"
reject_new "$name" feature/bad-dp-dup 4 "duplicate deps-prefix (line 2)"
pass "$name"
