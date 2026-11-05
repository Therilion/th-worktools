# shellcheck shell=bash

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

# Sets $repo (<owner>/<repo>) from remote.origin.url.
resolve_repo() {
  local url
  git rev-parse --git-dir >/dev/null 2>&1 || die 4 "not a git repository"
  url="$(git config --get remote.origin.url || true)"
  [ -n "$url" ] || die 4 "no 'origin' remote configured"
  repo="$(printf '%s' "$url" | sed -E 's#^(git@[^:]+:|https?://[^/]+/)##; s#\.git$##')"
  case "/$repo/" in
    *[:@]*|*//*|*/./*|*/../*) die 4 "unsupported origin URL: $url" ;;
    /*/*/) ;;
    *) die 4 "unsupported origin URL: $url" ;;
  esac
}

# shortcut: root is compared with git's real paths without resolving symlinks, so a symlinked ~/.worktrees or $HOME lists nothing; canonicalize both sides with #8 (configurable root)
# Where this repo's worktrees live; needs $repo from resolve_repo.
worktrees_root() { printf '%s' "$HOME/.worktrees/$repo/"; }

# Sets $dest for branch $1 and checks it does not already exist; needs $repo.
worktree_dest() {
  local name="${1//\//-}"
  # pr-reviews/ holds the PR worktrees; the check is on the normalized name so pr/reviews is reserved too
  [ "$name" != pr-reviews ] || die 2 "reserved branch name: $1 (pr-reviews is where PR worktrees live)"
  dest="$(worktrees_root)$name"
  [ ! -e "$dest" ] || die 4 "destination already exists: $dest"
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
  local dest="$1" pm sub
  deps=skipped
  detect_pm "$dest"
  [ -n "$pm" ] || return 0
  if ! command -v "$pm" >/dev/null; then
    echo "th-wt: warning: $pm not found in PATH; skipping dependency install in $dest" >&2
    return 0
  fi
  # stdout is reserved for --json and there is no terminal to answer prompts
  if (cd "$dest" && "$pm" "${sub[@]}" >&2 </dev/null); then
    deps="$pm"
  else
    deps=failed
    echo "th-wt: warning: $pm install failed in $dest; run it there manually" >&2
  fi
}

# PR worktrees never install: the PR's own .npmrc, packageManager and scripts would run its author's code. Sets $deps and tells how to install by hand.
skip_pr_deps() {
  local dest="$1" pm sub
  deps=skipped
  detect_pm "$dest"
  [ -z "$pm" ] || echo "th-wt: warning: dependencies not installed: PR code is untrusted; if you trust it, run '$pm ${sub[*]}' in $dest" >&2
}

# Prints the created worktree object as JSON; needs $repo and $deps.
print_created_json() {
  jq -n --arg path "$1" --arg branch "$2" --arg repo "$repo" --arg deps "$deps" '{path: $path, branch: $branch, repo: $repo, deps: $deps}'
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
  local limit="$1" head="${2:-}" base filter=()
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
          if out="$(git --no-optional-locks -C "$path" status --porcelain --untracked-files=normal 2>/dev/null)"; then
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
