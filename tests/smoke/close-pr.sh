#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

# gh falso: devuelve $TMP/gh.json (solo lo usa `pr`; close no consulta GitHub).
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<EOF2
#!/usr/bin/env bash
cat "$TMP/gh.json"
EOF2
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

# Abre el PR $1 (un commit hijo de main solo en refs/pull/$1/head) y deja un report.md al lado del código.
open_pr() {
  git -C "$TMP/origin.git" update-ref "refs/pull/$1/head" "$(git -C "$TMP/origin.git" commit-tree -p main -m "trabajo del PR $1" "main^{tree}")"
  echo "{\"number\":$1,\"title\":\"PR $1\",\"headRefName\":\"feat/x$1\",\"baseRefName\":\"main\"}" > "$TMP/gh.json"
  (cd "$TMP/repo" && "$WT" pr "$1" 2>/dev/null) || fail "th-wt pr $1 falló"
  echo "notas" > "$HOME/.worktrees/acme/demo/pr-reviews/pr-$1/report.md"
}

name="close review/pr-<n> sin --yes planea borrar worktree y rama aunque no estén mergeadas ni pusheadas, y nombra los archivos que se conservan"
open_pr 7
dest="$HOME/.worktrees/acme/demo/pr-reviews/pr-7/code"
out="$(cd "$TMP/repo" && "$WT" close review/pr-7 --json 2>/dev/null)" || fail "$name: close --json falló"
[ "$(printf '%s' "$out" | jq -c '[.delete, .kept]')" = '[{"worktree":true,"branch":true},["report.md"]]' ] || fail "$name: json=[$out]"
err="$(cd "$TMP/repo" && "$WT" close review/pr-7 2>&1)" || fail "$name: close falló: [$err]"
printf '%s\n' "$err" | grep -E '^ +delete: +worktree and branch' >/dev/null || fail "$name: el plan no dice que se borran worktree y rama: [$err]"
printf '%s\n' "$err" | grep -E '^ +kept: +.*report\.md' >/dev/null || fail "$name: el plan no nombra report.md: [$err]"
[ -d "$dest" ] || fail "$name: el dry run borró el worktree"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/review/pr-7 || fail "$name: el dry run borró la rama"
pass "$name"

name="close review/pr-<n> --yes borra worktree y rama y conserva report.md"
dest="$HOME/.worktrees/acme/demo/pr-reviews/pr-7/code"
(cd "$TMP/repo" && "$WT" close review/pr-7 --yes 2>/dev/null) || fail "$name: close --yes falló"
[ ! -e "$dest" ] || fail "$name: sigue el worktree"
git -C "$TMP/repo" worktree list --porcelain | grep -F "$dest" >/dev/null && fail "$name: git sigue registrando el worktree"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/review/pr-7 && fail "$name: sigue la rama"
[ "$(cat "$HOME/.worktrees/acme/demo/pr-reviews/pr-7/report.md")" = notas ] || fail "$name: report.md no se conservó"
pass "$name"

name="close review/pr-<n> --yes borra pr-reviews/pr-<n>/ solo si queda vacío"
open_pr 8
rm "$HOME/.worktrees/acme/demo/pr-reviews/pr-8/report.md"
(cd "$TMP/repo" && "$WT" close review/pr-8 --yes 2>/dev/null) || fail "$name: close --yes falló"
[ ! -e "$HOME/.worktrees/acme/demo/pr-reviews/pr-8" ] || fail "$name: sigue pr-reviews/pr-8/"
[ -d "$HOME/.worktrees/acme/demo/pr-reviews/pr-7" ] || fail "$name: se borró pr-reviews/pr-7/, que tiene report.md"
pass "$name"

