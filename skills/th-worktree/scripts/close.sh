# shellcheck shell=bash
# shellcheck source=lib.sh source-path=SCRIPTDIR
# shellcheck disable=SC2154 # $repo is set by resolve_repo in lib.sh

# Names in pr-reviews/pr-<n>/ (dir $1) other than code, one per line.
pr_dir_names() {
  local f
  for f in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    { [ -e "$f" ] || [ -L "$f" ]; } && [ "${f##*/}" != code ] && printf '%s\n' "${f##*/}"
  done
  return 0
}

# Prints the commit branch $1 was created at (its oldest reflog entry); nothing without a reflog, or if expiry dropped the creation entry (the oldest left is then a later commit).
branch_creation_oid() { git reflog show --format='%H %gs' "refs/heads/$1" 2>/dev/null | tail -1 | awk '$2 == "branch:" && $3 == "Created" { print $1 }'; }

# True if branch $1 is review/pr-<n> and $2 is the PR worktree path for that same <n> under root $3.
is_pr_worktree() {
  local n="${1#review/pr-}"
  [ "$n" != "$1" ] || return 1
  case "$n" in ""|*[!0-9]*|0*) return 1 ;; esac
  [ "$2" = "${3}pr-reviews/pr-$n/code" ]
}

# True if $1 (a trailing / is dropped) is a symlink, or a directory with nothing but symlinks and directories in it.
only_links() {
  local f="${1%/}" hit
  [ -L "$f" ] && return 0
  [ -d "$f" ] || return 1
  # a find error (unreadable subdir) keeps the entry listed: it may hold real files
  hit="$(find "$f" ! -type l ! -type d -print -quit 2>/dev/null)" && [ -z "$hit" ]
}

# Prints "<head_oid>\t<branch>" (branch empty if detached) for the worktree at resolved path $1; nothing if none.
# Kept out of $(...): bash 3.2 mis-parses case inside command substitution.
worktree_at_path() {
  local target="$1" wt_path="" head="" line
  { git worktree list --porcelain || die 1 "git worktree list failed"; } | while IFS= read -r line; do
    case "$line" in
      "worktree "*) wt_path="${line#worktree }"; head="" ;;
      "HEAD "*) head="${line#HEAD }" ;;
      "branch "*) [ "$wt_path" != "$target" ] || printf '%s\t%s\n' "$head" "${line#branch refs/heads/}" ;;
      detached) [ "$wt_path" != "$target" ] || printf '%s\t\n' "$head" ;;
    esac
  done
}

