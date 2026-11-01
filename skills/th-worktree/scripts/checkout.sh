# shellcheck shell=bash
# shellcheck source=lib.sh source-path=SCRIPTDIR
# shellcheck disable=SC2154 # $repo is set by resolve_repo in lib.sh

# Prints the path of the worktree where branch $1 is checked out, or nothing if none.
# No exit inside awk: it reads all of git's output, so git never gets SIGPIPE.
find_worktree_for_branch() {
  git worktree list --porcelain | awk -v t="branch refs/heads/$1" '/^worktree /{p=substr($0,10)} $0==t{print p}'
}

checkout_worktree() {
  local branch dest remote json remote_heads busy_path
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
      if ! git worktree add --no-track -q -b "$branch" "$dest" "refs/remotes/origin/$branch"; then
        # git creates the branch before failing; drop it so a retry does not take the no-upstream local path.
        git branch -D -q "$branch" || true
        die 1 "git worktree add failed"
      fi
      git config "branch.$branch.remote" origin
      git config "branch.$branch.merge" "refs/heads/$branch"
    else
      die 4 "branch not found: $branch (try --remote)"
    fi
  fi

  if [ "$json" = 1 ]; then
    print_created_json "$dest" "$branch"
  fi
}
