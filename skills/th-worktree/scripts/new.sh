# shellcheck shell=bash
# shellcheck source=lib.sh source-path=SCRIPTDIR
# shellcheck disable=SC2154 # $repo is set by resolve_repo in lib.sh

new_worktree() {
  local branch base json dest default
  case "${1:-}" in
    ""|-*) bad_usage ;;
  esac
  branch="$1"
  shift
  base=""
  json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --base) { [ $# -ge 2 ] && [ -n "$2" ]; } || bad_usage; base="$2"; shift 2 ;;
      --json) json=1; shift ;;
      *) bad_usage ;;
    esac
  done

  git check-ref-format "refs/heads/$branch" || die 2 "invalid branch name: $branch"
  [ -z "$base" ] || git check-ref-format "refs/heads/$base" || die 2 "invalid base branch: $base"

  resolve_repo
  dest="$HOME/.worktrees/$repo/${branch//\//-}"

  [ ! -e "$dest" ] || die 4 "destination already exists: $dest"

  default="$(origin_default_branch)" || die 1 "cannot read origin (unreachable or no access)"

  if git show-ref --verify --quiet "refs/heads/$branch" || [ -n "$(git ls-remote --heads origin "refs/heads/$branch")" ]; then
    die 4 "branch already exists: $branch"
  fi

  if [ -z "$base" ]; then
    base="$default"
    [ -n "$base" ] || die 1 "cannot determine origin's default branch (pass --base)"
  fi
  fetch_origin_branch "$base" || die 4 "base branch not found on origin (or fetch failed): $base"
  git worktree add --no-track -q -b "$branch" "$dest" "origin/$base" || die 1 "git worktree add failed"

  if [ "$json" = 1 ]; then
    jq -n --arg path "$dest" --arg branch "$branch" --arg repo "$repo" '{path: $path, branch: $branch, repo: $repo}'
  fi
}
