# shellcheck shell=bash
# shellcheck source=lib.sh source-path=SCRIPTDIR
# shellcheck disable=SC2154 # $repo is set by resolve_repo in lib.sh

# Prints the path of the worktree where branch $1 is checked out, or nothing if none.
# No exit inside awk: it reads all of git's output, so git never gets SIGPIPE.
find_worktree_for_branch() {
  git worktree list --porcelain | awk -v t="branch refs/heads/$1" '/^worktree /{p=substr($0,10)} $0==t{print p}'
}

checkout_worktree() {
  local branch dest remote json remote_heads busy_path track=0 pr_copy=0
  case "${1:-}" in
    "") bad_usage "missing <branch>" ;;
    -h|--help) usage; exit 0 ;;
    -*) bad_usage "expected <branch> first, got option: $1 (options go after <branch>)" ;;
  esac
  branch="$1"
  shift
  remote=0
  json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --remote) remote=1; shift ;;
      --json) json=1; shift ;;
      *) bad_arg "$1" ;;
    esac
  done

  git check-ref-format "refs/heads/$branch" || die 2 "invalid branch name: $branch"
  [ "$branch" != HEAD ] || die 2 "invalid branch name: $branch"

  resolve_repo
  worktree_dest "$branch"

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    busy_path="$(find_worktree_for_branch "$branch")"
    [ -z "$busy_path" ] || die 4 "branch $branch is already checked out in $busy_path"
    git worktree add -q "$dest" "$branch" || die 1 "git worktree add failed"
  else
    if [ "$remote" = 1 ]; then
      remote_heads="$(git ls-remote --heads origin "refs/heads/$branch")" || die 4 "cannot read origin (unreachable or no access)"
      [ -n "$remote_heads" ] || die 4 "branch not found on origin: $branch"
      fetch_origin_branch "$branch" || die 4 "fetch of origin/$branch failed"
    fi

    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      add_branch_worktree "$branch" "$dest" "refs/remotes/origin/$branch"
      track=1
    else
      die 4 "branch not found: $branch (try --remote)"
    fi
  fi
  # review/pr-* is a local copy of a PR (kept by close --force): same rule as pr
  case "$branch" in review/pr-*) pr_copy=1 ;; esac
  [ "$pr_copy" = 1 ] || apply_repo_conf "$dest" "$branch"
  # upstream config only after the conf passed, so a rejected worktree leaves nothing behind
  if [ "$track" = 1 ]; then
    git config "branch.$branch.remote" origin
    git config "branch.$branch.merge" "refs/heads/$branch"
  fi
  if [ "$pr_copy" = 1 ]; then skip_pr_deps "$dest"; else install_deps "$dest"; fi
  index_codegraph "$dest"

  if [ "$json" = 1 ]; then
    print_created_json "$dest" "$branch"
  fi
}
