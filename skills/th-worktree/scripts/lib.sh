# shellcheck shell=bash

# Initialized here so values inherited from the environment cannot change behavior (undo_creation, print_created_json).
created_start=""
linked=()
deps_prefix=""
# Same for the settings load_config sets (a wt_root, install_deps_on or codegraph_mode or pr_limit in the environment is ignored).
wt_root=""
install_deps_on=1
codegraph_mode=auto
pr_limit=500

die() { echo "th-wt: $2" >&2; exit "$1"; }
bad_usage() { [ $# -eq 0 ] || echo "th-wt: $1" >&2; usage >&2; exit 2; }
# For an argument no option arm matched: -h/--help prints usage (exit 0), anything else is a usage error.
bad_arg() {
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -*) bad_usage "unknown option: $1" ;;
    *) bad_usage "unexpected argument: $1" ;;
  esac
}

# Validates the value $2 of config key $1. On success sets $cfg_value (the root expanded, without a trailing slash); on failure sets $reason and returns 1. Reads the caller's (load_config) locals via dynamic scope.
check_config_value() {
  local v="$2"
  cfg_value="$v"
  case "$1" in
    TH_WORKTREES_ROOT)
      case "$2" in *[[:cntrl:]]*) reason="TH_WORKTREES_ROOT must not contain control characters"; return 1 ;; esac
      case "$v" in \~/*) v="${HOME%/}/${v#\~/}" ;; esac
      v="${v%/}"
      # absolute only; wrapping in slashes catches '.', '..' and empty segments in one pattern
      case "$v" in
        /*) ;;
        *) reason="TH_WORKTREES_ROOT must be an absolute path or start with ~/, without '.', '..' or empty segments: $2"; return 1 ;;
      esac
      case "$v/" in
        *//*|*/./*|*/../*) reason="TH_WORKTREES_ROOT must be an absolute path or start with ~/, without '.', '..' or empty segments: $2"; return 1 ;;
      esac
      cfg_value="$v" ;;
    TH_INSTALL_DEPS)
      case "$2" in
        0|1) ;;
        *) reason="TH_INSTALL_DEPS must be 0 or 1: $2"; return 1 ;;
      esac ;;
    TH_CODEGRAPH)
      case "$2" in
        auto|off) ;;
        *) reason="TH_CODEGRAPH must be auto or off: $2"; return 1 ;;
      esac ;;
    TH_PR_LIMIT)
      case "$2" in
        ""|*[!0-9]*|0*) reason="TH_PR_LIMIT must be an integer >= 100: $2"; return 1 ;;
      esac
      if [ "$2" -lt 100 ]; then
        reason="TH_PR_LIMIT must be an integer >= 100: $2"
        return 1
      fi ;;
  esac
}

# Sets $wt_root (canonical, so it matches git's real paths), $install_deps_on and $codegraph_mode: environment variable (if non-empty) > $XDG_CONFIG_HOME/th-worktools/config > default.
# Validates everything first (exit 4, naming the file and line or the variable); the file is parsed line by line, never sourced.
load_config() {
  local conf="${XDG_CONFIG_HOME:-$HOME/.config}/th-worktools/config" line key n=0 reason cfg_value
  local file_root="" file_deps="" file_cg="" file_pr_limit=""
  if [ -f "$conf" ]; then
    # the last line may lack a newline
    while IFS= read -r line || [ -n "$line" ]; do
      n=$((n + 1))
      line="${line%$'\r'}" # CRLF files
      case "$line" in ""|"#"*) continue ;; esac
      # neither the line nor the value of an unknown key is printed: it could be a secret
      case "$line" in *=*) ;; *) die 4 "$conf:$n: expected KEY=value" ;; esac
      key="${line%%=*}"
      case "$key" in
        TH_WORKTREES_ROOT|TH_INSTALL_DEPS|TH_CODEGRAPH|TH_PR_LIMIT) ;;
        ""|[[:digit:]]*|*[![:upper:][:digit:]_]*) die 4 "$conf:$n: invalid key (not shown)" ;;
        *) die 4 "$conf:$n: unknown key: $key" ;;
      esac
      check_config_value "$key" "${line#*=}" || die 4 "$conf:$n: $reason"
      case "$key" in
        TH_WORKTREES_ROOT) file_root="$cfg_value" ;;
        TH_INSTALL_DEPS) file_deps="$cfg_value" ;;
        TH_CODEGRAPH) file_cg="$cfg_value" ;;
        TH_PR_LIMIT) file_pr_limit="$cfg_value" ;;
      esac
    done < "$conf"
  fi
  wt_root="${file_root:-${HOME%/}/.worktrees}"
  install_deps_on="${file_deps:-1}"
  codegraph_mode="${file_cg:-auto}"
  pr_limit="${file_pr_limit:-500}"
  if [ -n "${TH_WORKTREES_ROOT:-}" ]; then
    check_config_value TH_WORKTREES_ROOT "$TH_WORKTREES_ROOT" || die 4 "TH_WORKTREES_ROOT (environment): $reason"
    wt_root="$cfg_value"
  fi
  if [ -n "${TH_INSTALL_DEPS:-}" ]; then
    check_config_value TH_INSTALL_DEPS "$TH_INSTALL_DEPS" || die 4 "TH_INSTALL_DEPS (environment): $reason"
    install_deps_on="$cfg_value"
  fi
  if [ -n "${TH_CODEGRAPH:-}" ]; then
    check_config_value TH_CODEGRAPH "$TH_CODEGRAPH" || die 4 "TH_CODEGRAPH (environment): $reason"
    codegraph_mode="$cfg_value"
  fi
  if [ -n "${TH_PR_LIMIT:-}" ]; then
    check_config_value TH_PR_LIMIT "$TH_PR_LIMIT" || die 4 "TH_PR_LIMIT (environment): $reason"
    pr_limit="$cfg_value"
  fi
  # resolved here, in the main shell, so a failure exits the whole command before anything is created
  cfg_value="$wt_root"
  wt_root="$(canonical_dir "$cfg_value")" || die 4 "cannot resolve the worktrees root: $cfg_value"
}

# Sets $repo (<owner>/<repo>) from remote.origin.url; loads the global config first.
resolve_repo() {
  local url
  load_config
  git rev-parse --git-dir >/dev/null 2>&1 || die 4 "not a git repository"
  url="$(git config --get remote.origin.url || true)"
  [ -n "$url" ] || die 4 "no 'origin' remote configured"
  repo="$(printf '%s' "$url" | sed -E 's#^(git@[^:]+:|https?://[^/]+/)##; s#\.git$##')"
  case "/$repo/" in
    *[:@]*|*//*|*/./*|*/../*) die 4 "unsupported origin URL: $url" ;;
    /*/*/) ;;
    *) die 4 "unsupported origin URL: $url" ;;
  esac
  check_root_overlap
}

