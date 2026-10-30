# shellcheck shell=bash
# shellcheck source=lib.sh source-path=SCRIPTDIR
# shellcheck disable=SC2154 # $repo is set by resolve_repo in lib.sh

list_worktrees() {
  local default root rows base pr_limit=100 json=0 remote=false prs=null
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1; shift ;;
      --remote) remote=true; shift ;;
      *) bad_usage ;;
    esac
  done
  resolve_repo
  # shortcut: root is compared with git's real paths without resolving symlinks, so a symlinked ~/.worktrees or $HOME lists nothing; canonicalize both sides with #8 (configurable root)
  root="$HOME/.worktrees/$repo/"
  if [ "$remote" = true ]; then
    command -v gh >/dev/null || die 3 "missing dependency: gh"
    base="$(origin_default_branch)" || die 4 "cannot read origin (unreachable or no access)"
    [ -n "$base" ] || die 4 "cannot determine origin's default branch"
    fetch_origin_branch "$base" || die 4 "fetch of origin/$base failed"
    default="origin/$base"
    prs="$(gh pr list -R "$repo" --state all --limit "$pr_limit" --json number,state,baseRefName,headRefName,headRefOid,isCrossRepository)" || die 4 "gh pr list failed (not authenticated, or no access to GitHub or $repo?)"
    jq -e 'type == "array" and all(.[]; type == "object")' <<<"$prs" >/dev/null 2>&1 || die 4 "unexpected output from gh pr list"
  else
    default="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
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