close_worktree() {
  local arg="" branch="" path_arg="" detached=false wt_info="" json=0 yes=0 force=0 remote=false prs=null pr covered lost path root default row oid why="" err here dirty merged missing unpushed ignored=[] out shown ent unreadable=false kept="" del_wt=true del_br=false what is_pr=false left=[] created="" after_pr=null pr_n=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      --yes) yes=1 ;;
      --force) force=1 ;;
      --remote) remote=true ;;
      -*) bad_arg "$1" ;;
      *) [ -z "$arg" ] || bad_arg "$1"; arg="$1" ;;
    esac
    shift
  done
  [ -n "$arg" ] || bad_usage "missing <branch> or <path>"
  case "$arg" in
    /*|.*) path_arg="$arg" ;;
    *)
      branch="$arg"
      git check-ref-format "refs/heads/$branch" || die 2 "invalid branch name: $branch" ;;
  esac
  resolve_repo
  root="$(worktrees_root)"
  if [ -n "$path_arg" ]; then
    case "$path_arg" in /*) ;; *) path_arg="${PWD%/}/$path_arg" ;; esac
    [ "$path_arg" = / ] || path_arg="${path_arg%/}"
    path_arg="$(canonical_dir "$path_arg")" || die 4 "cannot resolve path: $arg"
    wt_info="$(worktree_at_path "$path_arg")"
    [ -n "$wt_info" ] || die 4 "no worktree at $path_arg under $root"
    IFS=$'\t' read -r oid branch <<<"$wt_info"
    [ -n "$branch" ] || detached=true
  fi
  if [ "$detached" = true ]; then
    [ "$remote" = false ] || die 2 "--remote needs a branch: $path_arg has a detached HEAD"
    default="$(local_default_branch)"
    row="$(list_rows "$root" "$default" "$prs" "$remote" "$path_arg")"
  else
    # read before anything else: a commit that lands later must not be deleted with the branch
    oid="$(git rev-parse --verify -q "refs/heads/$branch")" || die 4 "no worktree for branch $branch under $root"
    if [ "$remote" = true ]; then load_remote 1000 "$branch"; else default="$(local_default_branch)"; fi
    row="$(list_rows "$root" "$default" "$prs" "$remote" "${path_arg:-$branch}")"
  fi
  if [ -z "$row" ]; then
    if [ -n "$path_arg" ]; then die 4 "no worktree at $path_arg under $root"
    else die 4 "no worktree for branch $branch under $root"; fi
  fi
  # path goes last: read splits on tabs, so a path with spaces stays whole
  # covered: the PR was merged and no local commit came after it, so unpushed commits are in the PR
  IFS=$'\t' read -r dirty merged missing covered pr path < <(jq -r '[.dirty, .merged, .missing, (.pr.state == "MERGED" and .pr.ahead == false), (.pr | tojson), .path] | map(tostring) | join("\t")' <<<"$row")
  [ "$dirty" != null ] || [ "$missing" = true ] || unreadable=true
  # a PR worktree is review/pr-<n> at pr-reviews/pr-<n>/code; the other files in pr-reviews/pr-<n>/ outlive it
  if [ "$detached" = false ] && is_pr_worktree "$branch" "$path" "$root"; then
    is_pr=true
    left="$(pr_dir_names "${path%/code}" | jq -R -s -c 'split("\n") | map(select(length > 0))')"
    created="$(branch_creation_oid "$branch")"
  fi
  # commits of mine after the PR: from the branch's creation (first reflog entry) to its tip, minus what origin already has (a merged-in base, or pushed work); unknown (null) without a reflog
  [ -z "$created" ] || after_pr="$(git rev-list --count "$oid" --not "$created" --remotes=origin 2>/dev/null)" || after_pr=null
  # ignored files are deleted with the directory but never block; only names are read (directories come collapsed). -z (in wt_status): git does not quote names
  if [ "$missing" = false ] && out="$(wt_status "$path" --ignored --untracked-files=normal 2>/dev/null)"; then
    # a symlink, or a collapsed dir holding only symlinks (docs/ for docs/local), is a link to the main checkout: deleting it loses nothing
    shown=""
    while IFS= read -r -d $'\1' ent; do
      [[ "$ent" == '!! '* ]] || continue
      only_links "$path/${ent:3}" || shown="$shown${ent:3}"$'\1'
    done <<<"$out"
    ignored="$(printf '%s' "$shown" | jq -R -s -c 'split("\u0001") | map(select(length > 0))')"
  elif [ "$missing" = false ]; then ignored=null; fi
  # a PR worktree has no unpushed count: after_pr takes its place
  if [ "$is_pr" = true ]; then lost="$after_pr" unpushed=null
  elif [ "$detached" = true ]; then
    unpushed="$(git rev-list --count "$oid" --not --branches --remotes=origin)"
    lost="$unpushed"
  else
    unpushed="$(git rev-list --count "$oid" --not --remotes=origin)"
    lost="$unpushed"
    [ "$covered" = false ] || lost=0
  fi
  if { [ "$dirty" = true ] || [ "$unreadable" = true ] || [ "$lost" != 0 ]; } && [ "$force" = 0 ]; then del_wt=false
  elif [ "$detached" = true ]; then :
  elif [ "$is_pr" = true ] && [ "$lost" = 0 ]; then del_br=true
  # only reachable with --force: the branch may hold commits of mine that nothing else has
  elif [ "$is_pr" = true ]; then kept="it may have commits of yours after the PR"
  elif [ "$covered" = false ] && [ "$merged" = null ]; then kept="default branch unknown (try: git remote set-head origin -a)"
  elif [ "$covered" = false ] && [ "$merged" = false ]; then kept="not contained in $default$([ "$remote" = false ] || jq -r 'if . == null then " and it has no PR" elif .state == "MERGED" and .ahead == true then " and it has local commits after its merged PR #\(.number)" elif .state == "MERGED" then " and the head of its merged PR #\(.number) is not fetched locally" else " and its PR #\(.number) is \(.state)" end' <<<"$pr")"
  # a branch checked out elsewhere must survive: update-ref would leave that worktree on a dangling branch
  elif [ "$(git worktree list --porcelain | grep -cxF "branch refs/heads/$branch" || true)" -gt 1 ]; then kept="still checked out in another worktree"
  elif [ "$branch" = "${default#origin/}" ]; then kept="it is origin's default branch"
  else del_br=true; fi
  if [ "$del_wt" = false ]; then
    [ "$dirty" != true ] || why="uncommitted changes"
    if [ "$lost" = 0 ]; then :
    elif [ "$detached" = true ]; then why="${why:+$why and }$lost commit(s) only in its detached HEAD"
    elif [ "$is_pr" = false ]; then why="${why:+$why and }$lost unpushed commit(s)"
    elif [ "$lost" = null ]; then why="${why:+$why and }cannot tell whether you have commits after the PR"
    else why="${why:+$why and }$lost commit(s) of yours after the PR"; fi
    [ -z "$why" ] || why="$why in $path"
    [ "$unreadable" = false ] || why="${why:+$why; }cannot read git status of $path"
  fi
  if [ "$yes" = 1 ]; then
    here="$(pwd -P)"
    case "$here/" in "$path/"*) die 4 "cannot close $path from inside it: run close from another directory" ;; esac
    [ "$del_wt" = true ] || die 4 "$why (use --force to close anyway)"
    # codegraph's index is untracked, and git refuses to remove a worktree with untracked files; a symlink may point to the main checkout's index, and anything tracked there must not be deleted: leave those (an ignored index goes with the worktree); no `codegraph uninit`: it also removes the git hooks that every worktree of the repo shares
    if [ -d "$path/.codegraph" ] && [ ! -L "$path/.codegraph" ] && [ -z "$(git -C "$path" ls-files -- .codegraph)" ]; then
      rm -rf "$path/.codegraph"
    fi
    if [ "$force" = 1 ]; then git worktree remove --force "$path" || die 4 "git could not remove $path (see git's message above)"
    else git worktree remove "$path" || die 4 "git could not remove $path (see git's message above)"; fi
    # rmdir only removes an empty directory: anything else in pr-reviews/pr-<n>/ stays
    [ "$is_pr" = false ] || rmdir "${path%/code}" 2>/dev/null || true
    if [ "$detached" = true ]; then
      pr_n="${path%/code}"
      pr_n="${pr_n##*/pr-}"
      if is_pr_worktree "review/pr-$pr_n" "$path" "$root"; then
        rmdir "${path%/code}" 2>/dev/null || true
        if git show-ref --verify --quiet "refs/heads/review/pr-$pr_n"; then
          echo "th-wt: branch review/pr-$pr_n kept (detached HEAD); to reopen PR $pr_n with th-wt pr, delete it first: git branch -D review/pr-$pr_n" >&2
        fi
      fi
    fi
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
    if [ "$del_br" = false ] && [ "$detached" = false ]; then echo "th-wt: branch $branch kept: $kept" >&2; fi
  fi
  if [ "$json" = 1 ]; then
    jq -n --arg path "$path" --arg branch "$branch" --argjson detached "$detached" --argjson merged "$merged" --argjson dirty "$dirty" --argjson missing "$missing" --argjson ignored "$ignored" \
      --argjson unpushed "$unpushed" --argjson wt "$del_wt" --argjson br "$del_br" --argjson remote "$remote" --argjson pr "$pr" --argjson is_pr "$is_pr" --argjson left "${left:-[]}" --argjson after "$after_pr" \
      '{path: $path, branch: (if $detached then null else $branch end), merged: $merged, dirty: $dirty, missing: $missing, ignored: $ignored, unpushed: $unpushed, delete: {worktree: $wt, branch: $br}}
       + if $remote then {pr: $pr} else {} end
       + if $is_pr then {kept: $left, after_pr: $after} else {} end
       | if $is_pr then del(.unpushed) else . end'
    return 0
  fi
  if [ "$del_wt" = false ]; then what="nothing (blocked: $why)"
  elif [ "$detached" = true ]; then what="worktree only (detached HEAD, no branch)"
  elif [ "$del_br" = true ]; then what="worktree and branch"
  else what="worktree only (branch kept: $kept)"; fi
  {
    if [ "$detached" = true ]; then
      echo "  branch:    (detached)"
    else
      echo "  branch:    $branch"
    fi
    echo "  path:      $path"
    [ "$missing" = false ] || echo "  missing:   directory already gone; closing only cleans git's registration"
    echo "  merged:    ${merged/null/unknown}"
    echo "  dirty:     ${dirty/null/unknown}"
    if [ "$is_pr" = true ]; then
      echo "  after PR:  ${after_pr/null/unknown} commits of yours"
      # --no-pager: stderr is the terminal, and git would open a pager there when run by hand
      { [ -z "$created" ] || [ "$after_pr" = 0 ]; } || git --no-pager log -10 --format='             %h %s' "$oid" --not "$created" --remotes=origin >&2
    elif [ "$detached" = true ]; then
      echo "  unpushed:  $unpushed commits only in this HEAD"
    else
      echo "  unpushed:  $unpushed commits$([ "$covered" = false ] || [ "$unpushed" = 0 ] || echo " (all in the PR)")"
    fi
    if [ "$remote" = true ]; then
      # a branch already contained in the default one is not looked up (same as list --remote)
      echo "  pr:        $(jq -r --arg d "${default#origin/}" --arg m "$merged" 'if . == null then (if $m == "true" then "not checked (already contained in \($d))" else "none" end) else "#\(.number) \(.state) (base \(.base)\(if .base != $d then ", not the default branch" else "" end))\(if .ahead == null then ", PR head not fetched" elif .ahead then ", local commits after it" else "" end)" end' <<<"$pr")"
    fi
    echo "  ignored:   $(jq -r 'if . == null then "unknown" elif length == 0 then "none" else join(", ") end' <<<"$ignored")"
    [ "$is_pr" = false ] || echo "  kept:      $(jq -r 'if length == 0 then "none" else join(", ") end' <<<"${left:-[]}") (in ${path%/code})"
    echo "  delete:    $what"
    if [ "$yes" = 1 ]; then echo "closed $path"; else echo "Dry run: nothing deleted. Add --yes to close."; fi
  } >&2
}