# Exits 4 if the worktrees root of $repo and the main checkout contain one another; needs $repo and $wt_root.
check_root_overlap() {
  local main root="$wt_root/$repo/"
  main="$(git worktree list --porcelain | awk 'NR == 1 { print substr($0, 10) }')"
  # trailing slash on both sides so /a/b does not match /a/bc
  case "$root" in "$main/"*) die 4 "worktrees root $wt_root/$repo overlaps the main checkout $main" ;; esac
  case "$main/" in "$root"*) die 4 "worktrees root $wt_root/$repo overlaps the main checkout $main" ;; esac
}

# Absolute path $1 with symlinks resolved, even if it does not exist yet: the deepest existing ancestor is resolved with cd -P and the missing tail is appended. $1 has no ., .. or empty segments.
canonical_dir() {
  local ancestor="$1" rest="" base
  while [ ! -d "$ancestor" ]; do
    # a symlink that is not a directory (dangling, loop, file) cannot be created through
    ! [ -L "$ancestor" ] || return 1
    rest="/${ancestor##*/}$rest"
    ancestor="${ancestor%/*}"
    [ -n "$ancestor" ] || ancestor=/
  done
  base="$(cd -P "$ancestor" && pwd)" || return 1
  [ "$base" != / ] || base=""
  printf '%s' "$base$rest"
}

# Where this repo's worktrees live; needs $repo from resolve_repo ($wt_root is already canonical).
worktrees_root() { printf '%s' "$wt_root/$repo/"; }

