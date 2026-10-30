# shellcheck shell=bash

die() { echo "th-wt: $2" >&2; exit "$1"; }
bad_usage() { usage >&2; exit 2; }

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
