# shellcheck shell=bash
# shellcheck source=lib.sh source-path=SCRIPTDIR
# shellcheck disable=SC2154 # $repo is set by resolve_repo in lib.sh

list_worktrees() {
  local default root rows pr_limit=100 json=0 remote=false prs=null
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1; shift ;;
      --remote) remote=true; shift ;;
      *) bad_arg "$1" ;;
    esac
  done
  resolve_repo
  root="$(worktrees_root)"
  if [ "$remote" = true ]; then
    load_remote "$pr_limit"
  else
    default="$(local_default_branch)"
  fi
  rows="$(list_rows "$root" "$default" "$prs" "$remote")"
  # shortcut: PRs are matched within the latest $pr_limit only; make the limit configurable with #8
  if [ "$remote" = true ] && [ "$(jq length <<<"$prs")" = "$pr_limit" ] && [ "$(printf '%s\n' "$rows" | jq -s 'any(.[]; .branch != null and .merged == false and .pr == null)')" = true ]; then
    echo "th-wt: only the $pr_limit most recent PRs were checked; branches without a PR here may have an older one" >&2
  fi
  if [ "$json" = 1 ]; then
    printf '%s\n' "$rows" | jq -s --arg repo "$repo" '{repo: $repo, worktrees: .}'
  elif [ -z "$rows" ]; then
    echo "no worktrees under $root" >&2
  else
    printf '%s\n' "$rows" | jq -r --arg default "$default" \
      '"\(.branch // "(detached)")  \(if .missing then "missing" elif .dirty == null then "dirty unknown" elif .dirty then "dirty" else "clean" end)  \(if .merged == null then "containment unknown" elif .merged then "contained in \($default)" else "not contained in \($default)" end)  \(if .pr then "PR #\(.pr.number) \(.pr.state) (base \(.pr.base))\(if .pr.ahead == null then ", PR head not fetched" elif .pr.ahead then ", local commits after it" else "" end)  " else "" end)\(.path)"' >&2
  fi
}