name="close review/pr-<n> con commits míos posteriores al PR bloquea sin --force, el plan los muestra y --force cierra"
open_pr 9
dest="$HOME/.worktrees/acme/demo/pr-reviews/pr-9/code"
git -C "$dest" commit -q --allow-empty -m "mi arreglo sobre el PR"
out="$(cd "$TMP/repo" && "$WT" close review/pr-9 --json 2>/dev/null)" || fail "$name: close --json falló"
[ "$(printf '%s' "$out" | jq -c '[.after_pr, has("unpushed"), .delete]')" = '[1,false,{"worktree":false,"branch":false}]' ] || fail "$name: json=[$out]"
err="$(cd "$TMP/repo" && "$WT" close review/pr-9 2>&1)" || fail "$name: close falló: [$err]"
case "$err" in *"mi arreglo sobre el PR"*) ;; *) fail "$name: el plan no muestra mi commit: [$err]" ;; esac
case "$err" in *"blocked: 1 commit(s) of yours after the PR"*) ;; *) fail "$name: el plan no dice por qué bloquea: [$err]" ;; esac
rc=0
err="$(cd "$TMP/repo" && "$WT" close review/pr-9 --yes 2>&1)" || rc=$?
[ "$rc" = 4 ] || fail "$name: --yes sin --force: exit=$rc, esperado 4: [$err]"
[ -d "$dest" ] || fail "$name: --yes sin --force borró el worktree"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/review/pr-9 || fail "$name: --yes sin --force borró la rama"
(cd "$TMP/repo" && "$WT" close review/pr-9 --yes --force 2>/dev/null) || fail "$name: --force falló"
[ ! -e "$dest" ] || fail "$name: --force no borró el worktree"
git -C "$TMP/repo" show-ref --verify --quiet refs/heads/review/pr-9 && fail "$name: --force no borró la rama"
pass "$name"

name="close review/pr-<n> con cambios sin commitear o sin saber si hay commits míos (sin reflog, o con su primera entrada expirada) bloquea sin --force"
blocked() { # <rama> <json esperado de [dirty, after_pr, delete.worktree]> <fragmento del plan>
  local out err rc=0
  out="$(cd "$TMP/repo" && "$WT" close "$1" --json 2>/dev/null)" || fail "$name: $1: close --json falló"
  [ "$(printf '%s' "$out" | jq -c '[.dirty, .after_pr, .delete.worktree]')" = "$2" ] || fail "$name: $1: json=[$out]"
  err="$(cd "$TMP/repo" && "$WT" close "$1" 2>&1)" || fail "$name: $1: close falló: [$err]"
  case "$err" in *"$3"*) ;; *) fail "$name: $1: el plan no dice [$3]: [$err]" ;; esac
  err="$(cd "$TMP/repo" && "$WT" close "$1" --yes 2>&1)" || rc=$?
  [ "$rc" = 4 ] || fail "$name: $1: --yes sin --force: exit=$rc, esperado 4: [$err]"
  git -C "$TMP/repo" show-ref --verify --quiet "refs/heads/$1" || fail "$name: $1: --yes sin --force borró la rama"
}
reflog_of() { printf '%s' "$TMP/repo/.git/logs/refs/heads/$1"; }

open_pr 10
echo "sin commitear" > "$HOME/.worktrees/acme/demo/pr-reviews/pr-10/code/nuevo.txt"
blocked review/pr-10 '[true,0,false]' "uncommitted changes"
(cd "$TMP/repo" && "$WT" close review/pr-10 --yes --force 2>/dev/null) || fail "$name: --force con cambios falló"
[ ! -e "$HOME/.worktrees/acme/demo/pr-reviews/pr-10/code" ] || fail "$name: --force no cerró el worktree con cambios"

open_pr 11
rm "$(reflog_of review/pr-11)"
blocked review/pr-11 '[false,null,false]' "cannot tell whether you have commits after the PR"
(cd "$TMP/repo" && "$WT" close review/pr-11 --yes --force 2>/dev/null) || fail "$name: --force sin reflog falló"

open_pr 12
git -C "$HOME/.worktrees/acme/demo/pr-reviews/pr-12/code" commit -q --allow-empty -m "mi commit"
# sin la entrada de creación, la primera que queda ya es mi commit: contarlo desde ahí daría 0
sed '1d' "$(reflog_of review/pr-12)" > "$TMP/reflog.cut" && cp "$TMP/reflog.cut" "$(reflog_of review/pr-12)"
blocked review/pr-12 '[false,null,false]' "cannot tell whether you have commits after the PR"
pass "$name"
