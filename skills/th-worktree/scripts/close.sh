# shellcheck shell=bash
# shellcheck source=lib.sh source-path=SCRIPTDIR
# shellcheck disable=SC2154 # $repo is set by resolve_repo in lib.sh

close_worktree() {
  local branch="" json=0 yes=0 force=0 remote=false prs=null pr covered lost path root default row oid why="" err here dirty merged missing unpushed ignored=[] out unreadable=false kept="" del_wt=true del_br=false what
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      --yes) yes=1 ;;
      --force) force=1 ;;
      --remote) remote=true ;;
      -*) bad_usage ;;
      *) [ -z "$branch" ] || bad_usage; branch="$1" ;;
    esac
    shift
  done
  [ -n "$branch" ] || bad_usage
  git check-ref-format "refs/heads/$branch" || die 2 "invalid branch name: $branch"
  resolve_repo
  root="$(worktrees_root)"
  # read before anything else: a commit that lands later must not be deleted with the branch
  oid="$(git rev-parse --verify -q "refs/heads/$branch")" || die 4 "no worktree for branch $branch under $root"
  if [ "$remote" = true ]; then load_remote 1000 "$branch"; else default="$(local_default_branch)"; fi
  row="$(list_rows "$root" "$default" "$prs" "$remote" "$branch")"
  [ -n "$row" ] || die 4 "no worktree for branch $branch under $root"
  # path goes last: read splits on tabs, so a path with spaces stays whole
  # covered: the PR was merged and no local commit came after it, so unpushed commits are in the PR
  IFS=$'\t' read -r dirty merged missing covered pr path < <(jq -r '[.dirty, .merged, .missing, (.pr.state == "MERGED" and .pr.ahead == false), (.pr | tojson), .path] | map(tostring) | join("\t")' <<<"$row")
  [ "$dirty" != null ] || [ "$missing" = true ] || unreadable=true
  # ignored files are deleted with the directory but never block; only names are read (directories come collapsed). -z: git does not quote names; tr because $(...) drops NUL bytes
  if [ "$missing" = false ] && out="$(git --no-optional-locks -C "$path" status --porcelain -z --ignored --untracked-files=normal 2>/dev/null | tr '\0' '\1')"; then
    ignored="$(printf '%s' "$out" | jq -R -s -c 'split("\u0001") | map(select(startswith("!! ")) | .[3:])')"
  elif [ "$missing" = false ]; then ignored=null; fi
  unpushed="$(git rev-list --count "$oid" --not --remotes=origin)"
  lost="$unpushed"
  [ "$covered" = false ] || lost=0
  if { [ "$dirty" = true ] || [ "$unreadable" = true ] || [ "$lost" != 0 ]; } && [ "$force" = 0 ]; then del_wt=false
  elif [ "$covered" = false ] && [ "$merged" = null ]; then kept="default branch unknown (try: git remote set-head origin -a)"
  elif [ "$covered" = false ] && [ "$merged" = false ]; then kept="not contained in $default$([ "$remote" = false ] || jq -r 'if . == null then " and it has no PR" elif .state == "MERGED" and .ahead == true then " and it has local commits after its merged PR #\(.number)" elif .state == "MERGED" then " and the head of its merged PR #\(.number) is not fetched locally" else " and its PR #\(.number) is \(.state)" end' <<<"$pr")"
  # a branch checked out elsewhere must survive: update-ref would leave that worktree on a dangling branch
  elif [ "$(git worktree list --porcelain | grep -cxF "branch refs/heads/$branch" || true)" -gt 1 ]; then kept="still checked out in another worktree"
  else del_br=true; fi
  if [ "$del_wt" = false ]; then
    [ "$dirty" != true ] || why="uncommitted changes"
    [ "$lost" = 0 ] || why="${why:+$why and }$lost unpushed commit(s)"
    [ -z "$why" ] || why="$why in $path"
    [ "$unreadable" = false ] || why="${why:+$why; }cannot read git status of $path"
  fi
  if [ "$yes" = 1 ]; then
    here="$(pwd -P)"
    case "$here/" in "$path/"*) die 4 "cannot close $path from inside it: run close from another directory" ;; esac
    [ "$del_wt" = true ] || die 4 "$why (use --force to close anyway)"
    if [ "$force" = 1 ]; then git worktree remove --force "$path" || die 4 "git could not remove $path (see git's message above)"
    else git worktree remove "$path" || die 4 "git could not remove $path (see git's message above)"; fi
    if [ "$del_br" = true ]; then
      # update-ref only deletes if the branch still points at $oid; otherwise a commit arrived meanwhile
      if err="$(git update-ref -d "refs/heads/$branch" "$oid" 2>&1)"; then
        git config --remove-section "branch.$branch" 2>/dev/null || true
      else
        del_br=false
        if [ "$(git rev-parse --verify -q "refs/heads/$branch" || true)" != "$oid" ]; then kept="it moved while closing"
        else kept="git could not delete it: ${err//$'\n'/ }"; fi
      fi
    fi
    [ "$del_br" = true ] || echo "th-wt: branch $branch kept: $kept" >&2
  fi
  if [ "$json" = 1 ]; then
    jq -n --arg path "$path" --arg branch "$branch" --argjson merged "$merged" --argjson dirty "$dirty" --argjson missing "$missing" --argjson ignored "$ignored" \
      --argjson unpushed "$unpushed" --argjson wt "$del_wt" --argjson br "$del_br" --argjson remote "$remote" --argjson pr "$pr" \
      '{path: $path, branch: $branch, merged: $merged, dirty: $dirty, missing: $missing, ignored: $ignored, unpushed: $unpushed, delete: {worktree: $wt, branch: $br}}
       + if $remote then {pr: $pr} else {} end'
    return 0
  fi
  if [ "$del_wt" = false ]; then what="nothing (blocked: $why)"
  elif [ "$del_br" = true ]; then what="worktree and branch"
  else what="worktree only (branch kept: $kept)"; fi
  {
    echo "  branch:    $branch"
    echo "  path:      $path"
    [ "$missing" = false ] || echo "  missing:   directory already gone; closing only cleans git's registration"
    echo "  merged:    ${merged/null/unknown}"
    echo "  dirty:     ${dirty/null/unknown}"
    echo "  unpushed:  $unpushed commits$([ "$covered" = false ] || [ "$unpushed" = 0 ] || echo " (all in the PR)")"
    if [ "$remote" = true ]; then
      # a branch already contained in the default one is not looked up (same as list --remote)
      echo "  pr:        $(jq -r --arg d "${default#origin/}" --arg m "$merged" 'if . == null then (if $m == "true" then "not checked (already contained in \($d))" else "none" end) else "#\(.number) \(.state) (base \(.base)\(if .base != $d then ", not the default branch" else "" end))\(if .ahead == null then ", PR head not fetched" elif .ahead then ", local commits after it" else "" end)" end' <<<"$pr")"
    fi
    echo "  ignored:   $(jq -r 'if . == null then "unknown" elif length == 0 then "none" else join(", ") end' <<<"$ignored")"
    echo "  delete:    $what"
    if [ "$yes" = 1 ]; then echo "closed $path"; else echo "Dry run: nothing deleted. Add --yes to close."; fi
  } >&2
}
