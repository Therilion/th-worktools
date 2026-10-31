# shellcheck shell=bash
# shellcheck source=lib.sh source-path=SCRIPTDIR
# shellcheck disable=SC2154 # $repo is set by resolve_repo in lib.sh

checkout_worktree() {
  local branch dest remote
  case "${1:-}" in
    "") bad_usage "missing <branch>" ;;
    -h|--help) usage; exit 0 ;;
    -*) bad_usage "expected <branch> first, got option: $1 (options go after <branch>)" ;;
  esac
  branch="$1"
  shift
  remote=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --remote) remote=1; shift ;;
      *) bad_arg "$1" ;;
    esac
  done

  resolve_repo
  dest="$(worktrees_root)${branch//\//-}"

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add -q "$dest" "$branch" || die 1 "git worktree add failed"
    return 0
  fi

  if [ "$remote" = 1 ]; then
    git ls-remote --heads origin "refs/heads/$branch" >/dev/null
    fetch_origin_branch "$branch"
  fi

  if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    git worktree add --no-track -q -b "$branch" "$dest" "origin/$branch" || die 1 "git worktree add failed"
    git config "branch.$branch.remote" origin
    git config "branch.$branch.merge" "refs/heads/$branch"
  else
    return 1
  fi
}
