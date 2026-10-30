# shellcheck shell=bash
# shellcheck source=lib.sh source-path=SCRIPTDIR
# shellcheck disable=SC2154 # $repo is set by resolve_repo in lib.sh

# Path of the worktree of branch $1 whose path starts with $2 (case lives here: bash 3.2 mis-parses it inside $(...)).
find_worktree() {
  local line path=""
  git worktree list --porcelain | while IFS= read -r line; do
    case "$line" in
      "worktree "*) path="${line#worktree }" ;;
      "branch refs/heads/$1") case "$path" in "$2"*) echo "$path" ;; esac ;;
    esac
  done
}

close_worktree() {
  local branch="" json=0 yes=0 force=0 path root default out oid why here dirty=true merged=false unpushed del_wt=true del_br=false what
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      --yes) yes=1 ;;
      --force) force=1 ;;
      -*) bad_usage ;;
      *) [ -z "$branch" ] || bad_usage; branch="$1" ;;
    esac
    shift
  done
  [ -n "$branch" ] || bad_usage
  resolve_repo
  root="$HOME/.worktrees/$repo/"
  path="$(find_worktree "$branch" "$root")"
  [ -n "$path" ] || die 4 "no worktree for branch $branch under $root"
  if out="$(git --no-optional-locks -C "$path" status --porcelain --untracked-files=normal 2>/dev/null)"; then
    dirty=false
    [ -z "$out" ] || dirty=true
  fi
  default="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$default" ] && git merge-base --is-ancestor "refs/heads/$branch" "$default" 2>/dev/null; then merged=true; fi
  unpushed="$(git rev-list --count "refs/heads/$branch" --not --remotes=origin)"
  if { [ "$dirty" = true ] || [ "$unpushed" != 0 ]; } && [ "$force" = 0 ]; then del_wt=false
  elif [ "$merged" = true ]; then del_br=true; fi
  if [ "$yes" = 1 ]; then
    here="$(pwd -P)"
    case "$here/" in "$path/"*) die 4 "cannot close $path from inside it: run close from another directory" ;; esac
    if [ "$del_wt" = false ]; then
      why=""
      [ "$dirty" = false ] || why="uncommitted changes"
      [ "$unpushed" = 0 ] || why="${why:+$why and }$unpushed unpushed commit(s)"
      die 4 "$why in $path (use --force to close anyway)"
    fi
    oid="$(git rev-parse "refs/heads/$branch")"
    if [ "$force" = 1 ]; then git worktree remove --force "$path"; else git worktree remove "$path"; fi
    if [ "$del_br" = true ]; then git update-ref -d "refs/heads/$branch" "$oid"; else echo "th-wt: branch $branch kept: not contained in ${default:-the default branch}" >&2; fi
    git worktree prune
  fi
  if [ "$json" = 1 ]; then
    jq -n --arg path "$path" --arg branch "$branch" --argjson merged "$merged" --argjson dirty "$dirty" \
      --argjson unpushed "$unpushed" --argjson wt "$del_wt" --argjson br "$del_br" \
      '{path: $path, branch: $branch, merged: $merged, dirty: $dirty, unpushed: $unpushed, delete: {worktree: $wt, branch: $br}}'
    return 0
  fi
  if [ "$del_wt" = false ]; then what="nothing (blocked by uncommitted changes or unpushed commits)"
  elif [ "$del_br" = true ]; then what="worktree and branch"
  else what="worktree only (branch kept: not merged)"; fi
  {
    echo "  branch:    $branch"
    echo "  path:      $path"
    echo "  merged:    $merged"
    echo "  dirty:     $dirty"
    echo "  unpushed:  $unpushed commits"
    echo "  delete:    $what"
    if [ "$yes" = 1 ]; then echo "closed $path"; else echo "Dry run: nothing deleted. Add --yes to close."; fi
  } >&2
}
