#!/usr/bin/env bash
set -euo pipefail

src="${BASH_SOURCE[0]}"
case "$src" in */*) ;; *) src="./$src" ;; esac
while [ -L "$src" ]; do
  dir="$(cd -P "${src%/*}" && pwd)"
  src="$(readlink "$src")"
  case "$src" in /*) ;; *) src="$dir/$src" ;; esac
done
SELF_DIR="$(cd -P "${src%/*}" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$SELF_DIR/lib.sh"

usage() {
  cat <<'USAGE'
Usage: verify.sh [--agents <list>]
       verify.sh -h | --help

Check, without changing anything, that the kit installed by install.sh is complete: the fixed kit path ~/.local/share/th-worktools, each skills/th-*/ in the chosen agents' skills directories, each entrypoint in ~/.local/bin, and the required dependencies (git, jq).

--agents <list>  Comma-separated agents to check (supported: claude, agy). Default: the supported agents found in PATH.

Exit 0 if everything is ok, 2 on bad usage or an unsupported agent, 3 if a required dependency or a requested agent is not in PATH, 4 if anything else failed.
USAGE
}

err() { echo "verify.sh: $*" >&2; }
die() { local code="$1"; shift; err "$*"; exit "$code"; }
bad_usage() { err "$1"; usage >&2; exit 2; }

AGENTS_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --agents)
      [ -n "${2:-}" ] || bad_usage "--agents needs a comma-separated list of agents"
      AGENTS_ARG="$2"
      shift ;;
    *) bad_usage "unknown option: $1" ;;
  esac
  shift
done

pick_agents "$AGENTS_ARG"
if [ -z "$AGENTS_ARG" ] && [ -z "$AGENTS" ]; then
  err "warning: no supported agent found in PATH (claude, agy); checking only the kit path and entrypoints"
fi

PROBLEMS=0
DEPS_MISSING=0

# why_bad <dest> <target> [real-ok]: sets WHY to the cause, or "" if dest resolves to target. A real directory only passes with real-ok.
why_bad() {
  local dest="$1" target="$2" r
  WHY=""
  if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
    WHY="missing"
  elif [ -L "$dest" ] && ! r="$(resolve "$dest")"; then
    WHY="broken symlink"
  elif [ ! -L "$dest" ] && [ -z "${3:-}" ]; then
    WHY="not a symlink"
  else
    r="$(resolve "$dest")"
    [ "$r" = "$target" ] || WHY="points outside the kit: $r"
  fi
}

# line <dest> [why]: prints ok, or fail with its cause, and counts the problem.
line() {
  if [ -z "${2:-}" ]; then
    printf '%-6s %s\n' ok "$1" >&2
  else
    printf '%-6s %s\n' fail "$1 ($2)" >&2
    PROBLEMS=$((PROBLEMS + 1))
  fi
}

why_bad "$KIT_PATH" "$SELF_DIR" real-ok
line "$KIT_PATH" "$WHY"

for skill in "$SELF_DIR"/skills/th-*/; do
  [ -d "$skill" ] || continue
  skill="${skill%/}"
  skill="${skill##*/}"
  declared="$(awk '/^---$/ { n++; next } n == 1 && /^name:/ { sub(/^name:[ ]*/, ""); print; exit }' "$SELF_DIR/skills/$skill/SKILL.md" 2>/dev/null || true)"
  for a in $AGENTS; do
    dest="$(agent_dir "$a")/$skill"
    why_bad "$dest" "$SELF_DIR/skills/$skill"
    if [ -z "$WHY" ] && [ "$declared" != "$skill" ]; then WHY="name '$declared' does not match its folder"; fi
    line "$dest" "$WHY"
  done
done

for skill in "$SELF_DIR"/skills/th-*/; do
  [ -d "$skill" ] || continue
  skill="${skill%/}"
  skill="${skill##*/}"
  for f in "$SELF_DIR/skills/$skill/scripts/"*; do
    { [ -f "$f" ] && [ -x "$f" ]; } || continue
    why_bad "$BIN_DIR/${f##*/}" "$SELF_DIR/skills/$skill/scripts/${f##*/}"
    line "$BIN_DIR/${f##*/}" "$WHY"
  done
done

for dep in git jq; do
  if command -v "$dep" >/dev/null; then
    printf '%-6s %s\n' ok "$dep" >&2
  else
    printf '%-6s %s\n' fail "$dep (not found in PATH)" >&2
    DEPS_MISSING=1
  fi
done

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) err "warning: $BIN_DIR is not in PATH; th-wt will not run from the terminal" ;;
esac

if [ "$PROBLEMS" -gt 0 ]; then
  err "$PROBLEMS problem(s) found; run install.sh --yes (install.sh --link-here --yes from the clone if the kit path is missing)"
elif [ "$DEPS_MISSING" = 0 ]; then
  err "all ok"
fi
[ "$DEPS_MISSING" = 0 ] || exit 3
[ "$PROBLEMS" = 0 ] || exit 4
