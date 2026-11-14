# shellcheck shell=bash
# shellcheck source=lib.sh source-path=SCRIPTDIR
# shellcheck disable=SC2154 # $repo is set by resolve_repo in lib.sh

# True if $1 is a symlink pointing exactly to $2.
is_conf_link() { [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]; }

link_worktree() {
  local branch root row path i p dest conf_path json reason l
  case "${1:-}" in
    "") bad_usage "missing <branch>" ;;
    -h|--help) usage; exit 0 ;;
    -*) bad_usage "expected <branch> first, got option: $1 (options go after <branch>)" ;;
  esac
  branch="$1"
  shift
  json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1; shift ;;
      *) bad_arg "$1" ;;
    esac
  done

  git check-ref-format "refs/heads/$branch" || die 2 "invalid branch name: $branch"
  [ "$branch" != HEAD ] || die 2 "invalid branch name: $branch"

  resolve_repo
  case "$branch" in review/pr-*) die 4 "$branch is a PR copy (review/pr-*): the repo .conf is never applied to PR code" ;; esac
  root="$(worktrees_root)"
  row="$(list_rows "$root" "" null false "$branch" | head -n 1)"
  [ -n "$row" ] || die 4 "no worktree for branch $branch under $root"
  path="$(jq -r .path <<<"$row")"

  [ "$(jq -r .missing <<<"$row")" = false ] || die 4 "worktree directory of $branch no longer exists: $path"

  read_repo_conf
  if [ -z "$conf_file" ]; then
    conf_path="${XDG_CONFIG_HOME:-$HOME/.config}/th-worktools/repos/$repo.conf"
    echo "th-wt: no repo config ($conf_path); nothing to link" >&2
  else
    echo "th-wt: applying repo config $conf_file" >&2
    dest="$path"
    # validate every entry before linking any
    for ((i = 0; i < ${#conf_paths[@]}; i++)); do
      p="${conf_paths[$i]}"
      check_conf_worktree "$p" "$dest" || die 4 "$conf_file:${conf_nums[$i]}: $reason"
      if { [ -e "$dest/$p" ] || [ -L "$dest/$p" ]; } && ! is_conf_link "$dest/$p" "$conf_main/$p"; then
        die 4 "$conf_file:${conf_nums[$i]}: $p already exists in the worktree (not a link to $conf_main/$p)"
      fi
    done
    for ((i = 0; i < ${#conf_paths[@]}; i++)); do
      p="${conf_paths[$i]}"
      ! is_conf_link "$dest/$p" "$conf_main/$p" || continue
      { mkdir -p "$(dirname "$dest/$p")" && ln -s "$conf_main/$p" "$dest/$p"; } || die 1 "cannot link $p in $dest"
      linked+=("$p")
      echo "th-wt: linked $p" >&2
    done
  fi

  if [ "$json" = 1 ]; then
    jq -n --arg path "$path" --arg branch "$branch" --arg repo "$repo" --argjson linked "$(printf '%s\n' ${linked[@]+"${linked[@]}"} | jq -nRc '[inputs | select(length > 0)]')" '{path: $path, branch: $branch, repo: $repo, linked: $linked}'
  else
    p=""
    for l in ${linked[@]+"${linked[@]}"}; do p="${p:+$p, }$l"; done
    printf '  path:      %s\n  branch:    %s\n  linked:    %s\n' "$path" "$branch" "${p:-none}" >&2
  fi
}