# Sets $dest for branch $1 and checks it does not already exist; needs $repo.
worktree_dest() {
  local name="${1//\//-}"
  # pr-reviews/ holds the PR worktrees; the check is on the normalized name so pr/reviews is reserved too
  [ "$name" != pr-reviews ] || die 2 "reserved branch name: $1 (pr-reviews is where PR worktrees live)"
  dest="$(worktrees_root)$name"
  [ ! -e "$dest" ] || die 4 "destination already exists: $dest"
}

# Creates worktree $2 on a new branch $1 starting at commit-ish $3, with no upstream.
add_branch_worktree() {
  local start
  start="$(git rev-parse --verify -q "$3^{commit}")" || die 1 "git worktree add failed: no commit $3"
  created_start="$start"
  echo "th-wt: creating worktree $2 (branch $1)" >&2
  git worktree add --no-track -q -b "$1" "$2" "$start" && return 0
  # git creates the branch before some failures (e.g. the directory cannot be made); drop it so a retry does not hit
  # "branch already exists", but only while it still points at $start, so a branch made meanwhile by someone else survives
  git update-ref -d "refs/heads/$1" "$start" 2>/dev/null || true
  die 1 "git worktree add failed"
}

# Removes the fresh worktree $1 and, if this command created branch $2 ($created_start is its start commit), the branch while it still points there.
undo_creation() {
  if ! git worktree remove --force "$1" 2>/dev/null; then
    echo "th-wt: warning: could not remove the worktree $1; branch $2 kept" >&2
    return 0
  fi
  [ -z "$created_start" ] || git update-ref -d "refs/heads/$2" "$created_start" 2>/dev/null || true
}

# Checks one .conf entry; on failure sets $reason and returns 1. Reads the caller's (apply_repo_conf) locals via dynamic scope.
check_conf_entry() {
  local i q d rest
  if [ "$action" = deps-prefix ]; then
    if [ -z "$p" ] || [ -n "$extra" ]; then
      reason="expected 'deps-prefix <command>'"
      return 1
    fi
    case "$p" in
      */*) reason="deps-prefix must be a command name in PATH, without '/': $p"; return 1 ;;
    esac
    if [ -n "$dp_line" ]; then
      reason="duplicate deps-prefix (line $dp_line)"
      return 1
    fi
    return 0
  fi
  if [ "$action" != link ]; then
    reason="unknown action '$action' (only 'link' and 'deps-prefix' are supported)"
    return 1
  fi
  if [ -z "$p" ] || [ -n "$extra" ]; then
    reason="expected 'link <path>'"
    return 1
  fi
  # wrapping in slashes catches absolute paths, '.', '..', empty segments and a trailing slash in one pattern
  case "/$p/" in
    //*|*//*|*/./*|*/../*)
      reason="path must be relative, without '.', '..' or empty segments and without a trailing slash: $p"
      return 1 ;;
  esac
  case "$p" in
    *[*?[]*) reason="globs are not supported: $p"; return 1 ;;
  esac
  # an entry equal to or under another would make ln write inside the main checkout
  for ((i = 0; i < ${#paths[@]}; i++)); do
    q="${paths[$i]}"
    case "$p/" in "$q"/*) reason="$p overlaps $q (line ${nums[$i]})"; return 1 ;; esac
    case "$q/" in "$p"/*) reason="$p overlaps $q (line ${nums[$i]})"; return 1 ;; esac
  done
  if [ ! -e "$main/$p" ] && [ ! -L "$main/$p" ]; then
    reason="$p does not exist in the main checkout ($main)"
    return 1
  fi
  # a parent that is a tracked file or symlink would let mkdir/ln escape the worktree
  rest="$p"
  d=""
  while [ "$rest" != "${rest#*/}" ]; do
    d="${d:+$d/}${rest%%/*}"
    rest="${rest#*/}"
    if [ -L "$dest/$d" ] || { [ -e "$dest/$d" ] && [ ! -d "$dest/$d" ]; }; then
      reason="$p: parent $d in the worktree is not a directory"
      return 1
    fi
  done
  # asked before the link exists: git sees a path that is not there as a file, like the symlink it will become
  if ! git -C "$dest" check-ignore -q -- "$p"; then
    if git -C "$dest" check-ignore -q -- "$p/"; then
      reason="$p is ignored only as a directory ('$p/'); git sees a symlink as a file, so ignore '$p' without the trailing slash"
    else
      reason="$p is not ignored by git in the worktree (versioned, or missing from .gitignore)"
    fi
    return 1
  fi
}

