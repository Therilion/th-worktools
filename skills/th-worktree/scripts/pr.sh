# shellcheck shell=bash
# shellcheck source=lib.sh source-path=SCRIPTDIR
# shellcheck disable=SC2154 # $repo is set by resolve_repo in lib.sh

pr_worktree() {
  local n json=0 dest meta oid fetched base shown_base
  # title and branch names come from the PR author: strip control characters (C0, DEL, C1) so they cannot drive the terminal
  local clean='def clean: explode | map(if . < 32 or . == 127 or (. >= 128 and . < 160) then 32 else . end) | implode;'
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
  [ ! -e "$dest" ] || die 4 "destination already exists: $dest"
  ! git show-ref --verify --quiet "refs/heads/review/pr-$n" || die 4 "branch already exists: review/pr-$n"
  command -v gh >/dev/null || die 3 "missing dependency: gh"

  meta="$(gh pr view "$n" -R "$repo" --json number,title,headRefName,baseRefName,headRefOid)" || die 4 "PR not found, not authenticated, or no access?"
  jq -e 'type == "object" and (.number | type == "number") and all(.title, .headRefName, .baseRefName; type == "string") and (.baseRefName | length > 0) and (.headRefOid | type == "string" and test("^([0-9a-f]{40}|[0-9a-f]{64})$"))' <<<"$meta" >/dev/null 2>&1 || die 4 "unexpected output from gh pr view"
  base="$(jq -r .baseRefName <<<"$meta")"
  # base goes into a refspec: refuse anything git would not accept as a branch name
  git check-ref-format "refs/heads/$base" || die 4 "unexpected output from gh pr view"
  # check-ref-format accepts C1 characters: messages use the cleaned name
  shown_base="$(jq -r "$clean .baseRefName | clean" <<<"$meta")"
  echo "th-wt: fetching origin refs/pull/$n/head" >&2
  git fetch -q --no-tags origin "refs/pull/$n/head" || die 4 "fetch of PR #$n failed (origin unreachable, no access, or the PR has no head ref)"
  # FETCH_HEAD is shared state (the base fetch below, an IDE auto-fetch...): trust only what gh reports, and only if the fetch brought exactly that commit
  oid="$(jq -r .headRefOid <<<"$meta")"
  fetched="$(git rev-parse FETCH_HEAD)"
  [ "$fetched" = "$oid" ] || die 4 "PR #$n head changed while opening it (gh: $oid, fetched: $fetched); try again"
  echo "th-wt: fetching origin/$shown_base" >&2
  fetch_origin_branch "$base" || die 4 "fetch of origin/$shown_base failed"
  add_branch_worktree "review/pr-$n" "$dest" "$oid"
  skip_pr_deps "$dest"
  index_codegraph "$dest"

  if [ "$json" = 1 ]; then
    print_created_json "$dest" "review/pr-$n" | jq -c --argjson m "$meta" '. + {pr: {number: $m.number, title: $m.title, head: $m.headRefName, base: $m.baseRefName}}'
  else
    jq -r --arg path "$dest" --arg deps "$deps" --argjson cg "$codegraph" "$clean"'
      "  path:      \($path)\n  PR:        #\(.number) \(.title | clean)\n  branch:    \(.headRefName | clean)\n  base:      \(.baseRefName | clean)\n  deps:      \($deps)\n  codegraph: \(if $cg then "indexed" else "not indexed" end)"' <<<"$meta" >&2
  fi
}
