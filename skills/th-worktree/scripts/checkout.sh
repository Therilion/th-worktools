# shellcheck shell=bash
# shellcheck source=lib.sh source-path=SCRIPTDIR
# shellcheck disable=SC2154 # $repo is set by resolve_repo in lib.sh

checkout_worktree() {
  local branch dest
  case "${1:-}" in
    "") bad_usage "missing <branch>" ;;
    -h|--help) usage; exit 0 ;;
    -*) bad_usage "expected <branch> first, got option: $1 (options go after <branch>)" ;;
  esac
  branch="$1"
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      *) bad_arg "$1" ;;
    esac
  done

  resolve_repo
  dest="$(worktrees_root)${branch//\//-}"

  git worktree add -q "$dest" "$branch" || die 1 "git worktree add failed"
}
