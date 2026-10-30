# shellcheck shell=bash
# shellcheck source=lib.sh source-path=SCRIPTDIR
# shellcheck disable=SC2154 # $repo is set by resolve_repo in lib.sh

close_worktree() {
  local branch="" json=0 yes=0 force=0 path root default row oid why here dirty merged missing unpushed ignored=[] out unreadable=false del_wt=true del_br=false what
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      --yes) yes=1 ;;
      --force) force=1 ;;
      -*) bad_usage ;;
      *) [ -z "$branch" ] || bad_usage; branch="$1" ;;
    esac
    shift
  done
  [ -n "$branch" ] || bad_usage
  resolve_repo
  root="$(worktrees_root)"
  # read before anything else: a commit that lands later must not be deleted with the branch
  oid="$(git rev-parse --verify -q "refs/heads/$branch")" || die 4 "no worktree for branch $branch under $root"
  default="$(local_default_branch)"
  row="$(list_rows "$root" "$default" null false "$branch")"
  [ -n "$row" ] || die 4 "no worktree for branch $branch under $root"
  # path goes last: read splits on tabs, so a path with spaces stays whole
  IFS=$'\t' read -r dirty merged missing path < <(jq -r '[.dirty, .merged, .missing, .path] | map(tostring) | join("\t")' <<<"$row")
  [ "$dirty" != null ] || [ "$missing" = true ] || unreadable=true
  # ignored files are deleted with the directory but never block; only names are read (directories come collapsed)
  if [ "$missing" = false ] && out="$(git -c core.quotePath=false --no-optional-locks -C "$path" status --porcelain --ignored --untracked-files=normal 2>/dev/null)"; then
    ignored="$(printf '%s\n' "$out" | jq -R -n -c '[inputs | select(startswith("!! ")) | .[3:]]')"
  fi
  unpushed="$(git rev-list --count "$oid" --not --remotes=origin)"
  if { [ "$dirty" = true ] || [ "$unreadable" = true ] || [ "$unpushed" != 0 ]; } && [ "$force" = 0 ]; then del_wt=false
  elif [ "$merged" = true ]; then del_br=true; fi
  if [ "$yes" = 1 ]; then
    here="$(pwd -P)"
    case "$here/" in "$path/"*) die 4 "cannot close $path from inside it: run close from another directory" ;; esac
    if [ "$del_wt" = false ]; then
      why=""
      [ "$dirty" != true ] || why="uncommitted changes"
      [ "$unpushed" = 0 ] || why="${why:+$why and }$unpushed unpushed commit(s)"
      [ -z "$why" ] || why="$why in $path"
      [ "$unreadable" = false ] || why="${why:+$why; }cannot read git status of $path"
      die 4 "$why (use --force to close anyway)"
    fi
    if [ "$force" = 1 ]; then git worktree remove --force "$path" || die 4 "git could not remove $path (locked?)"
    else git worktree remove "$path" || die 4 "git could not remove $path (locked?)"; fi
    if [ "$del_br" = true ]; then
      # update-ref only deletes if the branch still points at $oid; otherwise a commit arrived meanwhile
      if ! git update-ref -d "refs/heads/$branch" "$oid" 2>/dev/null; then
        del_br=false
        echo "th-wt: branch $branch kept: it moved while closing" >&2
      fi
    elif [ "$merged" = null ]; then echo "th-wt: branch $branch kept: default branch unknown (try: git remote set-head origin -a)" >&2
    else echo "th-wt: branch $branch kept: not contained in $default" >&2; fi
  fi
  if [ "$json" = 1 ]; then
    jq -n --arg path "$path" --arg branch "$branch" --argjson merged "$merged" --argjson dirty "$dirty" --argjson missing "$missing" --argjson ignored "$ignored" \
      --argjson unpushed "$unpushed" --argjson wt "$del_wt" --argjson br "$del_br" \
      '{path: $path, branch: $branch, merged: $merged, dirty: $dirty, missing: $missing, ignored: $ignored, unpushed: $unpushed, delete: {worktree: $wt, branch: $br}}'
    return 0
  fi
  if [ "$del_wt" = false ]; then what="nothing (blocked by uncommitted changes or unpushed commits)"
  elif [ "$del_br" = true ]; then what="worktree and branch"
  elif [ "$merged" = true ]; then what="worktree only (branch kept: it moved while closing)" # only reachable after the race
  elif [ "$merged" = null ]; then what="worktree only (branch kept: default branch unknown)"
  else what="worktree only (branch kept: not merged)"; fi
  {
    echo "  branch:    $branch"
    echo "  path:      $path"
    [ "$missing" = false ] || echo "  missing:   directory already gone; closing only cleans git's registration"
    echo "  merged:    ${merged/null/unknown}"
    echo "  dirty:     ${dirty/null/unknown}"
    echo "  unpushed:  $unpushed commits"
    echo "  ignored:   $(jq -r 'if length == 0 then "none" else join(", ") end' <<<"$ignored")"
    echo "  delete:    $what"
    if [ "$yes" = 1 ]; then echo "closed $path"; else echo "Dry run: nothing deleted. Add --yes to close."; fi
  } >&2
}
