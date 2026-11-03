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
  command -v gh >/dev/null || die 3 "missing dependency: gh"

  meta="$(gh pr view "$n" -R "$repo" --json number,title,headRefName,baseRefName)" || die 4 "PR not found, not authenticated, or no access?"
  jq -e 'type == "object" and (.number | type == "number") and all(.title, .headRefName, .baseRefName; type == "string") and (.baseRefName | length > 0)' <<<"$meta" >/dev/null 2>&1 || die 4 "unexpected output from gh pr view"
  base="$(jq -r .baseRefName <<<"$meta")"
  # base goes into a refspec: refuse anything git would not accept as a branch name
  git check-ref-format "refs/heads/$base" || die 4 "unexpected output from gh pr view"
  git fetch -q --no-tags origin "refs/pull/$n/head" || die 4 "fetch of PR #$n failed (origin unreachable, no access, or the PR has no head ref)"
  # read before the base fetch below overwrites FETCH_HEAD
  oid="$(git rev-parse FETCH_HEAD)"
  fetch_origin_branch "$base" || die 4 "fetch of origin/$base failed"
  git worktree add --no-track -q -b "review/pr-$n" "$dest" "$oid"

  if [ "$json" = 1 ]; then
    print_created_json "$dest" "review/pr-$n" | jq -c --argjson m "$meta" '. + {pr: {number: $m.number, title: $m.title, head: $m.headRefName, base: $m.baseRefName}}'
  else
    jq -r --arg path "$dest" '"  path:   \($path)\n  PR:     #\(.number) \(.title)\n  branch: \(.headRefName)\n  base:   \(.baseRefName)"' <<<"$meta" >&2
  fi
}
