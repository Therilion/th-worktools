# shellcheck shell=bash
# shellcheck source=lib.sh source-path=SCRIPTDIR
# shellcheck disable=SC2154 # $repo is set by resolve_repo in lib.sh

# Returns the path of the worktree where branch $1 is checked out, or empty if none.
find_worktree_for_branch() {
  local target="refs/heads/$1" line path=""
  git worktree list --porcelain | while IFS= read -r line; do
    case "$line" in
      "worktree "*) path="${line#worktree }" ;;
      "branch "*)
        if [ "$line" = "branch $target" ]; then
          printf '%s\n' "$path"
          return 0
        fi
        ;;
    esac
  done
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

  resolve_repo
  dest="$(worktrees_root)${branch//\//-}"

  [ ! -e "$dest" ] || die 4 "destination already exists: $dest"

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    busy_path="$(find_worktree_for_branch "$branch")"
    [ -z "$busy_path" ] || die 4 "branch $branch is already checked out in $busy_path"
    git worktree add -q "$dest" "$branch" || die 1 "git worktree add failed"
  else
    if [ "$remote" = 1 ]; then
      remote_heads="$(git ls-remote --heads origin "refs/heads/$branch")"
      [ -n "$remote_heads" ] || die 4 "branch not found on origin: $branch"
      fetch_origin_branch "$branch"
    fi

    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      git worktree add --no-track -q -b "$branch" "$dest" "origin/$branch" || die 1 "git worktree add failed"
      git config "branch.$branch.remote" origin
      git config "branch.$branch.merge" "refs/heads/$branch"
    else
      die 4 "branch not found: $branch (try --remote)"
    fi
  fi

  if [ "$json" = 1 ]; then
    jq -n --arg path "$dest" --arg branch "$branch" --arg repo "$repo" '{path: $path, branch: $branch, repo: $repo}'
  fi
}