# Links the paths listed in this repo's .conf into the fresh worktree $1 (branch $2) as symlinks to the main checkout; sets $linked.
# Validates every line first and links only if all pass; any failure undoes the creation and exits 4. Needs $repo.
apply_repo_conf() {
  local dest="$1" branch="$2" conf="${XDG_CONFIG_HOME:-$HOME/.config}/th-worktools/repos/$repo.conf" main line action p extra reason n=0 i dp_line=""
  local paths=() nums=()
  [ -f "$conf" ] || return 0
  echo "th-wt: applying repo config $conf" >&2
  main="$(git worktree list --porcelain | awk 'NR == 1 { print substr($0, 10) }')"
  # the last line may lack a newline
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line="${line%$'\r'}" # CRLF files
    action="" p="" extra=""
    read -r action p extra <<<"$line"
    case "$action" in ""|"#"*) continue ;; esac
    check_conf_entry || { undo_creation "$dest" "$branch"; die 4 "$conf:$n: $reason"; }
    if [ "$action" = deps-prefix ]; then
      deps_prefix="$p"
      dp_line="$n"
      continue
    fi
    paths+=("$p")
    nums+=("$n")
  done < "$conf"
  for ((i = 0; i < ${#paths[@]}; i++)); do
    p="${paths[$i]}"
    { mkdir -p "$(dirname "$dest/$p")" && ln -s "$main/$p" "$dest/$p"; } || { undo_creation "$dest" "$branch"; die 1 "cannot link $p in $dest"; }
    linked+=("$p")
  done
  for p in ${linked[@]+"${linked[@]}"}; do echo "th-wt: linked $p" >&2; done
}

# Sets $pm and $sub (the install command) from the lockfile in worktree $1; $pm stays empty if there is none (warns about lockfiles of other managers).
detect_pm() {
  local f
  pm=""
  if [ -f "$1/pnpm-lock.yaml" ]; then
    pm=pnpm
    sub=(install --frozen-lockfile)
  elif [ -f "$1/package-lock.json" ]; then
    pm=npm
    sub=(ci)
  else
    for f in yarn.lock bun.lock bun.lockb Cargo.lock uv.lock poetry.lock; do
      [ ! -f "$1/$f" ] || echo "th-wt: warning: unsupported lockfile $f; dependencies not installed in $1" >&2
    done
  fi
}

# Installs the dependencies of worktree $1 from its lockfile; sets $deps. A failed install only warns: the worktree is already there.
install_deps() {
  local dest="$1" pm sub shown bin=
  deps=skipped
  detect_pm "$dest"
  [ -n "$pm" ] || return 0
  if [ "$install_deps_on" = 0 ]; then
    echo "th-wt: dependency install disabled (TH_INSTALL_DEPS=0); dependencies not installed in $dest" >&2
    return 0
  fi
  if ! command -v "$pm" >/dev/null; then
    echo "th-wt: warning: $pm not found in PATH; skipping dependency install in $dest" >&2
    return 0
  fi
  # type -P looks only at executables in PATH: th-wt runs non-interactive and never sees shell functions or aliases
  if [ -n "$deps_prefix" ]; then
    bin="$(type -P "$deps_prefix" || true)"
    # a relative entry in PATH ('.' or empty) gives a relative path: it would resolve in the worktree, i.e. branch code
    case "$bin" in
      /*) ;;
      *)
        echo "th-wt: warning: deps-prefix $deps_prefix is not an executable in PATH (shell functions and aliases do not count); dependencies not installed in $dest" >&2
        return 0 ;;
    esac
  fi
  shown="${deps_prefix:+$deps_prefix }$pm ${sub[*]}"
  echo "th-wt: installing dependencies ($shown)" >&2
  # stdout is reserved for --json and there is no terminal to answer prompts; argv, never eval
  if (cd "$dest" && ${bin:+"$bin"} "$pm" "${sub[@]}" >&2 </dev/null); then
    deps="$pm"
  else
    deps=failed
    echo "th-wt: warning: $pm install failed in $dest; run '$shown' there manually" >&2
  fi
}

# PR worktrees never install: the PR's own .npmrc, packageManager and scripts would run its author's code. Sets $deps and tells how to install by hand.
skip_pr_deps() {
  local dest="$1" pm sub
  deps=skipped
  detect_pm "$dest"
  [ -z "$pm" ] || echo "th-wt: warning: dependencies not installed: PR code is untrusted; if you trust it, run '$pm ${sub[*]}' in $dest" >&2
}

# Indexes worktree $1 with codegraph if installed and not disabled (TH_CODEGRAPH=off); sets $codegraph. A failed init only warns: the worktree is already there.
index_codegraph() {
  local dest="$1"
  codegraph=false
  [ "$codegraph_mode" = off ] && return 0
  command -v codegraph >/dev/null || return 0
  # a link (e.g. from the repo .conf) or committed files other than a regular .gitignore (a symlink would be written through): init would say "Already initialized" and index nothing, or reuse a crafted db
  if [ -L "$dest/.codegraph" ] || { [ -e "$dest/.codegraph" ] && { [ ! -d "$dest/.codegraph" ] || [ -n "$(find "$dest/.codegraph" -mindepth 1 -maxdepth 1 ! \( -name .gitignore -type f \) -print -quit)" ]; }; }; then
    echo "th-wt: warning: .codegraph already exists in $dest; not indexed" >&2
    return 0
  fi
  echo "th-wt: indexing with codegraph (may take a few minutes)" >&2
  # stdout is reserved for --json and there is no terminal to answer prompts
  # codegraph's telemetry and update check are network access: opt-in only
  # empty NO_WATCH: codegraph installs git hooks in the shared .git only when it is '1'; empty DIR: the kit checks .codegraph
  if CODEGRAPH_TELEMETRY=0 CODEGRAPH_NO_UPDATE_CHECK=1 CODEGRAPH_NO_WATCH='' CODEGRAPH_DIR='' codegraph init -y "$dest" >&2 </dev/null; then
    codegraph=true
  else
    echo "th-wt: warning: codegraph init failed in $dest; run 'codegraph init -y' there manually" >&2
  fi
}

# Prints the created worktree object as JSON; needs $repo, $deps, $codegraph and $linked.
print_created_json() {
  # ${linked[@]+...}: bash 3.2 fails on an empty or unset array under set -u (pr and review/pr-* never set it)
  # not --args: jq would take a path starting with '-' as an option; paths cannot contain newlines (they come from read lines); with no paths printf emits one empty line, hence the select
  jq -n --arg path "$1" --arg branch "$2" --arg repo "$repo" --arg deps "$deps" --argjson codegraph "$codegraph" --argjson linked "$(printf '%s\n' ${linked[@]+"${linked[@]}"} | jq -nRc '[inputs | select(length > 0)]')" '{path: $path, branch: $branch, repo: $repo, linked: $linked, deps: $deps, codegraph: $codegraph}'
}

# Prints the created worktree summary to stderr (the text counterpart of print_created_json); needs $deps, $codegraph and $linked.
print_created_summary() {
  local l="" p cg="not indexed"
  for p in ${linked[@]+"${linked[@]}"}; do l="${l:+$l, }$p"; done
  [ "$codegraph" != true ] || cg=indexed
  printf '  path:      %s\n  branch:    %s\n  linked:    %s\n  deps:      %s\n  codegraph: %s\n' "$1" "$2" "${l:-none}" "$deps" "$cg" >&2
}

# Local default branch (e.g. origin/main) from refs/remotes/origin/HEAD; empty if unset. Offline.
local_default_branch() { git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true; }

# Prints origin's default branch (empty if origin's HEAD is not a symref); fails only if origin cannot be read.
origin_default_branch() {
  local head_ref
  head_ref="$(git ls-remote --symref origin HEAD)" || return 1
  printf '%s\n' "$head_ref" | awk '/^ref:/ { sub("refs/heads/", "", $2); print $2 }'
}

# Fetches origin's branch $1 into refs/remotes/origin/$1; the caller decides the exit code.
fetch_origin_branch() {
  git fetch -q --no-tags origin "+refs/heads/$1:refs/remotes/origin/$1"
}

# --remote prelude shared by list and close: checks gh, fetches origin's default branch and reads PRs. Sets $default (origin/<branch>) and $prs in the caller; needs $repo. $1 = PR limit, $2 = only PRs from this head branch (optional).
load_remote() {
  local limit="${1:-$pr_limit}" head="${2:-}" base filter=()
  [ -z "$head" ] || filter=(--head "$head")
  command -v gh >/dev/null || die 3 "missing dependency: gh"
  base="$(origin_default_branch)" || die 4 "cannot read origin (unreachable or no access)"
  [ -n "$base" ] || die 4 "cannot determine origin's default branch"
  fetch_origin_branch "$base" || die 4 "fetch of origin/$base failed"
  default="origin/$base"
  # ${filter[@]+...}: bash 3.2 fails on an empty array under set -u
  prs="$(gh pr list -R "$repo" --state all --limit "$limit" ${filter[@]+"${filter[@]}"} --json number,state,baseRefName,headRefName,headRefOid,isCrossRepository)" || die 4 "gh pr list failed (not authenticated, or no access to GitHub or $repo?)"
  jq -e 'type == "array" and all(.[]; type == "object")' <<<"$prs" >/dev/null 2>&1 || die 4 "unexpected output from gh pr list"
}

# git status of worktree $1 (more git status flags after it) as \1-separated entries, without what codegraph leaves in .codegraph/: its untracked dir and its ignored files. Tracked changes there (it may have a committed .gitignore) still show. tr because $(...) drops NUL bytes.
wt_status() {
  local path="$1"
  shift
  git --no-optional-locks -C "$path" status --porcelain -z "$@" | tr '\0' '\1' | awk 'BEGIN { RS = ORS = "\001" } !/^([?][?] \.codegraph\/|!! \.codegraph(\/.*)?)$/'
}

# One JSON object per line for each worktree under $1, only the one on branch $5 if given (kept out of $(...): bash 3.2 mis-parses case inside it).
list_rows() {
  local root="$1" default="$2" prs="$3" remote="$4" only="${5:-}" path line head dirty missing ref name merged rc out pr oid ahead
  git worktree list --porcelain | while IFS= read -r line; do
    case "$line" in
      "worktree "*) path="${line#worktree }" ;;
      "HEAD "*) head="${line#HEAD }" ;;
      "branch "*|detached)
        case "$path" in "$root"*) ;; *) continue ;; esac
        if [ "$line" = detached ]; then
          ref="$head"
          name=""
        else
          ref="${line#branch }"
          name="${ref#refs/heads/}"
        fi
        [ -z "$only" ] || [ "$name" = "$only" ] || continue
        dirty=false
        missing=false
        if [ -d "$path" ]; then
          if out="$(wt_status "$path" --untracked-files=normal 2>/dev/null)"; then
            [ -z "$out" ] || dirty=true
          else
            dirty=null
          fi
        else
          missing=true
          dirty=null
        fi
        merged=null
        if [ -n "$default" ]; then
          rc=0
          git merge-base --is-ancestor "$ref" "$default" 2>/dev/null || rc=$?
          # 0 = ancestor, 1 = not; anything else (unborn branch, missing default) = unknown
          case "$rc" in 0) merged=true ;; 1) merged=false ;; esac
        fi
        pr=null
        ahead=null
        # the PR is looked up once per row, and only for branches git does not already contain
        if [ "$remote" = true ] && [ -n "$name" ] && [ "$merged" != true ]; then
          pr="$(jq -c --arg b "$name" '[.[] | select(.headRefName == $b and (.isCrossRepository | not))] | max_by(.number)' <<<"$prs")"
          oid="$(jq -r '.headRefOid // empty' <<<"$pr")"
          if [ -n "$oid" ]; then
            rc=0
            git merge-base --is-ancestor "$ref" "$oid" 2>/dev/null || rc=$?
            # 0 = ancestor, 1 = local commits after the PR head; anything else (no PR head, or not fetched) = unknown
            case "$rc" in 0) ahead=false ;; 1) ahead=true ;; esac
          fi
        fi
        jq -cn --arg path "$path" --arg branch "$name" --argjson dirty "$dirty" --argjson merged "$merged" --argjson missing "$missing" --argjson remote "$remote" --argjson pr "$pr" --argjson ahead "$ahead" \
          '{path: $path, branch: (if $branch == "" then null else $branch end), dirty: $dirty, merged: $merged, missing: $missing}
           + if $remote then {pr: ($pr | if . == null then null else {number, state, base: .baseRefName, ahead: $ahead} end)} else {} end' ;;
    esac
  done
}
