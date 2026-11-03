# shellcheck shell=bash
# shellcheck source=lib.sh source-path=SCRIPTDIR
# shellcheck disable=SC2154 # $repo is set by resolve_repo in lib.sh

pr_worktree() {
  local n json=0 dest meta oid base
  n="${1:-}"
  case "$n" in
    -h|--help) usage; exit 0 ;;
    ""|*[!0-9]*|0*) bad_usage "<n> must be a positive integer without leading zeros: ${n:-(missing)}" ;;
  esac
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1; shift ;;
      *) bad_arg "$1" ;;
    esac
  done

  resolve_repo
  dest="$(worktrees_root)pr-reviews/pr-$n/code"

  meta="$(gh pr view "$n" -R "$repo" --json number,title,headRefName,baseRefName)"
  base="$(jq -r .baseRefName <<<"$meta")"
  git fetch -q --no-tags origin "refs/pull/$n/head"
  # read before the base fetch below overwrites FETCH_HEAD
  oid="$(git rev-parse FETCH_HEAD)"
  fetch_origin_branch "$base"
  git worktree add --no-track -q -b "review/pr-$n" "$dest" "$oid"

  if [ "$json" = 1 ]; then
    print_created_json "$dest" "review/pr-$n" | jq -c --argjson m "$meta" '. + {pr: {number: $m.number, title: $m.title, head: $m.headRefName, base: $m.baseRefName}}'
  else
    jq -r --arg path "$dest" '"  path:   \($path)\n  PR:     #\(.number) \(.title)\n  branch: \(.headRefName)\n  base:   \(.baseRefName)"' <<<"$meta" >&2
  fi
}
